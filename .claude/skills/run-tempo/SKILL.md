---
name: run-tempo
description: Launch Tempo in this worktree's own simulator, drive it with AXe (tap, swipe, read the screen), take screenshots, or install it on Nicola's iPhone from the CLI. Use whenever a change must be seen working in the real app, for QA passes, or when asked to run, screenshot or install Tempo.
---

# Run and drive Tempo

Every worktree has its own simulator and build folder, managed by `scripts/sim.sh`. Never target the stock "iPhone 17" by name and never build into the default DerivedData: two sessions on one simulator queue up ("test runner hung before establishing connection") and overwrite each other's app.

## Launch

```bash
scripts/sim.sh qa          # build, install, launch past onboarding (most QA)
scripts/sim.sh run         # same, real first-launch path (onboarding shown)
scripts/sim.sh run -healthKitAuthorized YES   # any extra launch args
UDID=$(scripts/sim.sh udid)
```

`qa` passes `--uitesting-skip-onboarding -healthKitAuthorized YES -hasCompletedSetup YES`. The last two set `@AppStorage` values, which shows the Move card and hides the welcome banner. The app is "Tempo Dev", bundle `app.tempo.Tempo.dev`.

## Drive it with AXe

AXe is installed (`brew install cameroncooke/axe/axe`; if missing, first `brew trust --formula cameroncooke/axe/axe`).

```bash
axe describe-ui --udid "$UDID"                  # accessibility tree: labels + frames
axe tap --label "Start Workout" --udid "$UDID"  # prefer labels
axe tap -x 200 -y 400 --udid "$UDID"            # points, not pixels
axe swipe --start-x 200 --start-y 700 --end-x 200 --end-y 200 --udid "$UDID"
axe touch -x 200 -y 400 --down --up --delay 1.2 --udid "$UDID"   # long press
scripts/sim.sh shot <scratchpad>/screen.png     # screenshot resized to points, so its pixels = tap coordinates
```

Look at the screenshot (Read it) after every step; don't drive blind.

Gotchas:

- On a brand-new simulator the calendar "full access" prompt still appears once (`simctl privacy` can't grant full access): `axe tap --label "Allow Full Access" --udid "$UDID"`. Notification and HealthKit prompts also can't be pre-granted. Never run `simctl privacy` while the app is running: it kills the app.

- The ActiveWorkoutView full-screen cover and the ☰ menu are NOT in the AX tree (it shows the Training screen underneath). Drive them by screenshot coordinates. Menu rows sit at y≈93/135/177/219/261/303/345/387 (Week Plan … History).
- A swipe often registers as a tap; for scrolling, start the swipe on empty space.
- The Undo toast lasts 5 s. Tap it right away.
- The trainer import sheet has "Load Sample Program (DEBUG)", so no backend is needed for it.

If AXe can't reach something, a temporary XCUITest in `TempoUITests` that writes `app.screenshot().pngRepresentation` to the scratchpad works too (run with `scripts/sim.sh test -only-testing:TempoUITests/<Test>`). Delete it afterwards and rerun `xcodegen generate`.

## Local test backend, scenarios, pushes

Anything that needs the server (weekly plan, AI features, pushes, Pro gates) runs against the local test backend instead of production:

```bash
scripts/testenv.sh up                       # Postgres + Redis + server in test mode (≈10 s; --rebuild after backend edits)
scripts/sim.sh qa --local                   # signed into this simulator's own test account (Pro, AI consent)
scripts/sim.sh qa --local --scenario week   # wiped app + seeded state; `sim.sh scenarios` lists them
scripts/sim.sh qa --local --as alice --free # another account, without Pro
scripts/testenv.sh ai broken                # fake | broken | empty | slow [secs] | error | real (needs `up --real-ai`)
scripts/testenv.sh pushes                   # pushes the server sent and whether the simulator got them
scripts/sim.sh notify urgent                # any notification kind with its real action buttons (`notify help`)
scripts/testenv.sh status | logs -f | down | reset
```

- AI, USDA, Open Food Facts, DSLD, Whoop, OpenAI and Instacart are faked (`tempo-backend/Sources/App/TestMode/`). Any other outside host gets a 502 and a `[test-mode] blocked outbound` log line; add a fixture there when that shows up.
- Local runs ask for notification permission and sim.sh taps Allow (AXe). To see the action buttons, go home (`axe button home`), send the notification, then long-press the banner (`axe touch -x 200 -y 90 --down`, wait, `--up`).
- `sim.sh qa` / `run` without `--local` switch the simulator back to production.
- A new scenario goes in `Tempo/Tempo/App/ScenarioSeed.swift` as a `case "name": // description` line.

## Install on Nicola's iPhone

```bash
xcodebuild -project Tempo/Tempo.xcodeproj -scheme Tempo -destination 'id=00008150-001631A11163401C' \
  -derivedDataPath DerivedData -allowProvisioningUpdates -quiet build
xcrun devicectl device install app --device 00008150-001631A11163401C "DerivedData/Build/Products/Debug-iphoneos/Tempo Dev.app"
xcrun devicectl device process launch --device 00008150-001631A11163401C --terminate-existing app.tempo.Tempo.dev
```

Screenshots of the device are not possible from the CLI. A simulator check is necessary but not sufficient: only Nicola's on-device check after a fresh install counts as verified (see `.claude/rules/swift.md`).

## When done

Leave the simulator; it belongs to this worktree and is reused next time. When the worktree is finished, `scripts/sim.sh clean` (or `scripts/cleanup.py`) removes the simulator and build folder.
