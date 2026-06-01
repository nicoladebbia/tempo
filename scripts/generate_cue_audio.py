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
COUNTDOWN = {
    "cue_ten_seconds": "Get ready. Ten seconds.",
    "cue_three": "Three.",
    "cue_two": "Two.",
    "cue_one": "One.",
    "cue_go": "Go.",
}


def slug(name: str) -> str:
    """Mirror WarmupMove.slug exactly."""
    s = re.sub(r"[^a-z0-9]+", "_", name.lower())
    return s.strip("_")


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


def synth(text: str, out_path: str, voice: str, key: str) -> None:
    url = f"https://api.elevenlabs.io/v1/text-to-speech/{voice}"
    body = (
        '{"text": %s, "model_id": "eleven_multilingual_v2", '
        '"voice_settings": {"stability": 0.5, "similarity_boost": 0.75}}'
    ) % _json_str(text)
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

    clips: dict[str, str] = dict(COUNTDOWN)
    for name in warmup_move_names(routine):
        clips[f"cue_move_{slug(name)}"] = name + "."

    print(f"Generating {len(clips)} clips → {OUT_DIR}")
    for clip_slug, text in clips.items():
        out = os.path.join(OUT_DIR, clip_slug + ".mp3")
        synth(text, out, args.voice, key)
    print("Done. Commit Tempo/Tempo/Resources/CueAudio/*.mp3 and run xcodegen.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
