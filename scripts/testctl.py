#!/usr/bin/env python3
"""testctl.py — control the local test server's test-only features.

Called by scripts/testenv.sh (`testenv.sh fault ...` etc.); runnable directly.
Talks to /v1/test/* on this worktree's server (testenv.sh passes TEMPO_TEST_URL;
default http://127.0.0.1:58080, the main checkout's).

  fault add <path-prefix> <kind> [value] [--count N] [--method GET] [--as NAME]
        kinds: error [status] | slow [secs] | logout | garbage | empty | timeout
  fault list | fault clear [id]
  auth ttl <seconds|off>          shorter access tokens (silent re-login)
  sign-out <name>                 revoke every session of a test user
  time                            what time the server thinks it is
  time set <when> | +<n><m|h|d> | -<n><m|h|d> | reset
        when: "sunday 19:55", "tomorrow 08:20", "2026-10-04 08:20" (your local time)
  job run <job> [--as NAME] [--force]
        jobs: morning-briefing weekly-summary drill-sergeant leaderboard-refresh
              notifications-cleanup   (--force: briefing outside 08:15-08:45 / again today)
  sub <name> <state> [--days N]   server-side subscription state
        states: free trial active cancelled grace billing-retry expired refunded
  persona <name> <persona>        server half of a person with history
        personas: athlete picky-vegan exam-week injured lapsed-pro
  shared <name>                   the user's live grocery share links (open as the shopper)
"""

import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ.get("TEMPO_TEST_URL", "http://127.0.0.1:58080")


def die(msg):
    print(f"[testctl] {msg}", file=sys.stderr)
    sys.exit(1)


