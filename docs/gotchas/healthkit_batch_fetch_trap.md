# HealthKit batch-fetch trap (DashboardViewModel.refresh)

The 7 HealthKit fetches (steps, energy, HR, HRV, RHR, sleep, workouts) MUST each be
awaited in its own `try?` with a per-metric empty default — NOT a shared
`do { try await … } catch`.

**Why:** `fetchHeartRate` (HKSampleQueryDescriptor-based) throws HealthKit error
code 11 ("No data available") on empty results. On an iPhone with no Apple Watch
this happens on EVERY refresh. A shared do/catch aborts on the first throw and
runs `steps = 0`, discarding an already-successful `fetchSteps`. Symptom: Move
block stuck at 0 steps; `fetchSteps: 75` logs fine in the service layer but
`[Dashboard] Body built: connected=false`. The code-11 log was silenced, which
hid the bug for a long time and caused 3 wrong theorize-and-rebuild cycles before
measuring with a diagnostic print.

**How to apply:** `let x = (try? await asyncLetX) ?? emptyDefault` per metric.
Statistics-based fetches (steps, energy) return empty gracefully; descriptor-based
ones (heart rate) THROW on empty — never let them share a failure path. Nicola
uses Whoop, no Apple Watch → HK heart-rate is always empty. Move-block
calories/strain come from Whoop `fetchCycle` (caloriesBurned, dayStrain), NOT
HealthKit active energy.

**Deferred bugs (out of scope this session, not yet fixed):**
1. Whoop session desync — `[Dashboard] Whoop cycle fetch failed: notConnected`
   logged even when `Whoop state: connected` two lines above.
2. `isConnected` Move-card render gate is HealthKit-only
   (`healthKitConnected || !workouts.isEmpty`) → hides Whoop calories/strain when
   HK is empty but Whoop is connected.
