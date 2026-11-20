# App <-> server contract goldens

`golden/*.json` is the JSON the Tempo backend really sends for every route the
iOS app calls (plus the push payloads the app parses). Both sides test against
the same files:

- **Backend** `tempo-backend/Tests/AppTests/ContractGoldenTests.swift` produces
  each response and fails if a file differs from what the server now sends.
- **iOS** `Tempo/TempoTests/Services/Network/APIContractTests.swift` decodes each
  file with the app's real DTOs, through `APIClient.decodeBody` (the same decoder
  and envelope unwrap the app uses), and asserts key fields are non-default.

This catches the drift that otherwise only shows up on a phone: a renamed
CodingKey, `USD` vs `Usd`, a push `type` nested where the app doesn't look.

## Regenerate after an API change

```
scripts/testenv.sh db 1 && eval "$(scripts/testenv.sh test-env 1)"   # any free slot
cd tempo-backend
TEMPO_UPDATE_CONTRACTS=1 swift test --filter ContractGolden          # rewrites contracts/golden/
swift test --filter ContractGolden                                   # must pass with no env var
cd .. && scripts/sim.sh test -only-testing:TempoTests/APIContractTests
```

Commit the golden diff with the change. If the iOS test fails, that is a real
mismatch: fix the app DTO or the server. Only a known, tracked bug gets an
`XCTExpectFailure("<description>")` around its assertion.

Goldens are normalized (sorted keys; ids, timestamps, tokens and request ids
replaced by fixed values of the same shape), so they change only when the shape
does.

## How each golden is produced

- **Driven**: the real route, in-process (`app.test`), in test mode, as a Pro,
  consented test user. Claude/USDA/DSLD are the test-mode fakes.
- **Encoded**: routes that need a real `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`
  (other suites assert those are unset, so they can't be set here) or an Apple
  identity token. The server's own response type is encoded through the same
  `Envelope` + global snake_case encoder from a value with every optional filled
  in (Swift omits nil keys, which would hide a missing key).

## Adding a route

1. Backend: add a `try golden("<route-slug>", ...)` in `ContractGoldenTests`
   (driven if you can, else `envelopeJSON(app, <server response value>)` with all
   optionals set). Slug = method-less path, e.g. `nutrition-ai-suggest-meal`.
2. Regenerate (above) and commit `contracts/golden/<slug>.json`.
3. iOS: add the slug to `covered` and a test in `APIContractTests` that decodes
   it with the app's DTO and asserts a few values (`testEveryGoldenFileHasAnIOSContractTest`
   fails until you do).

Not covered: routes the app defines but never calls (`/v1/sync/*` has no server
route either), `/v1/auth/logout` (the app ignores the body), error bodies, and
non-JSON responses (`GET /v1/exercise-images/:slug` is raw image bytes).
