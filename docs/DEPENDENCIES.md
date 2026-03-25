# Tempo -- Dependency Audit & Recommendations

> **Version:** 1.0.0
> **Last Updated:** 2026-03-24
> **Author:** Build Engineering
> **Status:** Authoritative reference for all dependency decisions
> **Philosophy:** Prefer Apple built-in frameworks. Only add a dependency if it saves >40 hours of development AND is well-maintained. Every dependency is a liability.

---

## Table of Contents

1. [Dependency Philosophy](#1-dependency-philosophy)
2. [iOS App Dependencies](#2-ios-app-dependencies)
3. [Vapor Backend Dependencies](#3-vapor-backend-dependencies)
4. [iOS Package.swift](#4-ios-packageswift)
5. [Vapor Package.swift](#5-vapor-packageswift)
6. [Total Binary Size Estimate](#6-total-binary-size-estimate)
7. [Dependency Update Strategy](#7-dependency-update-strategy)
8. [Security & Vulnerability Scanning](#8-security--vulnerability-scanning)
9. [Rejected Dependencies](#9-rejected-dependencies)

---

## 1. Dependency Philosophy

### The Cost of Every Dependency

Every third-party package added to Tempo incurs:

- **Binary size:** Measured in KB/MB added to the .ipa. Budget: < 15MB total for frameworks/dependencies (from PERFORMANCE_OPTIMIZATION.md Section 9.1).
- **Launch time:** Each dynamic framework adds 5-20ms to dylib loading. Each SPM static library adds rebase/bind time.
- **Maintenance burden:** Dependency updates, breaking API changes, Swift version compatibility.
- **Supply chain risk:** Abandoned packages, malicious updates, license changes.
- **Build time:** Additional compilation targets slow CI.

### Decision Framework

Before adding ANY dependency, answer these five questions:

| # | Question | Required Answer |
|---|----------|----------------|
| 1 | Does Apple provide a built-in alternative? | If yes, use the built-in framework. Period. |
| 2 | Does this save > 40 hours of development time? | If no, write it yourself. |
| 3 | Is the package actively maintained (commit within last 6 months)? | If no, reject. |
| 4 | Does it have > 1,000 GitHub stars and > 5 contributors? | If no, strongly consider forking or vendoring. |
| 5 | Is the binary size impact < 2MB? | If no, find a lighter alternative or extract only what you need. |

### Linking Strategy

All SPM dependencies are linked **statically** to avoid dynamic framework loading overhead. This is the default for SPM packages in Xcode.

```
// In Build Settings:
MACH_O_TYPE = staticlib  (for SPM packages)
```

Static linking eliminates the per-dylib 5-20ms launch penalty. The trade-off is slightly larger binary, but LTO (Link-Time Optimization) strips unused symbols.

---

## 2. iOS App Dependencies

### 2.1 Networking

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **URLSession** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| Alamofire | Third-party | ~1.5MB | Active (40K+ stars) | Rejected |
| Moya | Third-party | ~500KB + Alamofire | Active | Rejected |

**Decision: URLSession + thin custom wrapper**

**Rationale:** Tempo's networking needs are straightforward: JSON REST API with JWT auth, ETag caching, retry logic, and request/response logging. URLSession's async/await API (iOS 15+) handles all of this natively. Alamofire would add 1.5MB of binary for convenience methods we can replicate in ~200 lines.

**What we build instead:**

```swift
// APIClient.swift (~200 lines)
// - Generic request/response with Codable
// - JWT token injection via URLSessionDelegate
// - Automatic token refresh on 401
// - ETag caching
// - Retry with exponential backoff (3 attempts)
// - Request/response logging (DEBUG only)
// - Idempotency-Key header injection
// - X-Client-Version, X-Device-Id headers
```

**Risk if URLSession changes:** Zero. Apple maintains backward compatibility indefinitely.

**Time saved by using built-in:** N/A (baseline). Time that would be wasted with Alamofire: ongoing dependency updates, version migration when Alamofire releases breaking changes (happened with Alamofire 5.0 migration).

---

### 2.2 Image Loading

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **AsyncImage** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** (primary) |
| Custom `ImageCache` | First-party | ~100 lines | Self-maintained | **CHOSEN** (disk cache) |
| Kingfisher | Third-party | ~2MB | Active (23K+ stars) | Rejected |
| Nuke | Third-party | ~500KB | Active (8K+ stars) | Rejected |
| SDWebImage | Third-party | ~3MB | Active (25K+ stars) | Rejected |

**Decision: AsyncImage + custom disk cache**

**Rationale:** Tempo has minimal image loading needs:
- User avatars (< 200KB each, ~50 max on leaderboard screen)
- Exercise demo thumbnails (on-demand, disk-cached 30 days)
- No infinite scroll image feeds, no complex image transformations

`AsyncImage` handles memory caching and async loading natively. For disk persistence (exercise demos), a simple `FileManager`-based cache with TTL (~80 lines) is sufficient. Kingfisher would add 2MB for features we never use (GIF animation, image processors, prefetching pipelines).

**Custom cache implementation** (already specified in PERFORMANCE_OPTIMIZATION.md Section 2.5):

```swift
// ImageCache.swift (~80 lines)
// - NSCache for memory (auto-evicts on memory pressure)
// - FileManager for disk (30-day TTL for exercise demos, 7-day for avatars)
// - SHA256 hash of URL as filename
// - prepareForDisplay() for off-main-thread decoding
```

**Risk assessment:** If Apple deprecates AsyncImage (extremely unlikely for a SwiftUI primitive), migration to any third-party library is straightforward since the call sites are isolated behind our cache wrapper.

---

### 2.3 Charts

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **Swift Charts** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| DGCharts (danielgindi/Charts) | Third-party | ~5MB | Active (28K+ stars) | Rejected |
| SwiftUICharts | Third-party | ~300KB | Low activity | Rejected |
| Custom `Canvas` rendering | First-party | ~200 lines | Self-maintained | **CHOSEN** (365-day dense charts) |

**Decision: Swift Charts + Canvas for dense data**

**Rationale:** Swift Charts (iOS 16+, Tempo targets iOS 17+) provides:
- Line, bar, area, and point charts natively
- Built-in accessibility (VoiceOver reads data points)
- Automatic axis scaling, legends, and animations
- Interactive selection (scrub gesture)
- Integration with SwiftUI's layout system

DGCharts would add 5MB and is a UIKit wrapper requiring `UIViewRepresentable`, defeating the purpose of a SwiftUI-first architecture.

For the 365-day heatmap calendar and ultra-dense charts (>100 data points where Swift Charts may lag), use `Canvas` for direct GPU-accelerated drawing (specified in PERFORMANCE_OPTIMIZATION.md Section 2.4).

**Chart types mapped to implementation:**

| Chart | Implementation | Data Points |
|-------|---------------|-------------|
| 7-day trend line | Swift Charts `LineMark` | 7 |
| 30-day exercise progress | Swift Charts `LineMark` + `PointMark` | 30 |
| 90-day recovery trend | Swift Charts `LineMark` | 90 |
| 365-day heatmap | `Canvas` + `LazyVGrid` | 365 |
| Multi-series overlay | Swift Charts multi-series `LineMark` | 3x90 |
| Score ring (dashboard) | Custom `Shape` + `drawingGroup()` | 1 |

**Risk assessment:** Swift Charts is an Apple system framework. It will be maintained as long as SwiftUI exists.

---

### 2.4 Keychain

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **Security framework** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| KeychainAccess | Third-party | ~200KB | Active (8K+ stars) | Rejected |
| SwiftKeychainWrapper | Third-party | ~100KB | Low activity | Rejected |

**Decision: Raw Security framework with thin wrapper**

**Rationale:** Tempo stores exactly four items in the Keychain:
1. JWT access token
2. JWT refresh token
3. Stable device UUID (X-Device-Id header)
4. Subscription receipt data (backup)

A Keychain wrapper for four items is ~50 lines of code. KeychainAccess adds 200KB for a generic interface we barely use.

**Implementation:**

```swift
// KeychainService.swift (~50 lines)
enum KeychainService {
    static func save(key: String, data: Data, accessibility: CFString = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly) throws
    static func load(key: String) -> Data?
    static func delete(key: String) throws
    static func deleteAll() throws  // for logout
}
```

**Accessibility level:** `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` -- available after first unlock, not synced to other devices. This matches Tempo's security requirements (tokens are device-specific, per SECURITY_AND_PRIVACY.md Section 4).

**Risk assessment:** The Security framework's C API is ugly but stable. It has not had breaking changes in over a decade. Our 50-line wrapper isolates the ugliness.

---

### 2.5 Analytics -- PostHog

| Detail | Value |
|--------|-------|
| **Package** | `posthog-ios` |
| **GitHub** | https://github.com/PostHog/posthog-ios |
| **Current version** | 3.x (latest stable) |
| **What it does in Tempo** | Event tracking, feature flags, A/B testing, session replay, user identification, cohort assignment |
| **Maintenance status** | Very active. PostHog is a VC-backed company (Series B, $45M+). 20+ contributors. Weekly releases. |
| **Stars** | ~500 (iOS SDK); parent org PostHog/posthog has 22K+ stars |
| **License** | MIT |
| **Binary size impact** | ~1.5MB |
| **Alternatives considered** | Mixpanel (cloud-only, no feature flags), Firebase Analytics (Google data sharing concerns for health app), Amplitude (expensive, cloud-only) |
| **Why PostHog** | Single tool for events + feature flags + A/B testing + session replay. Self-hostable for GDPR/health data compliance. Eliminates need for LaunchDarkly ($$$) and a separate analytics SDK. See ANALYTICS_AND_METRICS.md Section 1.1. |
| **Risk if abandoned** | Low (funded company). If it were abandoned, the `AnalyticsService` wrapper means swapping to Mixpanel/Amplitude requires changing one file. |
| **Can we vendor/fork?** | Not practical -- the SDK is tightly coupled to PostHog's ingestion API. But the MIT license allows forking if needed. |

**Decision: APPROVED -- PostHog iOS SDK**

This is one of the few third-party dependencies that clears the 40-hour bar easily. Building feature flags, A/B testing, event funnels, and session replay from scratch would take months.

**Integration rules:**
- All analytics calls go through `AnalyticsService` (wrapper). No module imports PostHog directly.
- PostHog is initialized lazily (not in `TempoApp.init`) to avoid impacting cold launch time.
- Feature flag evaluation is cached locally and refreshed every 5 minutes.
- Session replay is enabled only for opted-in users (GDPR).

---

### 2.6 Crash Reporting -- Firebase Crashlytics

| Detail | Value |
|--------|-------|
| **Package** | `firebase-ios-sdk` (Crashlytics module only) |
| **GitHub** | https://github.com/firebase/firebase-ios-sdk |
| **Current version** | 11.x (latest stable) |
| **What it does in Tempo** | Crash symbolication, crash-free user rate tracking, non-fatal error logging |
| **Maintenance status** | Extremely active. Google-maintained. 100+ contributors. |
| **Stars** | 5.5K+ |
| **License** | Apache 2.0 |
| **Binary size impact** | ~3.5MB (Crashlytics + FirebaseCore + GoogleDataTransport + nanopb) |
| **Alternatives considered** | Sentry (~4MB, self-hostable, more features but more complex), Datadog (~5MB, enterprise-focused, expensive), BugSnag (~2MB, less ecosystem) |
| **Why Crashlytics** | Industry standard for iOS crash reporting. Free. Best symbolication. Specified in ANALYTICS_AND_METRICS.md. |
| **Risk if abandoned** | Near-zero. Google maintains this as critical infrastructure. |
| **Can we vendor/fork?** | No. Crash symbolication requires a backend service. |

**Decision: APPROVED -- Firebase Crashlytics (Crashlytics module ONLY)**

**Critical: Only include `FirebaseCrashlytics`.** Do NOT include Firebase Analytics, Firebase Remote Config, or any other Firebase module. Each adds 2-5MB. PostHog handles analytics and feature flags.

**SPM import:**

```swift
// Only these products from firebase-ios-sdk:
.product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk")
```

**Binary size mitigation:** Firebase Crashlytics pulls in FirebaseCore and GoogleDataTransport as transitive dependencies. Total cost: ~3.5MB. This is the single largest dependency. Acceptable because crash reporting has no viable build-it-yourself alternative.

---

### 2.7 Push Notifications

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **APNs (raw)** | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| OneSignal | Third-party | ~2MB | Active | Rejected |
| Firebase Cloud Messaging | Third-party | ~3MB (on top of Firebase) | Active | Rejected |

**Decision: Raw APNs (Apple Push Notification service)**

**Rationale:** Tempo's push notification strategy (ONBOARDING_AND_NOTIFICATIONS.md) requires:
- Drill-sergeant notification content (custom text)
- Time-sensitive notifications for accountability escalation
- Background silent pushes for data sync triggers
- Rich notifications with category actions ("Mark as Done")

All of this is native APNs functionality. The Vapor backend sends pushes via APNSwift (see Section 3.5). The iOS app registers for remote notifications via `UNUserNotificationCenter` and handles tokens/delivery natively.

OneSignal and FCM add 2-3MB each for a dashboard and segmentation features we do not need -- our backend handles all push logic.

**Implementation:**

```swift
// PushNotificationService.swift (~100 lines on iOS side)
// - Register for remote notifications
// - Send device token to backend (POST /v1/push/register)
// - Handle notification categories (mark as done, snooze, etc.)
// - Handle silent background pushes for sync triggers
```

---

### 2.8 Animations -- Lottie

| Detail | Value |
|--------|-------|
| **Package** | `lottie-ios` |
| **GitHub** | https://github.com/airbnb/lottie-ios |
| **Current version** | 4.x (latest stable) |
| **What it does in Tempo** | Streak flame animation (Arena, looping), pull-to-refresh trophy spin (Arena), level-up celebration, achievement unlock shimmer |
| **Maintenance status** | Very active. Airbnb-maintained. 50+ contributors. |
| **Stars** | 25K+ |
| **License** | Apache 2.0 |
| **Binary size impact** | ~1.8MB (Lottie 4.x with Core Animation renderer) |
| **Alternatives considered** | SwiftUI `.animation()` (insufficient for complex multi-element animations), SpriteKit (overkill), custom Canvas (too much work for designer-authored animations) |
| **Why Lottie** | MODULE_ARENA.md explicitly specifies Lottie for streak flame (Section 4), pull-to-refresh trophy animation (Section 5.4), and level-up celebration. Lottie enables designers to author animations in After Effects and export as JSON -- no developer animation code needed. |
| **Risk if abandoned** | Low (Airbnb has used it in production for 8+ years). If abandoned, Lottie JSON files can be converted to Core Animation code or replaced with SwiftUI animations. |
| **Can we vendor/fork?** | Yes. Apache 2.0 allows forking. The codebase is self-contained with no external dependencies. |

**Decision: APPROVED -- Lottie**

**Binary size mitigation:** Use Lottie 4.x's Core Animation rendering mode (not the Main Thread renderer). Core Animation mode is faster and uses less memory.

**Lottie JSON files budget:** Each animation JSON should be < 50KB. Total Lottie asset budget: < 500KB.

| Animation | File | Est. Size | Loop? |
|-----------|------|-----------|-------|
| Streak flame (3 tiers) | `streak_flame_1.json`, `_2.json`, `_3.json` | 30KB each | Yes |
| Pull-to-refresh trophy | `trophy_spin.json` | 40KB | No |
| Level-up burst | `level_up.json` | 50KB | No |
| Achievement unlock shimmer | `achievement_unlock.json` | 25KB | No |
| XP gain float | `xp_gain.json` | 15KB | No |
| **Total** | | **~230KB** | |

---

### 2.9 Testing

| Option | Type | What For | Binary Size | Recommendation |
|--------|------|----------|-------------|----------------|
| **XCTest** (built-in) | Apple framework | Unit + integration tests | 0 bytes | **CHOSEN** |
| **swift-snapshot-testing** | Third-party | Snapshot tests for SwiftUI views | Test target only | **CHOSEN** |
| Quick/Nimble | Third-party | BDD-style test syntax | Test target only | Rejected |
| OHHTTPStubs | Third-party | HTTP request mocking | Test target only | Rejected |
| ViewInspector | Third-party | SwiftUI view unit testing | Test target only | Rejected |

**Decisions:**

**XCTest: CHOSEN** -- Native, fast, integrated with Xcode. Tempo's testing strategy (TESTING_STRATEGY.md) is built around XCTest.

**swift-snapshot-testing: CHOSEN**

| Detail | Value |
|--------|-------|
| **Package** | `swift-snapshot-testing` |
| **GitHub** | https://github.com/pointfreeco/swift-snapshot-testing |
| **Current version** | 1.x (latest stable) |
| **What it does in Tempo** | Pixel-perfect regression testing for all 5 module screens (Dashboard, Training, Lockdown, Recovery, Arena) + onboarding |
| **Maintenance status** | Very active. Point-Free maintains it as part of their open-source ecosystem. |
| **Stars** | 3.8K+ |
| **License** | MIT |
| **Binary size impact** | 0 bytes in production (test target only) |
| **Why this** | TESTING_STRATEGY.md Section 6 specifies snapshot tests for all major screens. This is the de facto standard library. |

**Quick/Nimble: REJECTED** -- Adds 1MB+ to the test bundle for syntactic sugar. XCTest's `XCTAssertEqual` is fine.

**OHHTTPStubs: REJECTED** -- We use protocol-based mock injection (e.g., `MockWhoopAPI`, `MockNutriTrackAPI`) instead of intercepting URLSession at the network layer. This is cleaner and does not require a dependency.

---

### 2.10 Logging

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **OSLog / Logger** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| SwiftyBeaver | Third-party | ~300KB | Moderate activity | Rejected |
| CocoaLumberjack | Third-party | ~500KB | Active | Rejected |

**Decision: OSLog / Logger (built-in)**

**Rationale:** `os.Logger` (iOS 14+) provides:
- Subsystem + category filtering (e.g., `com.tempo.networking`, `com.tempo.healthkit`)
- Integration with Console.app and Instruments
- Privacy-redacted parameters by default (`\(token, privacy: .private)`)
- Zero-cost when log level is disabled (compiled out in release builds)
- Structured logging with OSLogStore for reading back logs

No third-party logger can match the integration with Apple's tooling. SwiftyBeaver's cloud dashboard is irrelevant when we have PostHog.

**Implementation:**

```swift
// Logger+Tempo.swift (~20 lines)
import OSLog

extension Logger {
    static let networking = Logger(subsystem: "app.tempo", category: "networking")
    static let healthkit = Logger(subsystem: "app.tempo", category: "healthkit")
    static let whoop = Logger(subsystem: "app.tempo", category: "whoop")
    static let training = Logger(subsystem: "app.tempo", category: "training")
    static let recovery = Logger(subsystem: "app.tempo", category: "recovery")
    static let sync = Logger(subsystem: "app.tempo", category: "sync")
    static let subscription = Logger(subsystem: "app.tempo", category: "subscription")
}
```

---

### 2.11 Date Handling

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **Foundation** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| SwiftDate | Third-party | ~400KB | Low activity | Rejected |

**Decision: Foundation (built-in)**

**Rationale:** Tempo uses ISO 8601 dates from the API (`2026-03-24T10:30:00Z`) and date-only strings (`2026-03-24`). Foundation's `ISO8601DateFormatter`, `Calendar`, and `DateComponents` handle all cases. SwiftDate's convenience methods (`.isToday`, `.adding(.days, 7)`) save ~5 lines per usage but add 400KB.

**Convenience extensions we write instead:**

```swift
// Date+Tempo.swift (~30 lines)
extension Date {
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    var dateString: String { /* YYYY-MM-DD */ }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self)! }
}
```

---

### 2.12 JSON Parsing

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **Codable** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| SwiftyJSON | Third-party | ~200KB | Low activity | Rejected |

**Decision: Codable (built-in)**

**Rationale:** Every API response and SwiftData model in Tempo already conforms to `Codable`. SwiftyJSON is for untyped JSON parsing -- the opposite of what a type-safe Swift 6 codebase needs. All API models are strongly typed with `CodingKeys` and custom `init(from:)` where needed.

---

### 2.13 Feature Flags

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **PostHog feature flags** (bundled with analytics SDK) | Included in PostHog | 0 additional bytes | Same as PostHog | **CHOSEN** |
| LaunchDarkly | Third-party | ~2MB | Active | Rejected |
| Custom (backend-driven) | First-party | ~200 lines | Self-maintained | Backup option |

**Decision: PostHog feature flags**

**Rationale:** PostHog's iOS SDK includes feature flag evaluation at no additional binary cost (already paying the 1.5MB for analytics). LaunchDarkly would add 2MB AND a $10+/month subscription. A custom solution would work but lacks a dashboard, rollout percentages, and A/B test integration.

**Feature flags needed at launch:**

| Flag | Purpose | Default |
|------|---------|---------|
| `enable_ai_reports` | Gate weekly AI report generation | `true` |
| `enable_whoop_integration` | Gate Whoop connection flow | `true` |
| `enable_arena` | Gate social features for phased rollout | `false` (Phase 6) |
| `paywall_variant` | A/B test paywall headlines (A-E) | `"A"` |
| `enable_apple_watch` | Gate Watch app features | `false` (post-launch) |
| `max_free_friends` | Adjust free tier friend limit | `5` |

---

### 2.14 Crash Reporting (Redundant -- see 2.6)

Firebase Crashlytics. See Section 2.6 above.

---

### 2.15 StoreKit / Subscriptions

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **StoreKit 2** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| RevenueCat | Third-party | ~2.5MB | Active (13K+ stars) | Rejected |

**Decision: Raw StoreKit 2**

**Rationale:** Tempo has exactly two subscription products (`com.tempo.pro.monthly` and `com.tempo.pro.annual`) in a single subscription group. StoreKit 2's async/await API handles this with ~150 lines of code (already specified in MONETIZATION_STRATEGY.md Section 5.1).

RevenueCat's value proposition is:
- Cross-platform subscription management (Tempo is iOS-only)
- Subscriber analytics dashboard (PostHog + server-side tracking covers this)
- Paywall A/B testing (PostHog feature flags cover this)
- Receipt validation (Tempo's Vapor backend does server-side validation via Apple's App Store Server API v2)

RevenueCat would add 2.5MB and a $0-8,000/month cost (RevenueCat charges 1% of revenue above $2.5K/month) for features that are either unnecessary or already handled by our stack.

**What RevenueCat does better:** RevenueCat's churn analytics and subscription lifecycle dashboards are genuinely excellent. But these are analytics problems, not SDK problems. We replicate the most important metrics (MRR, churn rate, trial conversion) with PostHog events triggered from our server-side subscription webhook handler.

**Risk assessment:** StoreKit 2 is the path Apple wants developers on. It is stable, well-documented, and Apple actively improves it at every WWDC.

---

### 2.16 Maps

| Option | Type | Binary Size | Maintenance | Recommendation |
|--------|------|-------------|-------------|----------------|
| **MapKit** (built-in) | Apple framework | 0 bytes | Apple-maintained | **CHOSEN** |
| Mapbox | Third-party | ~15MB | Active | Rejected |
| Google Maps SDK | Third-party | ~30MB | Active | Rejected |

**Decision: MapKit (built-in)**

**Rationale:** Tempo uses maps only for displaying running route polylines in the Training module. MapKit's `Map` SwiftUI view with `MapPolyline` handles this perfectly. No custom tiles, no turn-by-turn navigation, no offline maps needed.

Mapbox/Google Maps would blow the entire 15MB dependency budget on one feature.

---

### 2.17 iOS Dependency Summary

| Dependency | Binary Size | Category | Justification |
|------------|-------------|----------|---------------|
| PostHog iOS SDK | ~1.5MB | Analytics + Feature Flags + A/B Testing | Replaces 3 separate tools |
| Firebase Crashlytics | ~3.5MB | Crash Reporting | Industry standard, no alternative |
| Lottie | ~1.8MB | Animations | Designer-authored animations for Arena |
| swift-snapshot-testing | 0 (test only) | Testing | Snapshot regression tests |
| **Total third-party** | **~6.8MB** | | |
| **Budget** | **< 15MB** | | **Under budget by 8.2MB** |

Everything else uses Apple built-in frameworks:

| Apple Framework | Used For |
|----------------|----------|
| SwiftUI | All UI |
| SwiftData | Local persistence |
| HealthKit | Biometric data (steps, HR, HRV, sleep, energy) |
| EventKit | Apple Calendar integration |
| StoreKit 2 | Subscriptions |
| MapKit | Running route display |
| Swift Charts | All charts (7/30/90 day) |
| Security | Keychain storage |
| OSLog / Logger | Structured logging |
| Foundation | Networking (URLSession), dates, JSON (Codable) |
| UserNotifications | Push notification handling |
| AuthenticationServices | Sign in with Apple |
| WatchConnectivity | Apple Watch communication |
| WidgetKit | Home screen widgets + Watch complications |
| ActivityKit | Live Activities |
| BackgroundTasks | BGTaskScheduler for background sync |

---

## 3. Vapor Backend Dependencies

### 3.1 Vapor (Core Framework)

| Detail | Value |
|--------|-------|
| **Package** | `vapor` |
| **GitHub** | https://github.com/vapor/vapor |
| **Current version** | 4.x (latest stable) |
| **What it does** | HTTP server, routing, middleware, WebSocket, content negotiation |
| **Maintenance status** | Very active. Vapor is the leading Swift server framework. 40+ contributors. |
| **Stars** | 24K+ |
| **License** | MIT |
| **Alternatives considered** | Hummingbird (lighter, newer, less ecosystem), Kitura (IBM, effectively abandoned), raw SwiftNIO (too low-level) |
| **Why Vapor** | Largest ecosystem, most documentation, native Swift concurrency support, built-in WebSocket (needed for Arena real-time updates). |
| **Risk if abandoned** | Moderate. Vapor is the primary Swift server framework with a dedicated company (Vapor Inc). If abandoned, Hummingbird is a viable migration target. |

---

### 3.2 Fluent ORM + PostgreSQL Driver

| Detail | Value |
|--------|-------|
| **Packages** | `fluent`, `fluent-postgres-driver` |
| **GitHub** | https://github.com/vapor/fluent, https://github.com/vapor/fluent-postgres-driver |
| **Current version** | 4.x |
| **What it does** | ORM for database models, migrations, queries. PostgreSQL driver built on PostgresNIO. |
| **Maintenance status** | Active. Part of the Vapor ecosystem. |
| **Stars** | 1.3K+ (fluent), 200+ (postgres driver) |
| **License** | MIT |
| **Why this** | Standard Vapor ORM. Provides type-safe queries, migration management, and relationship handling. The PostgreSQL driver uses async/await natively via PostgresNIO. |
| **Risk if abandoned** | Tied to Vapor's fate. If Vapor lives, Fluent lives. |

---

### 3.3 JWT Authentication

| Detail | Value |
|--------|-------|
| **Package** | `jwt-kit` (via `vapor-jwt`) |
| **GitHub** | https://github.com/vapor/jwt-kit |
| **Current version** | 4.x |
| **What it does** | JWT creation, signing (ES256), verification. Used for access/refresh token management and Sign in with Apple token verification. |
| **Maintenance status** | Active. Core Vapor ecosystem package. |
| **Stars** | 400+ |
| **License** | MIT |
| **Why this** | Native to the Vapor ecosystem. Supports ES256 (required for Apple JWT), RS256 (required for Apple's public keys), and HS256. |
| **Risk if abandoned** | Low. JWT handling is trivially implementable with swift-crypto if needed, but jwt-kit saves significant boilerplate. |

---

### 3.4 Redis

| Detail | Value |
|--------|-------|
| **Package** | `redis` (Vapor's Redis package, built on RediStack) |
| **GitHub** | https://github.com/vapor/redis |
| **Current version** | 4.x |
| **What it does** | Session storage, rate limit counters, OAuth state CSRF tokens, idempotency key cache, ETag cache, Whoop token refresh lock, subscription event dedup |
| **Maintenance status** | Active. Part of Vapor ecosystem. RediStack (underlying library) is maintained by Swift Server Workgroup. |
| **Stars** | 500+ |
| **License** | MIT |
| **Why this** | Standard Vapor Redis integration. Built on Apple's RediStack (swift-server/RediStack). |
| **Risk if abandoned** | Very low. RediStack is a Swift Server Workgroup project with Apple involvement. |

---

### 3.5 APNSwift (Push Notifications)

| Detail | Value |
|--------|-------|
| **Package** | `apnswift` |
| **GitHub** | https://github.com/swift-server-community/APNSwift |
| **Current version** | 5.x |
| **What it does** | Send push notifications to iOS devices via Apple's APNs HTTP/2 API. Used for drill-sergeant notifications, social alerts, sync triggers, and subscription lifecycle notifications. |
| **Maintenance status** | Active. Swift Server Community maintained. |
| **Stars** | 700+ |
| **License** | Apache 2.0 |
| **Alternatives considered** | Raw HTTP/2 client to APNs (too much boilerplate), Firebase Cloud Messaging server SDK (adds Google dependency to backend) |
| **Why this** | Purpose-built for APNs. Handles certificate/token auth, HTTP/2 multiplexing, retry, and device token feedback. |
| **Risk if abandoned** | Low. APNs protocol is stable. In worst case, we can send HTTP/2 requests directly with AsyncHTTPClient. |

---

### 3.6 AsyncHTTPClient

| Detail | Value |
|--------|-------|
| **Package** | `async-http-client` |
| **GitHub** | https://github.com/swift-server/async-http-client |
| **Current version** | 1.x |
| **What it does** | HTTP client for server-to-server calls: Whoop API, NutriTrack API, Apple's token verification endpoint, App Store Server API v2 |
| **Maintenance status** | Very active. Swift Server Workgroup project. Apple-backed. |
| **Stars** | 900+ |
| **License** | Apache 2.0 |
| **Why this** | The standard async HTTP client for Swift on the server. Built on SwiftNIO. |
| **Risk if abandoned** | Near-zero. Apple maintains this as part of the Swift Server ecosystem. |

---

### 3.7 Swift Crypto

| Detail | Value |
|--------|-------|
| **Package** | `swift-crypto` |
| **GitHub** | https://github.com/apple/swift-crypto |
| **Current version** | 3.x |
| **What it does** | AES-256-GCM encryption for Whoop tokens (stored in DB), HKDF-SHA256 key derivation, SHA-256 hashing for refresh token storage |
| **Maintenance status** | Very active. Apple-maintained. |
| **Stars** | 1.5K+ |
| **License** | Apache 2.0 |
| **Why this** | Apple's official cryptography library for Swift. Cross-platform (uses CryptoKit on Apple platforms, BoringSSL on Linux). |
| **Risk if abandoned** | Near-zero. Apple maintains this. |

---

### 3.8 Queues (Background Jobs)

| Detail | Value |
|--------|-------|
| **Package** | `queues`, `queues-redis-driver` |
| **GitHub** | https://github.com/vapor/queues, https://github.com/vapor/queues-redis-driver |
| **Current version** | 1.x |
| **What it does** | Background job processing: Whoop data sync, NutriTrack sync, AI report generation (Claude API), weekly email digests, subscription webhook processing, data export jobs |
| **Maintenance status** | Active. Part of Vapor ecosystem. |
| **Stars** | 300+ |
| **License** | MIT |
| **Why this** | Native Vapor job queue. Uses Redis as the backing store (which we already run). Supports scheduled jobs, retries, and priority queues. |
| **Risk if abandoned** | Tied to Vapor ecosystem. If needed, a simple Redis-based job queue is ~200 lines. |

---

### 3.9 Leaf (Templating -- Optional)

| Detail | Value |
|--------|-------|
| **Package** | `leaf` |
| **GitHub** | https://github.com/vapor/leaf |
| **Current version** | 4.x |
| **What it does** | Server-side HTML templating for: Whoop OAuth callback page, email templates, App Store Server Notification webhook handler debug page |
| **Maintenance status** | Active. Part of Vapor ecosystem. |
| **Stars** | 400+ |
| **License** | MIT |
| **Why this** | Lightweight templating for the few HTML pages the backend serves. |
| **Note** | If the backend serves zero HTML pages (all OAuth redirects use URL scheme redirects), this can be removed. |

---

### 3.10 Backend Dependency Summary

| Dependency | Category | Required? |
|------------|----------|-----------|
| `vapor` | Core framework | Yes |
| `fluent` | ORM | Yes |
| `fluent-postgres-driver` | Database driver | Yes |
| `jwt-kit` (via `vapor/jwt`) | Authentication | Yes |
| `redis` (Vapor) | Caching, rate limiting, jobs | Yes |
| `apnswift` | Push notifications | Yes |
| `async-http-client` | HTTP client (Whoop, NutriTrack, Apple APIs) | Yes |
| `swift-crypto` | Encryption, hashing | Yes |
| `queues` + `queues-redis-driver` | Background jobs | Yes |
| `leaf` | HTML templating | Optional |

All backend dependencies are MIT or Apache 2.0 licensed. All are maintained by either Apple, the Swift Server Workgroup, or the Vapor team.

---

## 4. iOS Package.swift

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tempo",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "TempoCore",
            targets: ["TempoCore"]
        ),
    ],
    dependencies: [
        // Analytics + Feature Flags + A/B Testing
        .package(
            url: "https://github.com/PostHog/posthog-ios.git",
            from: "3.0.0"
        ),

        // Crash Reporting (Crashlytics module ONLY)
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            from: "11.0.0"
        ),

        // Designer-authored animations (streak flame, level-up, etc.)
        .package(
            url: "https://github.com/airbnb/lottie-ios.git",
            from: "4.4.0"
        ),
    ],
    targets: [
        .target(
            name: "TempoCore",
            dependencies: [
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "Lottie", package: "lottie-ios"),
            ]
        ),

        // Test target — snapshot testing is test-only, zero production binary impact
        .testTarget(
            name: "TempoTests",
            dependencies: [
                "TempoCore",
                .product(
                    name: "SnapshotTesting",
                    package: "swift-snapshot-testing"
                ),
            ]
        ),
    ]
)

// Note: swift-snapshot-testing is only used in tests.
// Add it to the dependencies array:
// .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.15.0"),
```

**Important Xcode project note:** Tempo is primarily an Xcode project (`.xcodeproj` / `.xcworkspace`), not a pure SPM package. The Package.swift above defines the SPM dependency resolution. In Xcode:

1. File > Add Package Dependencies
2. Add each URL with the version specified above
3. Link only the products listed to the app target
4. Link `SnapshotTesting` only to the `TempoTests` test target

**Watch app target:** The Watch app target should link only `TempoCore` (shared models). It should NOT link PostHog, Firebase, or Lottie. The Watch app uses WatchKit haptics (not Lottie) and does not need analytics or crash reporting independently.

---

## 5. Vapor Package.swift

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "tempo-backend",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Core server framework
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),

        // ORM + PostgreSQL
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),

        // JWT authentication (Sign in with Apple, access/refresh tokens)
        .package(url: "https://github.com/vapor/jwt.git", from: "4.2.0"),

        // Redis (caching, rate limiting, CSRF state, idempotency, job queue)
        .package(url: "https://github.com/vapor/redis.git", from: "4.10.0"),

        // Push notifications via APNs
        .package(url: "https://github.com/swift-server-community/APNSwift.git", from: "5.0.0"),

        // HTTP client for server-to-server calls (Whoop, NutriTrack, Apple APIs)
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.21.0"),

        // Cryptography (AES-256-GCM token encryption, HKDF, SHA-256)
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.2.0"),

        // Background job processing
        .package(url: "https://github.com/vapor/queues.git", from: "1.15.0"),
        .package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.1.0"),

        // HTML templating (OAuth callback pages, optional)
        .package(url: "https://github.com/vapor/leaf.git", from: "4.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "Redis", package: "redis"),
                .product(name: "APNSwift", package: "APNSwift"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Queues", package: "queues"),
                .product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
                .product(name: "Leaf", package: "leaf"),
            ],
            path: "Sources/App"
        ),

        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            path: "Tests/AppTests"
        ),
    ]
)
```

**Backend project structure:**

```
tempo-backend/
├── Package.swift
├── Package.resolved          # Lockfile — commit this
├── Sources/
│   └── App/
│       ├── configure.swift   # Vapor configuration
│       ├── routes.swift      # Route registration
│       ├── Controllers/      # HTTP controllers
│       ├── Models/           # Fluent models
│       ├── Migrations/       # Database migrations
│       ├── Services/         # Business logic (WhoopService, NutriTrackService, etc.)
│       ├── Middleware/        # JWT, rate limiting, logging
│       ├── Jobs/             # Background jobs
│       └── DTOs/             # Request/response data transfer objects
├── Tests/
│   └── AppTests/
└── Resources/
    └── Views/                # Leaf templates (if used)
```

---

## 6. Total Binary Size Estimate

### iOS App (.ipa) Size Breakdown

| Component | Estimated Size | Notes |
|-----------|---------------|-------|
| Swift runtime (embedded) | ~8MB | Included by Xcode for apps targeting < iOS 18 |
| App executable (arm64, LTO optimized) | ~6MB | 5 modules, engines, services, views |
| Asset catalog (SF Symbols, colors, app icon) | ~2MB | Mostly vector assets |
| Exercise library seed (JSON, compressed) | ~300KB | Gzipped, lazy-loaded |
| Lottie animation files | ~230KB | 6 animation JSONs |
| **PostHog SDK** | ~1.5MB | Static linked |
| **Firebase Crashlytics** | ~3.5MB | Static linked (includes FirebaseCore, GoogleDataTransport, nanopb) |
| **Lottie framework** | ~1.8MB | Static linked |
| Localization (English only) | ~200KB | Strings files |
| Storyboard / Launch screen | ~50KB | Minimal |
| **Subtotal (before thinning)** | **~23.6MB** | |
| App Thinning (arm64 slice only) | -15% | Xcode strips unused architectures |
| **Estimated download size** | **~20MB** | |
| **Budget** | **< 50MB** | |
| **Status** | **WELL UNDER BUDGET** | 30MB headroom |

### Comparison to Budget (PERFORMANCE_OPTIMIZATION.md Section 9.1)

| Budget Item | Allocated | Estimated Actual | Status |
|-------------|-----------|-----------------|--------|
| Executable (arm64) | < 15MB | ~6MB | Under |
| Asset catalog | < 5MB | ~2MB | Under |
| Exercise library (seed JSON) | < 500KB | ~300KB | Under |
| Frameworks/dependencies | < 15MB | ~6.8MB | Under |
| Localization | < 2MB | ~200KB | Under |
| **Total download** | **< 50MB** | **~20MB** | **Under by 30MB** |
| **Total install** | **< 80MB** | **~35MB** | **Under by 45MB** |

The conservative dependency choices leave significant headroom for future features without hitting the 50MB cellular download limit or the 80MB install target. This headroom is intentional -- it allows adding exercise demo images, expanded Lottie animations, or a future dependency without emergency size reduction.

### Watch App Size

The Watch app links no third-party dependencies. Estimated size: ~5MB (SwiftUI views, WatchKit, shared models). Watch apps have a 50MB limit.

---

## 7. Dependency Update Strategy

### 7.1 Update Cadence

| Category | Frequency | Trigger |
|----------|-----------|---------|
| Security patches (CVE) | Immediate (< 24 hours) | GitHub Dependabot alert, PostHog/Firebase advisory |
| Minor versions (bug fixes) | Monthly | First Monday of each month |
| Major versions (API changes) | Quarterly review | Evaluate breaking changes, schedule migration sprint |
| Apple frameworks | Annually (WWDC) | New iOS/watchOS release, test during beta period |

### 7.2 Update Process

```
1. Create branch: update/dependencies-YYYY-MM
2. Update Package.resolved (swift package update)
3. Build both targets (iOS app + Vapor backend)
4. Run full test suite (unit + integration + snapshot)
5. If snapshot tests fail: review changes, update reference images if intentional
6. Run on physical device (iPhone + Apple Watch)
7. Check binary size (must remain < 50MB)
8. Merge via PR with "dependency update" label
```

### 7.3 Lockfile Management

**iOS:** `Package.resolved` is committed to the repository. Every developer and CI machine uses the exact same dependency versions.

**Vapor backend:** `Package.resolved` is committed. The Docker build uses `swift build` with the lockfile, ensuring reproducible builds.

**Rule:** Never run `swift package update` without creating a dedicated branch and testing.

### 7.4 Pre-Update Checklist

Before updating any dependency:

- [ ] Read the CHANGELOG for all versions between current and target
- [ ] Check for breaking API changes
- [ ] Search GitHub Issues for regressions in the target version
- [ ] Verify Swift 6 compatibility (strict concurrency)
- [ ] Verify iOS 17+ / macOS 14+ compatibility
- [ ] Check that no new transitive dependencies are pulled in
- [ ] Verify license has not changed

---

## 8. Security & Vulnerability Scanning

### 8.1 GitHub Dependabot Configuration

Create `.github/dependabot.yml` in the repository root:

```yaml
version: 2
updates:
  # iOS app SPM dependencies
  - package-ecosystem: "swift"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "ios"
    reviewers:
      - "nicoladebbia"
    commit-message:
      prefix: "deps(ios):"

  # Vapor backend SPM dependencies
  - package-ecosystem: "swift"
    directory: "/tempo-backend"
    schedule:
      interval: "weekly"
      day: "monday"
    open-pull-requests-limit: 5
    labels:
      - "dependencies"
      - "backend"
    reviewers:
      - "nicoladebbia"
    commit-message:
      prefix: "deps(backend):"
```

### 8.2 Security Audit Checklist (Quarterly)

| Check | Tool | Action if Failed |
|-------|------|-----------------|
| Known CVEs in dependencies | `gh api /repos/{owner}/{repo}/dependabot/alerts` | Update immediately |
| License compliance | Manual review of Package.resolved | Remove or replace non-compliant dependency |
| Dependency freshness | Check last commit date for each dependency | If > 12 months stale, evaluate replacement |
| Transitive dependency audit | `swift package show-dependencies --format json` | Flag unexpected new transitive deps |
| Binary contains no debug symbols | `nm` on release binary | Fix build settings |
| No hardcoded secrets in dependencies | `grep -r "sk_live\|api_key\|secret" .build/` | Report to dependency maintainer |

### 8.3 Supply Chain Protection

- **Pin to exact minor versions** in Package.swift (e.g., `from: "4.92.0"` not `from: "4.0.0"`). This prevents unexpected major version jumps.
- **Review Package.resolved diffs** in every PR. New transitive dependencies must be explicitly approved.
- **Mirror critical dependencies** to a private GitHub fork if the project reaches >100K users. This protects against repo deletion or hostile takeover.

---

## 9. Rejected Dependencies

A record of every dependency considered and rejected, so future engineers do not re-evaluate them.

| Dependency | Category | Binary Size | Why Rejected |
|------------|----------|-------------|--------------|
| **Alamofire** | Networking | ~1.5MB | URLSession + 200-line wrapper covers all needs. Alamofire is unnecessary abstraction for a single-API-backend app. |
| **Kingfisher** | Image Loading | ~2MB | AsyncImage + 80-line disk cache is sufficient. Tempo has < 50 images to load in any view. |
| **Nuke** | Image Loading | ~500KB | Same rationale as Kingfisher. Lighter, but still unnecessary. |
| **SDWebImage** | Image Loading | ~3MB | ObjC-based, heaviest option. No SwiftUI-native API. |
| **DGCharts** (Charts) | Charts | ~5MB | Swift Charts (built-in) covers all chart types. DGCharts is UIKit-based. |
| **SwiftUICharts** | Charts | ~300KB | Unmaintained. Last significant commit >1 year ago. Swift Charts is strictly better. |
| **KeychainAccess** | Keychain | ~200KB | 50 lines of Security framework wrapper handles our 4 Keychain items. |
| **SwiftKeychainWrapper** | Keychain | ~100KB | Same as above. |
| **RevenueCat** | Subscriptions | ~2.5MB | StoreKit 2 + 150 lines handles 2 products. RevenueCat charges 1% of revenue for features we replicate with PostHog + server-side validation. |
| **LaunchDarkly** | Feature Flags | ~2MB | PostHog includes feature flags at no extra binary cost. LaunchDarkly costs $10+/month. |
| **OneSignal** | Push Notifications | ~2MB | Raw APNs + APNSwift on backend handles all push requirements. |
| **Firebase Analytics** | Analytics | ~5MB | Google data sharing concerns for a health-adjacent app. PostHog is privacy-first. |
| **Firebase Remote Config** | Feature Flags | ~3MB | PostHog flags are sufficient. Would pull in Firebase Analytics as transitive dependency. |
| **Mixpanel** | Analytics | ~1MB | Cloud-only, no feature flags, no session replay. PostHog is strictly better. |
| **Amplitude** | Analytics | ~1.5MB | Expensive at scale. No feature flags without add-on. |
| **Sentry** | Crash Reporting | ~4MB | More features than Crashlytics (performance monitoring, session replay) but heavier. Crashlytics is free and sufficient. |
| **Quick/Nimble** | Testing | ~1MB (test only) | Syntactic sugar over XCTest. Not worth the dependency for BDD-style assertions. |
| **OHHTTPStubs** | Testing | ~500KB (test only) | Protocol-based mock injection is cleaner than URLSession interception. |
| **SwiftyBeaver** | Logging | ~300KB | OSLog/Logger provides superior integration with Apple's tooling. |
| **CocoaLumberjack** | Logging | ~500KB | ObjC-based, heavy. OSLog is the modern replacement. |
| **SwiftDate** | Date Handling | ~400KB | 30-line Date extension replaces all needed convenience methods. |
| **SwiftyJSON** | JSON | ~200KB | Codable provides type-safe JSON parsing. SwiftyJSON is for untyped access, which is an anti-pattern in Swift 6. |
| **Mapbox** | Maps | ~15MB | Blows entire dependency budget. MapKit handles polyline display. |
| **Google Maps SDK** | Maps | ~30MB | Same as Mapbox but worse. |
| **ViewInspector** | Testing | ~200KB (test only) | Snapshot testing is more reliable for UI verification than programmatic view inspection. |
| **SnapKit** | Layout | ~300KB | Tempo uses SwiftUI exclusively. SnapKit is for UIKit Auto Layout. |
| **R.swift** | Resources | ~200KB | Swift's native string catalogs and asset catalogs provide compile-time safety. |

---

## Appendix: Dependency Decision Log

When adding or removing a dependency in the future, add an entry here:

| Date | Action | Dependency | Justification | Binary Impact |
|------|--------|-----------|---------------|---------------|
| 2026-03-24 | Added | PostHog iOS SDK 3.x | Analytics + feature flags + A/B testing in one tool | +1.5MB |
| 2026-03-24 | Added | Firebase Crashlytics 11.x | Crash reporting (industry standard) | +3.5MB |
| 2026-03-24 | Added | Lottie 4.x | Arena animations (streak flame, level-up, pull-to-refresh) | +1.8MB |
| 2026-03-24 | Added | swift-snapshot-testing 1.x | Snapshot tests (test target only) | +0MB |
