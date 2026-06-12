# StoreKit Setup — Local vs Production

How Tempo's subscriptions are wired, what works locally, and the exact
App Store Connect steps that can only be done in the portal.

## Status

| Layer | State |
|-------|-------|
| StoreKit 2 service (`SubscriptionService`) | Done — verification, txn listener, entitlement refresh, trial/grace/expired/churned states |
| Product loading through protocol | Done — `availableProducts()` on `SubscriptionServiceProtocol`; works in mock/preview, not just `live()` |
| Local `.storekit` config | Done — `Tempo/Tempo/Tempo.storekit`, 4 products + 7-day free trial |
| Scheme wiring | Done — `storeKitConfiguration` in `project.yml` Tempo scheme; survives `xcodegen generate` |
| App Store Connect products | **NOT DONE — manual, see below. Required for TestFlight/production.** |

## Products (single source of truth = `SubscriptionProduct` enum)

| Product ID | Price | Duration | Intro |
|------------|-------|----------|-------|
| `app.tempo.Tempo.pro.monthly` | $4.99 | 1 month | 7-day free |
| `app.tempo.Tempo.pro.annual` | $39.99 | 1 year | 7-day free |
| `app.tempo.Tempo.pro.student.monthly` | $2.99 | 1 month | 7-day free |
| `app.tempo.Tempo.pro.student.annual` | $23.99 | 1 year | 7-day free |

Subscription group: `tempo_pro`. Product IDs are **globally immutable** once
created in App Store Connect — they must match the enum raw values exactly.

## Local verification (do this now — manual, no automated test)

`xcodebuild test` cannot run (TEST_HOST broken on iOS sim — see project
memory). So the purchase flow is verified by hand:

1. Open `Tempo.xcodeproj` in Xcode (or run the Tempo scheme on a simulator).
2. The scheme already points at `Tempo/Tempo.storekit` (no manual Edit Scheme
   step — it's in `project.yml`). Confirm: Product > Scheme > Edit Scheme >
   Run > Options > StoreKit Configuration shows `Tempo.storekit`.
3. Launch on a simulator, navigate to the paywall (`PaywallView`).
4. Expect: 4 products render with prices $4.99 / $39.99 / $2.99 / $23.99 and
   "7-day free trial" copy. Toggle student mode → student prices show.
5. Tap subscribe → StoreKit test sheet → confirm. State should transition to
   `.trial` (intro offer active), `isPro` becomes true, Pro gating unlocks.
6. Test "Restore Purchases" — should re-resolve the same entitlement.
7. Optional: Xcode > Debug > StoreKit > Manage Transactions to expire/refund
   and verify `.gracePeriod` / `.expired` / `.churned` transitions.

If products don't appear: the `.storekit` isn't attached to the run action —
re-run `cd Tempo && xcodegen generate` and re-check step 2.

## App Store Connect — CANNOT be done locally (production / TestFlight)

The `.storekit` file makes the **simulator** fully functional. Real purchases
(TestFlight sandbox, App Store) require all of the following in App Store
Connect — none of it is in the repo:

1. **Subscription group**: create group named `tempo_pro`.
2. **4 auto-renewable subscriptions** with the EXACT product IDs above.
   IDs are permanent — typos mean a dead product forever.
3. **Pricing**: set each product's price per the table, per territory
   (Apple's price tiers; pick the tier closest to USD value).
4. **Introductory offer**: add a 7-day free trial (pay-as-you-go / free,
   1 week, new subscribers) to each of the 4 products.
5. **Localized metadata**: display name + description per locale (at least
   en-US) for each product and the group.
6. **Review info**: subscription review screenshot + notes (Apple requires a
   screenshot of the paywall for subscription review).
7. **Tax & banking**: Paid Apps Agreement signed, banking + tax forms
   complete in Business — subscriptions won't go live without this.
8. **Submit** the subscriptions with the first app build that contains them
   (subscriptions are reviewed alongside the binary the first time).
9. **Sandbox testing**: create a Sandbox Apple Account (Users and Access >
   Sandbox) to test real StoreKit (not the local `.storekit`) on a device /
   TestFlight before release.

### Student pricing note

The student products (`*.student.*`) are separate products at a lower price.
Student eligibility/verification is **not** an App Store mechanism — Tempo
must gate access to the student products in-app (e.g. verified `.edu` /
SheerID-style check) before presenting them. That gating logic is a separate
piece of work, not covered by StoreKit config. Don't ship the student
products purchasable by everyone.
