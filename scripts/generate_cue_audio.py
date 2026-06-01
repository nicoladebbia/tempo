#!/usr/bin/env python3
"""
Generate the bundled premium voice cue clips for Tempo's workout audio cues.

ONE-SHOT script: run once with an ElevenLabs API key to produce the .mp3 clips,
then the clips are committed as app resources and this script can be deleted
(git keeps it). It pre-renders only the CLOSED cue vocabulary:
  - 5 countdown phrases (ten-seconds warning, 3, 2, 1, go)
  - the fixed warm-up move names authored in WarmupRoutine.swift

It does NOT touch the exercise library — working-set exercise names are an open
set (custom exercises) and use the on-device Apple voice fallback at runtime.

Usage:
  export ELEVENLABS_API_KEY=sk_...
  python3 scripts/generate_cue_audio.py [--voice <voice_id>]

Output: Tempo/Tempo/Resources/CueAudio/*.mp3  (slugs match CueAudioPlayer +
WarmupMove.slug exactly).

NOTE (App Store): verify your ElevenLabs plan permits owning and redistributing
generated audio inside a commercial app before shipping these clips.
"""

import argparse
import os
import re
import sys
import urllib.request

OUT_DIR = os.path.join(
    os.path.dirname(__file__), "..", "Tempo", "Tempo", "Resources", "CueAudio"
)
# Default voice — "Harry - Fierce Warrior" (premade; works on free tier and
# fits Tempo's drill-sergeant tone). Override with --voice. NOTE: library
# voices (non-premade) require a paid plan via the API (free → HTTP 402).
DEFAULT_VOICE = "SOYHLrjzK2X1ezoPC6cr"  # Harry — Fierce Warrior

# Countdown vocabulary → (clip slug, spoken text). Matches WarmupCue.clipName.
# The ten-seconds cue ENDS on "ten seconds, get set" — it is fired early so the
# "ten seconds" lands right as the 10s countdown begins (see lead-time in
# TrainingViewModel.cue). Trailing punctuation adds a natural slow cadence.
COUNTDOWN = {
    "cue_ten_seconds": "Almost time... ten seconds, get set.",
    "cue_three": "Three.",
    "cue_two": "Two.",
    "cue_one": "One.",
    "cue_go": "Go.",
}


def slug(name: str) -> str:
    """Mirror WarmupMove.slug exactly."""
    s = re.sub(r"[^a-z0-9]+", "_", name.lower())
    return s.strip("_")


def exercise_names(exercises_json: str) -> list[str]:
    """Built-in (seeded) exercise names — a closed set. Custom exercises the
    user adds later have no clip and use the Apple fallback at runtime."""
    import json

    data = json.load(open(exercises_json))
    items = data if isinstance(data, list) else data.get("exercises", [])
    out = []
    for it in items:
        n = it.get("name")
        if n and n not in out:
            out.append(n)
    return out


def warmup_move_names(routine_path: str) -> list[str]:
    text = open(routine_path).read()
    names = re.findall(r'name:\s*"([^"]+)"', text)
    # Drop the struct's own field doc occurrences (name is also a property);
    # only WarmupMove(name: "...") calls have a following dose: line, but the
    # simplest robust filter is uniqueness + excluding the single-word field.
    seen = []
    for n in names:
        if n not in seen and len(n) > 2:
            seen.append(n)
    return seen


def synth(text: str, out_path: str, voice: str, key: str, speed: float = 1.0) -> None:
    import json as _json

    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice}"
    payload = {
        "text": text,
        "model_id": "eleven_multilingual_v2",
        # speed < 1.0 slows delivery (range ~0.7–1.2). Clearer over gym noise.
        "voice_settings": {"stability": 0.5, "similarity_boost": 0.75, "speed": speed},
    }
    body = _json.dumps(payload)
    req = urllib.request.Request(
        url,
        data=body.encode("utf-8"),
        headers={
            "xi-api-key": key,
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        audio = resp.read()
    with open(out_path, "wb") as f:
        f.write(audio)
    print(f"  wrote {os.path.basename(out_path)} ({len(audio)} bytes)")


def _json_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--voice", default=DEFAULT_VOICE)
    ap.add_argument(
        "--only", nargs="*", default=None,
        help="regenerate only these clip slugs (e.g. cue_ten_seconds)",
    )
    args = ap.parse_args()

    key = os.environ.get("ELEVENLABS_API_KEY")
    if not key:
        print("ERROR: set ELEVENLABS_API_KEY", file=sys.stderr)
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    routine = os.path.join(
        os.path.dirname(__file__),
        "..", "Tempo", "Tempo", "Models", "Training", "WarmupRoutine.swift",
    )

    exercises = os.path.join(
        os.path.dirname(__file__),
        "..", "Tempo", "Tempo", "Resources", "Exercises.json",
    )

    clips: dict[str, str] = dict(COUNTDOWN)
    for name in warmup_move_names(routine):
        clips[f"cue_move_{slug(name)}"] = name + "."
    # Built-in exercise names — announced as "Next up: X" at the end of an
    # inter-exercise rest. Closed set (custom exercises fall back to Apple).
    for name in exercise_names(exercises):
        clips[f"cue_ex_{slug(name)}"] = f"Next up. {name}."

    # Per-clip speed: the ten-seconds cue is slowed for a calmer, clearer
    # "get set"; everything else at normal pace.
    speeds = {"cue_ten_seconds": 0.85}

    if args.only:
        clips = {k: v for k, v in clips.items() if k in set(args.only)}
        if not clips:
            print(f"--only matched nothing: {args.only}", file=sys.stderr)
            return 1

    print(f"Generating {len(clips)} clips → {OUT_DIR}")
    for clip_slug, text in clips.items():
        out = os.path.join(OUT_DIR, clip_slug + ".mp3")
        synth(text, out, args.voice, key, speed=speeds.get(clip_slug, 1.0))
    print("Done. Commit Tempo/Tempo/Resources/CueAudio/*.mp3 and run xcodegen.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