def call(method, path, body=None, query=None):
    url = URL + path + ("?" + urllib.parse.urlencode(query) if query else "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            raw = res.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            detail = json.loads(detail).get("reason", detail)
        except ValueError:
            pass
        die(f"{method} {path} → {e.code}: {detail}")
    except urllib.error.URLError:
        die(f"test server not reachable at {URL} — run scripts/testenv.sh up")
    return json.loads(raw) if raw.strip() else None


def take_flag(args, flag, default=None):
    if flag in args:
        i = args.index(flag)
        if i + 1 >= len(args):
            die(f"{flag} needs a value")
        value = args[i + 1]
        del args[i : i + 2]
        return value
    return default


def user_id(name):
    """Test login name → user id (the server maps it)."""
    users = call("GET", "/v1/test/users", query={"name": name}) or []
    if not users:
        die(f"no test user '{name}' (sign in once with sim.sh qa --local --as {name})")
    return users[0]["id"]


def show_faults(rules):
    if not rules:
        print("no faults — every request behaves normally")
    for r in rules:
        extra = r.get("status") or r.get("delay_seconds") or ""
        scope = []
        if r.get("method"):
            scope.append(r["method"])
        if r.get("remaining") is not None:
            scope.append(f"{r['remaining']} left")
        if r.get("user_id"):
            scope.append(f"user {r['user_id']}")
        print(
            f"{r['id'][:8]}  {r['path_prefix']:<28} {r['kind']} {extra}  {' · '.join(scope)}  (hit {r.get('hits', 0)}×)"
        )


def cmd_fault(args):
    if not args or args[0] == "list":
        show_faults(call("GET", "/v1/test/faults"))
    elif args[0] == "clear":
        if len(args) > 1:
            match = [
                r["id"]
                for r in call("GET", "/v1/test/faults")
                if r["id"].startswith(args[1])
            ]
            if not match:
                die(f"no fault {args[1]}")
            call("DELETE", "/v1/test/faults", query={"id": match[0]})
        else:
            call("DELETE", "/v1/test/faults")
        show_faults(call("GET", "/v1/test/faults"))
    elif args[0] == "add":
        args = args[1:]
        count = take_flag(args, "--count")
        method = take_flag(args, "--method")
        name = take_flag(args, "--as")
        if len(args) < 2:
            die(
                "usage: fault add <path-prefix> <kind> [value] [--count N] [--method GET] [--as NAME]"
            )
        rule = {"path_prefix": args[0], "kind": args[1]}
        if len(args) > 2:
            if args[1] == "error":
                rule["status"] = int(args[2])
            elif args[1] == "slow":
                rule["delay_seconds"] = float(args[2])
        if count:
            rule["remaining"] = int(count)
        if method:
            rule["method"] = method.upper()
        if name:
            rule["user_id"] = user_id(name)
        call("POST", "/v1/test/faults", rule)
        show_faults(call("GET", "/v1/test/faults"))
    else:
        die("fault add | list | clear")


def cmd_auth(args):
    if len(args) != 2 or args[0] != "ttl":
        die("usage: auth ttl <seconds|off>")
    seconds = 0 if args[1] == "off" else float(args[1])
    res = call("POST", "/v1/test/auth", {"access_ttl_seconds": seconds})
    print(
        f"new access tokens last {int(res['access_ttl_seconds'])} s (tokens already issued keep theirs)"
    )


def cmd_sign_out(args):
    if len(args) != 1:
        die("usage: sign-out <name>")
    call("POST", "/v1/test/sign-out", query={"name": args[0]})
    print(f"revoked every session of {args[0]} — the app's next refresh fails")


def cmd_users(args):
    rows = call("GET", "/v1/test/users", query={"name": args[0]} if args else None) or []
    for u in rows:
        print(f"{u['name']:<28} {u['id']}  {'Pro ' if u['pro'] else 'free'}  {u.get('simulator_udid') or ''}")
    if not rows:
        print("no test users yet")


WEEKDAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def parse_when(text, now=None):
    """'sunday 19:55' | 'tomorrow 8:20' | 'today 23:59' | '2026-10-04 08:20' → aware local datetime."""
    now = now or dt.datetime.now().astimezone()
    words = text.lower().split()
    clock = dt.time(now.hour, now.minute)
    if words and re.fullmatch(r"\d{1,2}:\d{2}", words[-1]):
        h, m = map(int, words.pop().split(":"))
        if h > 23 or m > 59:
            die(f"bad time {h}:{m:02d}")
        clock = dt.time(h, m)
    day = now.date()
    if not words or words == ["today"]:
        pass
    elif words == ["tomorrow"]:
        day += dt.timedelta(days=1)
    elif words == ["yesterday"]:
        day -= dt.timedelta(days=1)
    elif len(words) == 1 and words[0] in WEEKDAYS:
        # The next one (today counts if it's that day).
        day += dt.timedelta(days=(WEEKDAYS.index(words[0]) - now.weekday()) % 7)
    elif len(words) == 1 and re.fullmatch(r"\d{4}-\d{2}-\d{2}", words[0]):
        day = dt.date.fromisoformat(words[0])
    else:
        die(f"can't read '{text}' — try 'sunday 19:55', 'tomorrow 08:20' or '2026-10-04 08:20'")
    return dt.datetime.combine(day, clock).astimezone()


def parse_shift(text):
    """'+2d' | '-3h' | '+90m' → seconds, or None."""
    m = re.fullmatch(r"([+-])(\d+(?:\.\d+)?)([mhd])", text)
    if not m:
        return None
    return (1 if m[1] == "+" else -1) * float(m[2]) * {"m": 60, "h": 3600, "d": 86400}[m[3]]


def show_clock(res):
    when = dt.datetime.fromisoformat(res["now"].replace("Z", "+00:00")).astimezone()
    offset = res["offset_seconds"]
    if abs(offset) < 1:
        print(f"server time: {when:%a %d %b %H:%M} (real time)")
    else:
        sign = "+" if offset > 0 else "-"
        offset = abs(offset)
        print(
            f"server time: {when:%a %d %b %H:%M}  ({sign}{int(offset // 86400)}d {int(offset % 86400 // 3600)}h "
            f"{int(offset % 3600 // 60)}m from real time — 'time reset' to go back)"
        )


def cmd_time(args):
    if not args:
        show_clock(call("GET", "/v1/test/clock"))
    elif args[0] == "reset":
        show_clock(call("POST", "/v1/test/clock", {"reset": True}))
    elif len(args) == 1 and parse_shift(args[0]) is not None:
        show_clock(call("POST", "/v1/test/clock", {"advance_seconds": parse_shift(args[0])}))
    elif args[0] == "set" and len(args) > 1:
        when = parse_when(" ".join(args[1:]))
        show_clock(call("POST", "/v1/test/clock", {"set": when.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}))
    else:
        die("usage: time | time set <when> | time +2d | time -3h | time reset")


def cmd_job(args):
    if len(args) < 2 or args[0] != "run":
        die("usage: job run <job> [--as NAME] [--force]")
    args = args[1:]
    name = take_flag(args, "--as")
    force = "--force" in args
    args = [a for a in args if a != "--force"]
    body = {"job": args[0], "force": force}
    if name:
        body["name"] = name
    res = call("POST", "/v1/test/jobs/run", body)
    who = f" for {name}" if name else ""
    when = dt.datetime.fromisoformat(res["now"].replace("Z", "+00:00")).astimezone()
    done = f"{res['affected']} user(s)" if res.get("affected") is not None else "done"
    print(f"ran {res['job']}{who} at server time {when:%a %d %b %H:%M} → {done}")
    if res["job"] == "morning-briefing" and res.get("affected") == 0 and not force:
        print("  nobody was in their 08:15–08:45 window or everyone had today's — add --force")


def cmd_sub(args):
    days = take_flag(args, "--days")
    if len(args) != 2:
        die("usage: sub <name> <free|trial|active|cancelled|grace|billing-retry|expired|refunded> [--days N]")
    body = {"name": args[0], "state": args[1]}
    if days:
        body["days"] = float(days)
    res = call("POST", "/v1/test/subscription", body)
    line = f"{res['name']}: {res['state']} → {'Pro' if res['pro'] else 'not Pro'}"
    if res.get("expires_at"):
        when = dt.datetime.fromisoformat(res["expires_at"].replace("Z", "+00:00")).astimezone()
        line += f", ends {when:%a %d %b %H:%M} (server time)"
    print(line)


def cmd_persona(args):
    if len(args) != 2:
        die("usage: persona <name> <athlete|picky-vegan|exam-week|injured|lapsed-pro>")
    r = call("POST", "/v1/test/persona", {"name": args[0], "persona": args[1]})
    print(
        f"{args[0]} is now {r['persona']}: {r['xp_events']} XP events ({r['xp_total']} XP), "
        f"{r['receipts']} receipts, {r['streak_days']}-day streak, {'Pro' if r['pro'] else 'not Pro'}"
    )


def cmd_shared(args):
    if len(args) != 1:
        die("usage: shared <name>")
    rows = call("GET", "/v1/test/shared", query={"name": args[0]}) or []
    for r in rows:
        print(f"{r['title']:<30} {r['items']:>3} items  {r['url']}")
    if not rows:
        print(f"{args[0]} isn't sharing a grocery list (Groceries → Share in the app)")


COMMANDS = {
    "persona": cmd_persona,
    "shared": cmd_shared,
    "sub": cmd_sub,
    "users": cmd_users,
    "fault": cmd_fault,
    "auth": cmd_auth,
    "sign-out": cmd_sign_out,
    "time": cmd_time,
    "job": cmd_job,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        print(__doc__.strip())
        return
    cmd = COMMANDS.get(sys.argv[1])
    if not cmd:
        die(f"unknown command '{sys.argv[1]}' (try: help)")
    cmd(sys.argv[2:])


if __name__ == "__main__":
    main()
