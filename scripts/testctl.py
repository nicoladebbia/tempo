#!/usr/bin/env python3
"""testctl.py — control the local test server's test-only features.

Called by scripts/testenv.sh (`testenv.sh fault ...` etc.); runnable directly.
Talks to /v1/test/* on the server testenv.sh started (TEMPO_TEST_URL or
http://127.0.0.1:58080).

  fault add <path-prefix> <kind> [value] [--count N] [--method GET] [--as NAME]
        kinds: error [status] | slow [secs] | logout | garbage | empty | timeout
  fault list | fault clear [id]
  auth ttl <seconds|off>          shorter access tokens (silent re-login)
  sign-out <name>                 revoke every session of a test user
"""

import json
import os
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


COMMANDS = {"users": cmd_users, "fault": cmd_fault, "auth": cmd_auth, "sign-out": cmd_sign_out}


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
