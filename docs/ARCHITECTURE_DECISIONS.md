# Tempo -- Architecture Decision Records

> **Version:** 1.0
> **Created:** 2026-03-24
> **Author:** Nicola Debbia
> **Purpose:** Document the WHY behind every major technical decision in Tempo, so that in 6 months the reasoning is preserved even if the context has faded.

---

## Table of Contents

**Platform & Architecture**
- [ADR-001: Native iOS (Swift) over cross-platform frameworks](#adr-001-native-ios-swift-over-cross-platform-frameworks)
- [ADR-002: SwiftUI over UIKit](#adr-002-swiftui-over-uikit)
- [ADR-003: SwiftData over Core Data, Realm, and GRDB](#adr-003-swiftdata-over-core-data-realm-and-grdb)
- [ADR-004: Vapor (Swift) over FastAPI, Express, and Supabase for backend](#adr-004-vapor-swift-over-fastapi-express-and-supabase-for-backend)
- [ADR-005: PostgreSQL over SQLite and DynamoDB for backend database](#adr-005-postgresql-over-sqlite-and-dynamodb-for-backend-database)
- [ADR-006: Monolith backend over microservices](#adr-006-monolith-backend-over-microservices)
- [ADR-007: REST API over GraphQL](#adr-007-rest-api-over-graphql)
- [ADR-008: JWT authentication over session-based auth](#adr-008-jwt-authentication-over-session-based-auth)
- [ADR-009: Sign in with Apple as sole authentication method](#adr-009-sign-in-with-apple-as-sole-authentication-method)

**Integration**
- [ADR-010: Whoop via both API and HealthKit](#adr-010-whoop-via-both-api-and-healthkit)
- [ADR-011: NutriTrack proxy through backend, not direct iOS-to-Flask](#adr-011-nutritrack-proxy-through-backend-not-direct-ios-to-flask)
- [ADR-012: HealthKit as unified biometric bus](#adr-012-healthkit-as-unified-biometric-bus)
- [ADR-013: Apple Calendar via EventKit over manual schedule input](#adr-013-apple-calendar-via-eventkit-over-manual-schedule-input)

**Data & Sync**
- [ADR-014: Offline-first with server sync](#adr-014-offline-first-with-server-sync)
- [ADR-015: Server-side source of truth for social data, client-side for personal data](#adr-015-server-side-source-of-truth-for-social-data-client-side-for-personal-data)
- [ADR-016: WebSockets for Arena real-time features](#adr-016-websockets-for-arena-real-time-features)
- [ADR-017: Webhook-driven plus polling hybrid for Whoop data](#adr-017-webhook-driven-plus-polling-hybrid-for-whoop-data)

**Features**
- [ADR-018: Claude API for AI features, not on-device ML](#adr-018-claude-api-for-ai-features-not-on-device-ml)
- [ADR-019: APNs directly over third-party push services](#adr-019-apns-directly-over-third-party-push-services)
- [ADR-020: Freemium subscription model](#adr-020-freemium-subscription-model)
- [ADR-021: Server-validated XP economy](#adr-021-server-validated-xp-economy)
- [ADR-022: In-app focus timer over system-level Screen Time integration](#adr-022-in-app-focus-timer-over-system-level-screen-time-integration)
- [ADR-023: Seeded JSON exercise library with server-hosted expansion](#adr-023-seeded-json-exercise-library-with-server-hosted-expansion)

**Operations**
- [ADR-024: PostHog for analytics over Firebase Analytics and Mixpanel](#adr-024-posthog-for-analytics-over-firebase-analytics-and-mixpanel)
- [ADR-025: Cloud deployment (Railway/Fly.io) over self-hosted infrastructure](#adr-025-cloud-deployment-railwayfly-io-over-self-hosted-infrastructure)
- [ADR-026: PostHog feature flags over LaunchDarkly and custom solutions](#adr-026-posthog-feature-flags-over-launchdarkly-and-custom-solutions)
- [ADR-027: Firebase Crashlytics for crash reporting over Sentry](#adr-027-firebase-crashlytics-for-crash-reporting-over-sentry)

**Future-Proofing**
- [ADR-028: Apple Watch as companion app, not independent](#adr-028-apple-watch-as-companion-app-not-independent)
- [ADR-029: iPad support deferred to post-1.0](#adr-029-ipad-support-deferred-to-post-10)
- [ADR-030: Android not planned; no cross-platform rewrite](#adr-030-android-not-planned-no-cross-platform-rewrite)

---

## ADR-001: Native iOS (Swift) over cross-platform frameworks

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo is a life operating system that deeply integrates with Apple ecosystem APIs: HealthKit (biometric data), EventKit (calendar), APNs (push notifications), ASWebAuthenticationSession (OAuth), WidgetKit (home screen widgets), WatchKit (Apple Watch), and Live Activities. The app also needs to feel native -- it sits alongside Apple Health and Apple Fitness, and users will compare it to those experiences. The developer (Nicola) already has Swift/SwiftUI experience from building Saife (another iOS app in the portfolio).

### Decision

Build Tempo as a native iOS app using Swift 6 and SwiftUI. No cross-platform framework.

### Alternatives Considered

**React Native**
- Pros: Large ecosystem, hot reload, JavaScript familiarity, cross-platform potential.
- Cons: HealthKit integration requires native modules. EventKit, APNs, WidgetKit, WatchKit, and Live Activities all need bridging. Performance overhead for workout logging (16ms frame budget during active sets). The bridging layer adds maintenance burden for a solo developer. RN's update cycle often lags behind iOS releases, meaning new Apple APIs (e.g., SwiftData, new HealthKit types) arrive months late.
- Why rejected: The sheer number of Apple-native APIs Tempo depends on would mean spending more time writing bridges than features. A React Native Tempo would be a native app wearing a React Native hat.

**Flutter**
- Pros: Excellent UI performance (Skia/Impeller rendering), Dart is pleasant, good cross-platform story, Google-backed.
- Cons: Same bridging problem as RN for HealthKit, EventKit, APNs, WatchKit. Flutter's rendering model means it does NOT use native UIKit/SwiftUI components -- the app would not look or feel like a native iOS app. No SwiftData. WidgetKit complications must still be written in SwiftUI. Apple Watch app cannot be built in Flutter.
- Why rejected: Flutter excels when the app is self-contained UI with minimal platform integration. Tempo is the opposite: it is deeply entangled with Apple's health and notification stack. Plus, the non-native rendering means losing the iOS feel that matters for App Store success in this category.

**Progressive Web App (PWA)**
- Pros: Instant distribution, no App Store review, works on all platforms.
- Cons: No HealthKit access. No push notifications on iOS (well, limited Web Push since iOS 16.4, but unreliable). No background processing. No Apple Watch. No widgets. No offline-first with SwiftData. Safari performance for charts and animations is poor. App Store presence matters for discoverability and trust.
- Why rejected: A non-starter. Tempo's core value proposition depends on APIs that are iOS-only. A PWA Tempo would be a dashboard with no data sources.

### Consequences

- **Positive:** Full access to every Apple API without bridging. Native performance for workout logging. SwiftUI previews accelerate UI development. App Store trust and discoverability. Apple Watch support is a natural extension.
- **Negative:** No Android version. Solo developer locked to one platform. Swift ecosystem is smaller than JavaScript/TypeScript for tooling and libraries.
- **Risks:** If Tempo succeeds and Android demand grows, a separate native Android app or cross-platform rewrite would be expensive.
- **What would make us reconsider:** If 50%+ of prospective users are on Android and revenue is being left on the table, a Kotlin Multiplatform (KMP) approach for shared business logic with native UI on each platform would be the path forward -- not a full rewrite in Flutter/RN.

### Implementation Notes

- Target iOS 17.4+ (enables SwiftData with critical bug fixes, new HealthKit APIs, interactive widgets). Per Technical Feasibility Audit: iOS 17.0-17.3 has significant SwiftData bugs (crashes on complex relationships, silent save failures).
- Use Swift 6 strict concurrency checking from day one to avoid data race issues.
- All platform API access goes through service abstractions (HealthKitService, CalendarService, etc.) so the business logic layer is testable without simulators.

---

## ADR-002: SwiftUI over UIKit

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo's UI is data-dense (4-quadrant dashboard, charts, workout logging, timers, leaderboards) but does not require custom UIKit-level rendering tricks. The app targets iOS 17+, which means SwiftUI is mature enough for production. The developer has SwiftUI experience from Saife.

### Decision

Build 100% of the UI in SwiftUI. No UIKit except where SwiftUI lacks coverage (e.g., ASWebAuthenticationSession for OAuth).

### Alternatives Considered

**UIKit (full)**
- Pros: Battle-tested, complete API surface, predictable performance, massive Stack Overflow knowledge base.
- Cons: Verbose (3-4x more code for the same UI). No declarative previews. Manual layout and state management. UIKit does not support WidgetKit or Apple Watch complications. New Apple features (Live Activities, interactive widgets) are SwiftUI-only.
- Why rejected: Writing Tempo in UIKit would take 2-3x longer for a solo developer and would forfeit widgets, complications, and Live Activities.

**Hybrid (SwiftUI shell + UIKit for complex views)**
- Pros: Best of both worlds. Use SwiftUI for navigation and simple views, UIKit for performance-critical views (charts, workout logging).
- Cons: Two paradigms in one app increases cognitive load. `UIViewControllerRepresentable` bridging is clunky. State management split between `@Observable` (SwiftUI) and delegates/closures (UIKit).
- Why rejected: SwiftUI on iOS 17 handles charts (Swift Charts), lists, animations, and custom gestures well enough. The 16ms workout logging budget is achievable by keeping state in-memory (`@State` / `@Observable`) and debouncing persistence. No need for UIKit's escape hatch.

### Consequences

- **Positive:** Faster development. Declarative UI is easier to reason about. Previews work. Widgets, complications, and Live Activities are built in the same paradigm. Future-proof as Apple invests more in SwiftUI.
- **Negative:** Some SwiftUI quirks (NavigationStack edge cases, List performance with large datasets, sheet presentation bugs) will require workarounds. Less control over exact rendering behavior compared to UIKit.
- **Risks:** A specific UI pattern (e.g., drag-to-reorder exercises in a workout) might fight SwiftUI's layout system and require more effort than UIKit.
- **What would make us reconsider:** If profiling reveals that a specific SwiftUI view cannot meet its frame budget (e.g., workout logging), we would wrap that single view in `UIViewRepresentable`. This is a surgical fix, not a paradigm switch.

### Implementation Notes

- Use `@Observable` (iOS 17) instead of `ObservableObject` for all view models and services. Simpler, more performant observation.
- Use `NavigationStack` with `NavigationPath` for type-safe navigation.
- Swift Charts for all chart views (progress, trends, recovery).
- Pre-warm haptic engines (`UIImpactFeedbackGenerator.prepare()`) in workout views.

---

## ADR-003: SwiftData over Core Data, Realm, and GRDB

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo needs local persistence for offline-first data: daily snapshots, workout plans, exercises, study sessions, non-negotiables, recovery prescriptions, XP events, and sync state. The data model has ~25 entities with relationships. The app must support schema migrations as the model evolves. Future multi-device sync (via CloudKit) is desirable but not required at launch.

### Decision

Use SwiftData with versioned schemas and a migration plan. CloudKit sync disabled at launch (Tempo uses its own Vapor backend for sync), but the group container is configured to enable it later.

### Alternatives Considered

**Core Data**
- Pros: Proven over 15+ years. Rich migration system (lightweight + custom). NSFetchedResultsController for efficient list updates. Huge knowledge base.
- Cons: Verbose API (NSManagedObject subclasses, fetch request boilerplate, context management). Does not compose naturally with SwiftUI's declarative model. @FetchRequest is limited compared to SwiftData's @Query. Feels like fighting the framework when using Swift concurrency.
- Why rejected: SwiftData is Apple's explicit successor to Core Data for SwiftUI apps. It uses the same underlying SQLite storage (and can even read Core Data stores) but with a Swift-native API. For a new project targeting iOS 17+, Core Data adds friction without benefit.

**Realm (MongoDB)**
- Pros: Fast reads, easy API, live objects that auto-update UI, built-in sync (Realm Sync / MongoDB Atlas).
- Cons: Third-party dependency with uncertain future (MongoDB has deprioritized Realm mobile in favor of Atlas Device SDK, which has had stability issues). Non-standard threading model (objects are thread-confined). Does not integrate with SwiftUI as naturally as SwiftData. Vendor lock-in if using Realm Sync. Binary size overhead.
- Why rejected: Adding a third-party ORM when Apple provides a first-party one that integrates perfectly with SwiftUI is unnecessary risk. Realm's threading model is also more complex than SwiftData's `ModelActor` approach.

**GRDB (Swift SQLite wrapper)**
- Pros: Full SQL access, excellent performance, no ORM overhead, great for complex queries.
- Cons: More boilerplate than SwiftData (manual Codable conformance, manual migration SQL). No automatic CloudKit sync. No `@Query` integration with SwiftUI. Requires writing raw SQL or its query builder DSL for every operation.
- Why rejected: GRDB is ideal for apps with complex query patterns (analytics, search). Tempo's queries are straightforward (fetch today's snapshot, fetch this week's workouts). SwiftData handles these with less code and better SwiftUI integration.

### Consequences

- **Positive:** `@Model` macro eliminates boilerplate. `@Query` in SwiftUI views gives automatic UI updates. Versioned schemas with `VersionedSchema` and `SchemaMigrationPlan` handle evolution. Potential CloudKit sync is one configuration change away.
- **Negative:** SwiftData is young (shipped 2023). There are known bugs around relationship deletion rules, compound predicates, and background context performance. Fewer community resources than Core Data.
- **Risks:** SwiftData bugs could force workarounds that add complexity. If a migration requires custom logic (not lightweight), SwiftData's custom migration support is less mature than Core Data's.
- **What would make us reconsider:** If SwiftData has a show-stopping bug (e.g., data corruption under concurrent writes during workout logging), we would evaluate GRDB as a replacement. The service layer abstraction makes swapping the persistence layer feasible without rewriting views.

### Implementation Notes

- `ModelContainer` created with `groupContainer: .identifier("group.app.tempo")` for future widget and Watch extension data sharing.
- `cloudKitDatabase: .none` at launch -- Tempo syncs through its own Vapor backend.
- All SwiftData writes on background `ModelActor` contexts; UI reads on `@MainActor`.
- Debounced persistence for workout logging (500ms delay after last interaction) to avoid write contention.
- Indexes on `date` fields for DailySnapshot and WorkoutPlan to meet the <50ms fetch budget.

---

## ADR-004: Vapor (Swift) over FastAPI, Express, and Supabase for backend

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo needs a backend for: (1) Whoop OAuth2 proxy (client_secret cannot live on device), (2) NutriTrack proxy (caching, auth transformation), (3) Arena social features (leaderboards, challenges, friend system), (4) XP economy (server-validated to prevent cheating), (5) push notification dispatch via APNs, (6) AI insights via Claude API, (7) user authentication (Sign in with Apple JWT verification). The developer is a solo builder who already knows Swift from the iOS app.

### Decision

Use Vapor 4 (Swift) as the backend framework, deployed as a Docker container.

### Alternatives Considered

**FastAPI (Python)**
- Pros: Extremely fast development speed. Nicola already knows Python deeply (seriea-pipeline, edge90, nutrition-app, hone, agent-storm all use Python). Excellent ecosystem (SQLAlchemy, Pydantic, httpx). Massive community. Easy deployment. Claude SDK has first-class Python support.
- Cons: Two languages in the stack (Swift + Python) means context-switching and no shared types. API request/response DTOs must be defined separately in both languages and kept in sync manually. Python's type system is optional and weaker -- bugs that Swift catches at compile time would become runtime errors. Performance is adequate but not exceptional.
- Why rejected: This was the hardest rejection. FastAPI would genuinely be faster to build. But the full-stack Swift advantage is significant: shared enum definitions (WorkoutType, RecoveryZone, etc.), shared DTO structs, compile-time guarantees across the entire stack. When the iOS model says `recoveryScore` is non-optional and the backend says it is optional, the compiler catches it. With Python, that is a runtime crash on a user's phone. For a solo developer with no QA team, compile-time safety across the stack is the QA team.

**Express (Node.js/TypeScript)**
- Pros: TypeScript provides decent type safety. Huge ecosystem (Prisma, passport, etc.). Nicola has Node.js experience (CredLink, DisputePilot, ripcord). Fast development. Easy deployment.
- Cons: Two languages (Swift + TypeScript). TypeScript types are structural and erased at runtime, so validation is a separate concern (Zod, io-ts). Node.js single-threaded model requires care for CPU-bound operations (AI processing). Memory usage is higher than compiled languages.
- Why rejected: TypeScript is closer to Swift's type safety story than Python, but it is still a second language with its own idioms, toolchain, and deployment model. The cognitive overhead of maintaining two type systems that must stay synchronized is real for a solo developer.

**Supabase (BaaS)**
- Pros: Instant PostgreSQL with REST/GraphQL API, built-in auth, real-time subscriptions, edge functions, storage. Near-zero backend code. Generous free tier. Nicola would only need to write edge functions for Whoop OAuth and AI features.
- Cons: Vendor lock-in. Limited control over business logic (XP calculation, notification escalation, Whoop token management require custom server-side code that outgrows edge functions). Row-level security policies for Arena features (leaderboard queries, challenge access) would be complex. Whoop webhook handling in edge functions is awkward. No first-party Swift SDK for server-side.
- Why rejected: Supabase is excellent for CRUD apps. Tempo's backend logic (Whoop OAuth proxy, NutriTrack proxy with caching, XP economy with anti-cheat, notification escalation scheduler, AI insight generation) is too custom for a BaaS. The edge functions would become a second backend that is harder to debug and test than a proper Vapor app.

### Consequences

- **Positive:** Full-stack Swift. Shared types (enums, DTOs) between iOS and backend via a shared Swift package or copy-paste with compiler verification. Vapor's async/await matches Swift concurrency idioms. High performance (compiled, low memory). APNs integration via Vapor's `APNS` library is native.
- **Negative:** Vapor has a smaller ecosystem than Express or FastAPI. Fewer tutorials, fewer libraries. Docker images are larger due to Swift runtime. Build times are longer than Python/Node. Finding Vapor developers (if the team grows) is harder.
- **Risks:** If a critical library is needed (e.g., a Stripe SDK for subscriptions) and no Swift server-side version exists, bridging to a REST API directly is always possible but adds friction. Vapor's community is small enough that a core maintainer leaving could slow framework updates.
- **What would make us reconsider:** If development speed becomes the bottleneck (feature velocity too slow because Vapor ecosystem lacks libraries), migrating the backend to FastAPI while keeping the iOS app in Swift is a clean break -- the REST API contract stays the same, only the server implementation changes.

### Implementation Notes

- Vapor 4 with Fluent ORM for PostgreSQL.
- Redis for caching (NutriTrack responses, rate limiting, OAuth state), session storage, and idempotency keys.
- Docker multi-stage build: Swift 5.10 build stage, Ubuntu 22.04 runtime stage.
- Deployment targets: Railway or Fly.io for managed container hosting.
- Shared DTOs: define Codable structs in both iOS and backend with identical field names. The compiler catches drift during development.

---

## ADR-005: PostgreSQL over SQLite and DynamoDB for backend database

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

The backend needs to store: users, friendships, XP events, challenges, achievements, Whoop OAuth tokens, daily snapshots (synced), push notification tokens, and webhook state. The Arena module requires leaderboard queries (ORDER BY xp DESC with ranking), friendship graph traversal, and challenge standings -- all relational patterns. Expected scale at launch: hundreds to low thousands of users.

### Decision

PostgreSQL 16, accessed via Vapor's Fluent ORM.

### Alternatives Considered

**SQLite (server-side, e.g., Litestream + Turso)**
- Pros: Zero-ops, embedded, fast reads, Litestream provides replication. No separate database server to manage. Perfect for single-server deployments.
- Cons: Single-writer concurrency model. When multiple Whoop webhooks arrive simultaneously, or multiple users submit XP events at the same time, SQLite's write lock becomes a bottleneck. No built-in full-text search (without FTS5 extension). Materialized views for leaderboards are not supported. Running SQLite on Railway/Fly.io with persistent volumes is possible but less mature than managed PostgreSQL.
- Why rejected: SQLite is excellent for read-heavy, single-writer workloads. Arena's leaderboard with concurrent XP writes from many users needs PostgreSQL's MVCC concurrency model. Also, managed PostgreSQL (Railway, Fly.io Postgres, Supabase) provides backups, monitoring, and scaling that SQLite on a volume does not.

**DynamoDB**
- Pros: Infinite scale, zero-ops (AWS managed), single-digit millisecond reads, pay-per-request pricing.
- Cons: DynamoDB's data model (partition key + sort key) does not map well to relational queries. Leaderboard ranking across all users requires a Global Secondary Index on XP, which has eventual consistency. Friendship graph queries (friends-of-friends, mutual friends) are unnatural in a key-value store. No JOINs, no materialized views. The Fluent ORM does not support DynamoDB. Adding the AWS SDK adds significant dependency weight. Cost is unpredictable with hot partitions.
- Why rejected: Tempo's data model is fundamentally relational. Users have friends. Friends are in challenges. Challenges have participants with scores. Leaderboards rank users by aggregated XP with time-windowed queries. This is exactly what PostgreSQL is designed for. DynamoDB would require denormalization patterns that add complexity without benefit at Tempo's scale.

### Consequences

- **Positive:** Rich query capabilities for Arena (window functions for ranking, materialized views for leaderboards). JSONB columns available if semi-structured data is needed. Fluent ORM has first-class PostgreSQL support. Managed PostgreSQL available on every cloud platform. pg_dump for backups.
- **Negative:** Requires a running database server (not embedded). Managed PostgreSQL has a cost floor (~$5-15/month even on free tiers). Schema migrations need care.
- **Risks:** If Tempo scales to 100K+ concurrent users, PostgreSQL can handle it with proper indexing and connection pooling, but costs increase. At that point, it would be a good problem to have.
- **What would make us reconsider:** If the backend needs to handle massive write throughput (millions of XP events per minute) with global distribution, we would evaluate CockroachDB or PlanetScale. This is extremely unlikely for Tempo's use case.

### Implementation Notes

- Connection pooling: 25 connections default, configurable via `DATABASE_POOL_SIZE`.
- Materialized view `weekly_leaderboard` refreshed on a schedule (every 5 minutes), not on every XP event.
- Indexes on: `users(xp_total DESC)`, `xp_events(user_id, date)`, `friendships(user_id, status)`, `challenges(start_date, end_date)`.
- Extensions: `uuid-ossp`, `pgcrypto` for UUID generation and encryption helpers.

---

## ADR-006: Monolith backend over microservices

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo's backend has distinct functional areas: auth, Whoop proxy, NutriTrack proxy, Arena/social, XP economy, push notifications, AI insights, sync. These could theoretically be separate services.

### Decision

Single Vapor monolith with internal module separation via Controllers and Services directories. No microservices.

### Alternatives Considered

**Microservices (separate deployable for each domain)**
- Pros: Independent scaling (Arena could scale separately from auth). Independent deployment. Fault isolation (AI service crash does not affect auth). Clear boundaries.
- Cons: A solo developer maintaining 5-7 deployable services, each with its own Dockerfile, CI pipeline, health checks, logging, and database migrations. Inter-service communication (HTTP or message queue) adds latency and failure modes. Distributed transactions (e.g., "create user + send welcome notification" spanning two services) require sagas or eventual consistency patterns. Debugging a request that spans 3 services requires distributed tracing infrastructure. This is Google-scale tooling for a university student's app.
- Why rejected: Microservices solve organizational problems (multiple teams shipping independently) more than technical problems. A solo developer with a single deploy target gains nothing and loses the simplicity of a single process, single database, single deployment.

### Consequences

- **Positive:** One codebase, one deployment, one database, one log stream. A `git push` deploys everything. No inter-service network calls. Shared database transactions. Simple debugging.
- **Negative:** All functional areas share the same process and deployment cycle. A bad deploy to the AI feature affects auth availability.
- **Risks:** If the AI insight generation becomes CPU-intensive and blocks the event loop, it could degrade API response times. Mitigated by running AI calls in background jobs (Vapor Queues + Redis) rather than inline in request handlers.
- **What would make us reconsider:** If Tempo grows a team and different people own different domains, extracting a service (e.g., Arena as its own service) becomes worthwhile. The Controller/Service separation in the monolith makes this extraction straightforward.

### Implementation Notes

- Internal boundaries via directory structure: `Controllers/AuthController.swift`, `Controllers/ArenaController.swift`, etc.
- Background jobs via Vapor Queues (backed by Redis) for: AI insight generation, Whoop token refresh, leaderboard materialization, notification dispatch.
- Rate limiting per-endpoint to prevent one feature's traffic from starving others.

---

## ADR-007: REST API over GraphQL

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

The iOS app needs to communicate with the Vapor backend. The API surface includes: auth endpoints, CRUD for users and settings, Whoop data sync, NutriTrack proxy, Arena social endpoints, XP events, push notification registration, AI insights, and real-time WebSocket for leaderboard updates. The iOS app is the only client (no web app, no third-party API consumers).

### Decision

RESTful JSON API with versioned endpoints (`/v1/...`), cursor-based pagination, standard error envelope, and a separate WebSocket endpoint for real-time features.

### Alternatives Considered

**GraphQL**
- Pros: Client controls exactly which fields to fetch (no over-fetching). Single endpoint. Strongly typed schema. Introspection. Good for evolving APIs without versioning.
- Cons: Vapor's GraphQL support (Graphiti) is less mature than its REST routing. Solo developer must maintain a schema definition language in addition to Swift models. Caching is harder (no HTTP caching by URL). Error handling is non-standard (errors are in the response body alongside partial data). N+1 query problem requires DataLoader patterns. The iOS app is the only client, so over-fetching is controllable by designing the REST endpoints to match what the app needs.
- Why rejected: GraphQL solves the problem of many different clients needing different views of the same data. Tempo has one client (iOS app) built by the same developer who builds the backend. The REST endpoints can be designed to return exactly what each screen needs. The added complexity of a GraphQL schema, resolvers, and DataLoaders is not justified.

### Consequences

- **Positive:** Simple, well-understood pattern. HTTP caching works naturally (ETag, Cache-Control). Standard error codes (4xx, 5xx) map to well-known semantics. Easy to test with curl. Extensive Vapor routing support.
- **Negative:** If a new client (web app, Android app) emerges with different data needs, we may end up creating multiple REST endpoints for the same resource or adding query parameters for field selection.
- **Risks:** API versioning (`/v1/` vs `/v2/`) requires maintaining old endpoints during migration. Mitigated by keeping v1 stable and additive (new fields are optional, old fields are never removed).
- **What would make us reconsider:** If Tempo gets a web dashboard or public API where many different clients need flexible queries, GraphQL would become more attractive.

### Implementation Notes

- All endpoints under `/v1/` prefix.
- Standard response envelope: `{"ok": true, "data": {...}, "meta": {"request_id": "...", "timestamp": "..."}}`.
- Cursor-based pagination (not offset-based) for all list endpoints.
- ETag support on frequently-read single-resource endpoints (user profile, config).
- Idempotency keys for mutating requests (stored in Redis with 24h TTL).

---

## ADR-008: JWT authentication over session-based auth

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

The iOS app needs to authenticate with the backend for all protected endpoints. The backend also needs to authenticate WebSocket connections. Tokens need to work across app restarts (stored in Keychain) and survive backend redeployments.

### Decision

Short-lived JWT access tokens (15 minutes, ES256 signed) with long-lived opaque refresh tokens (stored server-side). Access tokens are stateless; refresh tokens are validated against the database.

### Alternatives Considered

**Session-based authentication (server-side session store)**
- Pros: Simple to implement. Revocation is instant (delete the session). Session data can be enriched server-side.
- Cons: Every API request requires a database or Redis lookup to validate the session. This adds latency (1-5ms per request) and a single point of failure (if Redis goes down, all users are logged out). WebSocket authentication with sessions is awkward (sessions are HTTP cookie-based, WebSockets use query params or headers). Mobile apps do not use cookies naturally -- would need to manage session tokens manually anyway, which is basically JWT with extra steps.
- Why rejected: For a mobile-first API with no web browser client, session cookies add complexity without benefit. JWTs are the standard pattern for mobile API authentication and are stateless for the common case (access token validation without hitting the database).

### Consequences

- **Positive:** Stateless access token validation (no database hit for most requests). Standard `Authorization: Bearer` header works everywhere including WebSocket query params. Token stored in iOS Keychain for persistence. Refresh token rotation prevents replay attacks.
- **Negative:** Access tokens cannot be revoked before expiry (15 minutes). If a user's account is suspended, they have up to 15 minutes of continued access. Mitigated by the short TTL.
- **Risks:** JWT signing key compromise would require key rotation and forced re-authentication of all users. ES256 (ECDSA) is used instead of HS256 to allow public key verification without sharing the signing key.
- **What would make us reconsider:** If Tempo adds a web client with browser-based sessions, we might add cookie-based sessions alongside JWT for the web while keeping JWT for mobile.

### Implementation Notes

- Signing algorithm: ES256 (ECDSA with P-256 curve). Allows public key distribution for any future service that needs to verify tokens without the signing key.
- Access token TTL: 15 minutes. Refresh token TTL: 30 days.
- Refresh token rotation: each refresh issues a new refresh token and invalidates the old one. Reuse of an old refresh token invalidates the entire family (compromise detection).
- Keychain storage on iOS: access token and refresh token stored with `kSecAttrAccessibleAfterFirstUnlock` for background refresh capability.

---

## ADR-009: Sign in with Apple as sole authentication method

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo targets the App Store. Apple requires Sign in with Apple if any third-party login is offered. Tempo could offer email/password, Google Sign-In, or other social logins alongside Apple. The target audience is iOS-only users.

### Decision

Sign in with Apple is the ONLY authentication method. No email/password, no Google, no social logins.

### Alternatives Considered

**Email/password + Sign in with Apple**
- Pros: Familiar to all users. Does not depend on Apple infrastructure. Users keep their email for account recovery.
- Cons: Requires building: registration flow, password hashing (bcrypt/Argon2), password reset flow, email verification, rate limiting on login attempts, forgot-password emails, email delivery infrastructure (SendGrid/SES). For a solo developer, this is a week of work for a feature that adds friction (users hate creating new passwords). Apple's "Hide My Email" relay means the email address may not even be the user's real email.
- Why rejected: Every iOS user has an Apple ID. Adding email/password doubles the auth surface area (and attack surface) for users who already have Apple credentials. The development time is better spent on core features.

**Sign in with Apple + Google Sign-In**
- Pros: Captures users who prefer Google. Some users are more comfortable with Google.
- Cons: App Store guideline 4.8 requires Sign in with Apple if ANY third-party login is offered (already met). But adding Google means: Google SDK dependency (binary size, privacy policy implications), Google account linking/merging logic, two identity providers to manage, Google's SDK update cycle to track. The privacy story weakens ("we integrate with Google for sign-in").
- Why rejected: Tempo is an iOS-only app. Every user has an Apple ID. Adding Google increases complexity and weakens the privacy narrative without meaningful conversion improvement. If a user refuses to use Sign in with Apple on an iOS device, they are unlikely to be in Tempo's target audience.

### Consequences

- **Positive:** Single auth path simplifies the entire stack. No password storage liability. Apple handles email relay (privacy). Stable user ID from Apple persists across app reinstalls. One-tap sign-in UX. Strong privacy story for App Store listing.
- **Negative:** Users who distrust Apple's ecosystem (unlikely on iOS) have no alternative. Apple provides the user's name only on the FIRST sign-in -- if the backend misses it, it is lost until the user manually sets their display name.
- **Risks:** If Apple's Sign in with Apple service has an outage, no user can authenticate. This is a dependency on Apple infrastructure, but so is the entire iOS platform.
- **What would make us reconsider:** If Tempo launches a web version, Sign in with Apple on the web works but is less seamless than on iOS. At that point, adding email/password or Google for web users would be reasonable.

### Implementation Notes

- Use `ASAuthorizationAppleIDProvider` with `ASAuthorizationAppleIDButton` (system-rendered button, required by Apple).
- Persist `first_name` and `last_name` on the FIRST auth call to the backend -- Apple does not resend them.
- Listen for Apple's server-to-server credential revocation notifications via webhook.
- Support "Hide My Email" relay addresses as the user's primary email -- never ask for a "real" email.
- Nonce-based replay protection: generate a cryptographic nonce client-side, embed it in the authorization request, verify it matches the identity token on the backend.

---

## ADR-010: Whoop via both API and HealthKit

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Whoop provides rich recovery, sleep, and strain data via its REST API (v2). Whoop also writes some data to Apple HealthKit (HRV, resting HR, sleep). Tempo could read Whoop data via the API (through a backend proxy for OAuth), via HealthKit, or both. Not all users have a Whoop -- the app must also work with HealthKit-only biometric sources (Apple Watch).

### Decision

Use Whoop API via backend proxy as the PRIMARY source for Whoop users (recovery score, sleep score, strain, detailed sleep stages). Use HealthKit as the SECONDARY source for biometrics that Whoop writes there (HRV, resting HR) and as the ONLY source for non-Whoop users. HealthKit is also the universal source for steps, active energy, and workout detection regardless of Whoop status.

### Alternatives Considered

**HealthKit only (no Whoop API)**
- Pros: Simpler architecture (no OAuth proxy, no Whoop webhook handling, no token management). HealthKit is always available. Works for all users regardless of wearable.
- Cons: Whoop's proprietary recovery score, sleep performance score, and strain score are NOT available in HealthKit. Only raw metrics (HRV, RHR, sleep stages) are synced to HealthKit by the Whoop app. Tempo's recovery prescription engine needs the composite recovery score (0-100) that is Whoop's core intellectual property. Recreating it from raw HealthKit data would be an approximation at best.
- Why rejected: The recovery score is Whoop's killer feature and what Tempo users who own a Whoop are paying $30/month for. Reading it from HealthKit's raw data and trying to reverse-engineer the score would be inaccurate and legally questionable. The Whoop API provides it directly.

**Whoop API only (no HealthKit)**
- Pros: Single data source for biometrics. No HealthKit permission prompts for Whoop users.
- Cons: Excludes every user who does not own a Whoop ($30/month + hardware). Tempo becomes a Whoop accessory instead of a standalone app. App Store reviewers might reject an app that requires a paid third-party device. Steps and active energy from the phone's built-in sensors are only available via HealthKit.
- Why rejected: Tempo must work without Whoop for public App Store release. The installed base of Apple Watch (100M+) dwarfs Whoop's user base. HealthKit is the universal biometric layer.

### Consequences

- **Positive:** Best data quality for Whoop users (proprietary scores). Universal biometric access for all users via HealthKit. Apple Watch users get recovery estimation from HealthKit HRV/RHR without needing Whoop. Graceful degradation: if Whoop is disconnected, HealthKit data still populates the dashboard.
- **Negative:** Two data paths for biometrics add complexity. Must handle deduplication (Whoop writes HRV to HealthKit, and Tempo reads both Whoop API and HealthKit -- must not double-count). More onboarding complexity (Whoop connection is optional).
- **Risks:** Whoop could restrict API access, change pricing, or deprecate v2 endpoints. Mitigated by always having HealthKit as a fallback.
- **What would make us reconsider:** If Whoop opens up recovery score to HealthKit (very unlikely -- it is their moat), the API proxy becomes unnecessary for that metric.

### Implementation Notes

- Data priority: Whoop API > HealthKit for any metric available from both. If Whoop API returns recovery 72% and HealthKit has HRV 45ms, use both (recovery from API, HRV from HealthKit as supplementary).
- Deduplication: when Whoop writes HRV to HealthKit, tag the HealthKit source. If source is Whoop, skip it (use API value instead).
- Non-Whoop recovery estimation: derive an approximate recovery zone from HealthKit HRV trend, resting HR, and sleep duration. Clearly label it as "estimated" vs Whoop's "measured."
- Whoop connection is optional in onboarding. The app fully functions with HealthKit-only data.

---

## ADR-011: NutriTrack proxy through backend, not direct iOS-to-Flask

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

NutriTrack is Nicola's existing nutrition app -- a Flask server with 140+ API endpoints. It uses PIN-based authentication (6-digit PIN stored as a session cookie). Tempo needs to read NutriTrack data (meals, macros, compliance) for the dashboard and recovery modules.

### Decision

The Tempo Vapor backend proxies all NutriTrack requests. The iOS app never communicates directly with the NutriTrack Flask server.

### Alternatives Considered

**Direct iOS-to-Flask**
- Pros: Simpler architecture (no proxy). Lower latency (one hop instead of two). iOS app sends PIN directly to NutriTrack.
- Cons: The NutriTrack PIN would be stored on the iOS device and sent over the network in every request. NutriTrack's session cookie authentication does not integrate with Tempo's JWT system. The NutriTrack Flask server's URL and port would be exposed in iOS network traffic. No caching layer -- every dashboard refresh hits the Flask server directly. If NutriTrack's API changes, the iOS app binary must be updated (App Store review cycle). The NutriTrack server is single-user and not hardened for public internet exposure from arbitrary iOS clients.
- Why rejected: NutriTrack was designed as a personal tool, not a public API. Exposing it directly to iOS clients introduces security risks (PIN in transit, no rate limiting, no auth integration). The backend proxy centralizes authentication, caches responses, and isolates NutriTrack's API from the iOS app.

### Consequences

- **Positive:** Unified auth (one JWT for everything). Backend caches NutriTrack responses (reduces load on Flask). Backend transforms NutriTrack data to match Tempo's models. NutriTrack's URL and PIN never leave the backend. If NutriTrack's API changes, only the backend proxy needs updating (no App Store review wait).
- **Negative:** Extra network hop (iOS -> Vapor -> Flask -> Vapor -> iOS). Backend must be running for NutriTrack data to appear. More backend code to maintain.
- **Risks:** If the Vapor backend goes down, NutriTrack data is unavailable (but cached snapshots in SwiftData still display).
- **What would make us reconsider:** If NutriTrack is rebuilt with proper API authentication (OAuth2, API keys) and hardened for public access, direct integration from iOS would be viable.

### Implementation Notes

- Backend stores NutriTrack base URL and PIN in encrypted environment variables.
- Cache NutriTrack responses in Redis with 5-minute TTL for dashboard data, 30-second TTL for real-time meal status.
- Transform NutriTrack's response format to match Tempo's Codable DTOs on the backend.
- Health check: backend pings NutriTrack periodically to detect unavailability.

---

## ADR-012: HealthKit as unified biometric bus

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo reads biometric data from multiple sources: Whoop (via API), Apple Watch (via HealthKit), iPhone sensors (via HealthKit), and potentially future wearables. Tempo also writes data back (workout logs from RepForge, dietary energy from NutriTrack meals). Multiple wearables may write overlapping data to HealthKit (e.g., both Whoop and Apple Watch write HRV).

### Decision

Treat HealthKit as the universal biometric data bus. All wearable data that flows through HealthKit is read from HealthKit with source-aware priority. Whoop API is used only for proprietary metrics that HealthKit cannot provide (recovery score, strain score, sleep performance score).

### Alternatives Considered

**Direct integration with each wearable's API**
- Pros: Richest data from each source. No dependence on HealthKit sync timing.
- Cons: Each new wearable requires a new OAuth integration, backend proxy, token management, and webhook handler. Garmin, Oura, WHOOP, Fitbit -- each has its own API. For a solo developer, supporting N wearable APIs is O(N) integration work. HealthKit abstracts all of them into one read interface.
- Why rejected: HealthKit exists precisely to solve this problem. Every serious wearable writes to HealthKit on iOS. Reading from HealthKit gives Tempo automatic support for any wearable without writing a single line of integration code.

### Consequences

- **Positive:** Tempo automatically works with Apple Watch, Garmin, Oura, Fitbit, and any future wearable that writes to HealthKit. One read interface for all biometric data. Background delivery ensures data arrives even when Tempo is not active.
- **Negative:** HealthKit data may lag behind the source API (Whoop's HealthKit sync can take minutes). Some data granularity is lost in the HealthKit abstraction.
- **Risks:** Apple could change HealthKit permissions or data types, requiring app updates.
- **What would make us reconsider:** If a wearable provides critical data that it does NOT write to HealthKit, we would add a direct API integration for that specific wearable (as we already do for Whoop's proprietary scores).

### Implementation Notes

- Read types: `stepCount`, `activeEnergyBurned`, `heartRate`, `heartRateVariabilitySDNN`, `restingHeartRate`, `sleepAnalysis`, workout types.
- Write types: `dietaryEnergyConsumed` (from NutriTrack meals), workout sessions (from RepForge).
- Background delivery enabled for steps, workouts, sleep -- app updates even when suspended.
- Source priority: when multiple sources write the same metric, prefer the primary source (Whoop for HRV if Whoop is connected, otherwise Apple Watch, otherwise phone).

---

## ADR-013: Apple Calendar via EventKit over manual schedule input

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo's Training module needs to know the user's schedule to avoid programming heavy leg workouts before football practice, and the Accountability module needs to know class times to schedule study blocks. The user could manually enter their schedule, or Tempo could read their existing Apple Calendar.

### Decision

Read the user's Apple Calendar via EventKit. No manual schedule input.

### Alternatives Considered

**Manual schedule input (in-app form)**
- Pros: No permission prompt. User has explicit control. No dependency on external calendar.
- Cons: Duplicate data entry -- the user already has their schedule in Apple Calendar, Google Calendar, or a university system. Keeping two schedules in sync is the user's burden. Changes to the real schedule do not propagate to Tempo. Poor UX for a "life operating system" that should integrate, not duplicate.
- Why rejected: Tempo's value proposition is unifying existing data sources. Asking users to re-enter their schedule contradicts this. If the university moves a class, the user updates their calendar app -- Tempo should see the change automatically.

**Google Calendar API (server-side integration)**
- Pros: Many students use Google Calendar. Richer API than EventKit.
- Cons: Requires OAuth, backend proxy, token management -- another integration to maintain. Google Calendar data on iOS is already synced to Apple Calendar (most users enable this). Adding a Google integration duplicates data and adds complexity.
- Why rejected: Google Calendar events synced to iCloud or added to Apple Calendar are readable via EventKit. For the minority who use Google Calendar without syncing to Apple Calendar, the solution is to tell them to enable the sync in iOS Settings. Direct Google API integration is over-engineering for this use case.

### Consequences

- **Positive:** Zero setup for users. Their existing schedule is available immediately. Changes propagate automatically. EventKit is a local API (no network, no backend involvement).
- **Negative:** Requires calendar permission prompt (users may be uncomfortable granting access to their full calendar). Tempo can only read calendars the user has enabled on the device. If the user does not use Apple Calendar, this feature is unavailable.
- **Risks:** Apple could restrict EventKit access further. Users may deny permission, in which case training programming cannot account for their schedule.
- **What would make us reconsider:** If user research shows that a significant portion of users do not use Apple Calendar and manual input is preferred, we would add an in-app schedule editor as a fallback.

### Implementation Notes

- Request read-only access to calendar events. Tempo never writes to the user's calendar.
- Filter events by keyword heuristics: "football", "calcio", "practice", "training", "gym", "class", "lecture", "exam".
- Cache relevant events locally in SwiftData for offline access.
- Permission denied gracefully: training module works without schedule awareness, just without conflict avoidance.

---

## ADR-014: Offline-first with server sync

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo users will log workouts in gyms with poor reception, study in library basements with no Wi-Fi, and check their dashboard on the subway. The app must work without an internet connection for all personal data features.

### Decision

Offline-first architecture. All personal data (daily snapshots, workout plans, exercises, study sessions, non-negotiables, prescriptions, XP events) is stored locally in SwiftData and displayed from the local store. The backend is synced when connectivity is available. HealthKit data is always local.

### Alternatives Considered

**Online-required (server-side source of truth)**
- Pros: Single source of truth simplifies conflict resolution. Data is always fresh. No sync logic needed.
- Cons: App is unusable without internet. Workout logging during a gym session with poor signal would fail. Study timer in a library basement would not persist. This directly contradicts Tempo's "always available" philosophy.
- Why rejected: A fitness app that does not work at the gym is not a fitness app.

**Online-first with offline cache (read-only offline)**
- Pros: Simpler than full offline-first (read from cache, require connection for writes).
- Cons: Users cannot log workouts, mark non-negotiables, or run study timers offline. Only viewing cached data is possible. For a productivity app, read-only offline is nearly as bad as no offline.
- Why rejected: Workout logging, study timing, and non-negotiable tracking are write operations that must work offline. Read-only offline is insufficient.

### Consequences

- **Positive:** App works everywhere. Users never see loading spinners for their own data. HealthKit data is always available locally. Workout logging has zero network dependency.
- **Negative:** Sync conflict resolution is needed (if the user modifies data offline and the server has a different version). Sync state management adds complexity. Data may be temporarily inconsistent between devices (if multi-device is added).
- **Risks:** Conflict resolution bugs could cause data loss. Mitigated by last-write-wins for most fields and server-as-authority for XP (see ADR-021).
- **What would make us reconsider:** Nothing. Offline-first is non-negotiable for a fitness/productivity app.

### Implementation Notes

- SwiftData is the primary read source for all views.
- `SyncService` coordinates background uploads when connectivity resumes.
- `PendingSync` model tracks unsynced local changes with retry logic and exponential backoff.
- Conflict resolution: last-write-wins with server timestamp comparison for personal data. Server-authoritative for social data (XP, leaderboard positions).
- Arena features (leaderboard, challenges, friend requests) require connectivity and show "offline" state gracefully.

---

## ADR-015: Server-side source of truth for social data, client-side for personal data

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo has two categories of data: personal data (workouts, study sessions, non-negotiables, daily snapshots) and social data (XP totals, leaderboard rankings, challenges, friend requests, achievements). These have different consistency requirements.

### Decision

Personal data: client-side source of truth (SwiftData), synced to server for backup and cross-device access. Social data: server-side source of truth (PostgreSQL), cached locally for display.

### Alternatives Considered

**Server-side source of truth for everything**
- Pros: One authority. No sync conflicts. Easier to reason about.
- Cons: Personal data writes (workout logging, timer tracking) require network connectivity. See ADR-014 -- this is unacceptable.
- Why rejected: Workout logging must work offline.

**Client-side source of truth for everything (including XP)**
- Pros: Everything works offline. No network dependency for any feature.
- Cons: XP is a competitive metric visible to other users on leaderboards. If XP is client-authoritative, users could modify their local database to inflate XP (jailbroken device, SQLite editor). This ruins the Arena experience for honest users. XP validation must happen server-side.
- Why rejected: Client-authoritative XP is trivially exploitable. Arena's integrity requires server validation.

### Consequences

- **Positive:** Personal data always available offline. Social data is tamper-resistant. Clear ownership model: "your data lives on your device, competitive data lives on the server."
- **Negative:** XP display may lag (local cache shows stale data until server sync). Leaderboard positions may be outdated by minutes. Arena features have reduced functionality offline.
- **Risks:** Sync bugs could cause personal data to diverge between client and server. Server-side backups mitigate data loss.
- **What would make us reconsider:** If multi-device support becomes critical and users expect instant sync between iPhone and iPad, moving personal data to server-authoritative with offline cache (like Apple Notes/Reminders model) would be worth the complexity.

### Implementation Notes

- Personal data sync: client generates changes locally, pushes to server in batches. Server stores as backup. On new device setup, pull from server to populate local store.
- Social data sync: server pushes via WebSocket or pull on app foreground. Local cache in SwiftData with `syncedAt` timestamps.
- XP events: client generates XP events locally for optimistic display, but the server recalculates and reconciles. If the server rejects an XP event (invalid, duplicate), the local display is corrected.

---

## ADR-016: WebSockets for Arena real-time features

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Arena features (leaderboard updates, challenge score changes, achievement unlocks, friend requests, XP notifications) benefit from real-time delivery. When a friend completes a workout and passes you on the leaderboard, you should see it quickly -- the competitive tension is the product.

### Decision

WebSocket connection (`/v1/ws`) for real-time server-to-client events when the Arena tab is active. Fallback to polling when WebSocket is unavailable.

### Alternatives Considered

**Polling only (no WebSocket)**
- Pros: Simpler server and client implementation. No persistent connection management. Standard HTTP caching applies.
- Cons: Either too slow (poll every 60 seconds, miss competitive moments) or too expensive (poll every 5 seconds, 17,000 requests/day per user for one endpoint). Polling is the wrong tool for event-driven data.
- Why rejected: The Arena experience depends on real-time feedback. "Marco just passed you!" loses its impact if it arrives 60 seconds late. Polling at a frequency that feels real-time wastes bandwidth and server resources.

**Server-Sent Events (SSE)**
- Pros: Simpler than WebSocket (HTTP-based, no upgrade handshake). Auto-reconnect in browsers. One-directional (server-to-client) which matches the use case.
- Cons: SSE is not well-supported on iOS (no native `EventSource` API in URLSession). Would require a third-party library or manual implementation. WebSocket has native iOS support via `URLSessionWebSocketTask`. SSE cannot support client-to-server messages (heartbeats).
- Why rejected: WebSocket has better iOS platform support. `URLSessionWebSocketTask` is first-party, well-tested, and supports bidirectional communication (useful for heartbeats).

### Consequences

- **Positive:** Real-time leaderboard updates create competitive engagement. Achievement unlock animations trigger immediately. Friend request notifications appear without polling.
- **Negative:** Persistent WebSocket connections consume server resources (memory per connection). Connection management adds complexity (reconnection, token refresh, heartbeat). Battery impact from maintaining connection.
- **Risks:** If the backend cannot handle many concurrent WebSocket connections, we can degrade to polling. Connection count at launch will be trivially small.
- **What would make us reconsider:** If user testing shows that leaderboard updates every 30 seconds (via polling) feel real-time enough, we could simplify by removing WebSocket and using polling exclusively.

### Implementation Notes

- WebSocket only connected when app is foregrounded AND user is on a social-related screen.
- JWT passed as query parameter for authentication: `/v1/ws?token=...`.
- Client sends `{"type": "ping"}` every 30 seconds. Server closes connection after 90 seconds without ping.
- Server pushes event types: `leaderboard.update`, `challenge.score_update`, `challenge.completed`, `achievement.earned`, `friend.request`, `xp.earned`.
- Fallback: if WebSocket connection fails 3 times, fall back to polling every 30 seconds.
- Vapor supports WebSocket natively; no additional dependency needed.

---

## ADR-017: Webhook-driven plus polling hybrid for Whoop data

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Whoop generates data throughout the day: sleep data when the user wakes up, recovery score shortly after, workout data when a workout ends, and strain accumulates continuously. Tempo needs to reflect Whoop data with reasonable freshness.

### Decision

Hybrid approach: (1) Whoop webhooks for event-driven updates (sleep, recovery, workout completion), (2) polling every 15 minutes during active hours for strain/cycle data, (3) full sync on app launch.

### Alternatives Considered

**Polling only**
- Pros: Simpler implementation. No webhook endpoint to expose. No HMAC verification. No webhook registration.
- Cons: Recovery score appears when the user wakes up. If we poll every 15 minutes, there is up to a 15-minute delay before the dashboard shows it. For strain, 15 minutes is acceptable. For recovery (which the user checks first thing in the morning), it is not ideal. Polling more frequently (every 1 minute) would consume Whoop's rate limit (100 req/min, 10,000 req/day) too quickly for multiple users.
- Why rejected: Recovery and sleep data are high-value, time-sensitive events. Webhooks deliver them within seconds of availability.

**Webhooks only**
- Pros: Pure event-driven. Zero wasted requests. Data arrives as soon as Whoop produces it.
- Cons: Whoop's webhook delivery is not guaranteed. If a webhook is lost (network issue, server restart), the data never arrives until someone triggers a manual sync. Strain is a continuously updating metric -- Whoop does not send a webhook for every 0.1 increase in strain. Webhooks require a publicly accessible endpoint (domain, SSL certificate, DNS configuration).
- Why rejected: Webhooks alone cannot provide continuous strain updates, and relying solely on webhook delivery for critical data (recovery score) is fragile.

### Consequences

- **Positive:** Near-instant delivery of high-value events (recovery, sleep, workout completion) via webhooks. Continuous strain updates via polling. Full sync on launch catches any missed webhooks.
- **Negative:** Two data ingestion paths add complexity. Webhook endpoint must be publicly accessible and secured (HMAC verification). Must handle duplicate data (webhook and poll may overlap).
- **Risks:** Whoop could change webhook event types or payload formats. Mitigated by defensive parsing with fallback to polling.
- **What would make us reconsider:** If Whoop deprecates their webhook system, polling-only is the fallback. If they add a streaming API, we would switch to that.

### Implementation Notes

- Webhook endpoint: `POST /v1/integrations/whoop/webhook` with HMAC-SHA256 signature verification using `WHOOP_WEBHOOK_SECRET`.
- Webhook events subscribed: `workout.updated`, `sleep.updated`, `recovery.updated`.
- Polling: Vapor background job every 15 minutes fetches `GET /v2/cycle` for active strain.
- Full sync on app launch: backend fetches last 30 days of data from Whoop API and reconciles with stored data.
- Deduplication: each Whoop data point has a unique ID. Backend upserts (INSERT ON CONFLICT UPDATE) to prevent duplicates.

---

## ADR-018: Claude API for AI features, not on-device ML

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo's AI features include: weekly insight reports (pattern detection across sleep, nutrition, training, study), recovery-based workout programming, correlation analysis ("your sleep drops 14% on days you skip lunch"), and coaching recommendations. These require reasoning over multi-dimensional time-series data and generating natural language text.

### Decision

Use Anthropic's Claude API (server-side, called from the Vapor backend) for all AI features. No on-device ML models.

### Alternatives Considered

**On-device ML (Core ML + Create ML)**
- Pros: Zero latency. Works offline. No API cost. Privacy-friendly (data never leaves the device). Apple provides tools for tabular data regression and classification.
- Cons: Core ML is designed for inference on pre-trained models, not for reasoning over complex multi-dimensional data and generating natural language reports. Training a custom model to detect patterns across sleep, nutrition, exercise, and study data requires significant data science effort that would distract from app development. The model would need periodic retraining as more data arrives. Natural language generation (weekly reports) is not feasible with on-device Core ML. The quality of insights from a small, custom-trained model would be far below what Claude produces.
- Why rejected: On-device ML cannot generate the natural language weekly reports and nuanced pattern analysis that are Tempo's premium AI features. A regression model can predict, but it cannot explain "your HRV has been declining because you have been training legs twice a week without recovery days."

**No AI (rule-based insights only)**
- Pros: Zero cost. Fully deterministic. Easy to debug. Works offline.
- Cons: Rule-based systems can detect simple patterns ("HRV below threshold -> suggest rest") but cannot find non-obvious correlations, generate personalized prose, or adapt to individual user patterns. The weekly report would be a template with filled-in numbers rather than genuine analysis. The difference between "Your average sleep was 6.8 hours" (rule-based) and "Your sleep has been improving since you started eating dinner before 8 PM. The correlation is striking -- on the 4 nights you ate late, your sleep efficiency dropped by 11%." (Claude) is the difference between a dashboard and a coach.
- Why rejected: The AI coaching personality is a core differentiator and a premium feature that justifies the subscription price. Rule-based insights would feel generic and fail to justify the $4.99/month Pro tier.

### Consequences

- **Positive:** High-quality natural language insights. Claude can reason about complex multi-dimensional patterns. No ML engineering required from the developer. Model improves with Anthropic's updates (no retraining needed). Compelling Pro feature that justifies the subscription.
- **Negative:** API cost (~$0.01-0.05 per weekly report per user). Requires internet connectivity. Latency (2-5 seconds for a report). Privacy consideration (user data is sent to Anthropic's API).
- **Risks:** Anthropic could increase pricing, change rate limits, or deprecate the model. Claude could generate incorrect insights ("hallucinations"). Mitigated by prompt engineering, output validation, and making it clear that insights are AI-generated.
- **What would make us reconsider:** If Apple ships a sufficiently powerful on-device LLM (Apple Intelligence with local reasoning) that can run complex analytical prompts, we would consider a hybrid approach: on-device for basic daily recommendations, Claude for premium weekly reports.

### Implementation Notes

- Claude called from Vapor backend only (never from iOS directly). This keeps the API key server-side and allows request batching and caching.
- Model: Claude Sonnet (fast, cost-effective for structured analysis tasks).
- Monthly budget cap: $50 default, configurable via `CLAUDE_MONTHLY_BUDGET_CENTS`.
- Weekly reports generated as a background job (Sunday night), cached, and served to the iOS app on Monday morning.
- User data sent to Claude is anonymized (no user ID or email, only metrics and dates).

---

## ADR-019: APNs directly over third-party push services

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo's drill-sergeant notification system is a core feature: escalating push notifications throughout the day to enforce non-negotiables. This is not a "nice to have" -- the notification personality IS the product for the Accountability module. Notifications must be reliable, timely, and support rich content (custom sounds, actionable buttons).

### Decision

Use Apple Push Notification service (APNs) directly from the Vapor backend via the `APNS` library. No third-party push service (OneSignal, Firebase Cloud Messaging, Pusher).

### Alternatives Considered

**Firebase Cloud Messaging (FCM)**
- Pros: Free. Analytics on delivery rates. Topic-based messaging. Web push support.
- Cons: FCM on iOS is a wrapper around APNs. The notification is still delivered by APNs; FCM just adds an intermediary layer. This adds latency (FCM -> APNs -> device). Google dependency in a privacy-focused health app contradicts the "we don't share data with Google" narrative. FCM requires GoogleService-Info.plist and the Firebase SDK, adding binary size and initialization overhead.
- Why rejected: For an iOS-only app, FCM is an unnecessary intermediary over APNs. Vapor has native APNs support. Adding Google infrastructure to a health app weakens the privacy story.

**OneSignal**
- Pros: Dashboard for composing notifications. Segmentation. A/B testing of notification content. Analytics.
- Cons: Third-party dependency. Paid tiers for advanced features. User data (device tokens, notification content) passes through OneSignal's servers. Tempo's notifications are programmatic (triggered by time + completion state), not marketing campaigns composed in a dashboard. OneSignal's value (visual message composer, audience segmentation) does not apply to Tempo's use case.
- Why rejected: Tempo's notifications are algorithmic (if non-negotiable X is incomplete at time Y, send escalated notification Z). This logic lives in the Vapor backend. A visual notification composer adds nothing. Paying a third party to proxy APNs calls for programmatic notifications is waste.

### Consequences

- **Positive:** Direct APNs connection (lowest latency). No third-party data dependency. Vapor's APNS library supports HTTP/2 connection pooling, alert/background/VoIP types, rich content, and custom sounds. Full control over notification scheduling logic.
- **Negative:** No built-in delivery analytics (must implement tracking). No visual notification composer (irrelevant for Tempo's use case). Must manage APNs certificate/key rotation.
- **Risks:** APNs delivery is not guaranteed (notifications can be dropped by the OS for battery optimization). Mitigated by local notification scheduling as a backup for time-critical drill-sergeant alerts.
- **What would make us reconsider:** If Tempo adds a web app or Android client, a cross-platform push service would be necessary for those platforms. APNs remains the iOS path.

### Implementation Notes

- APNs key: P8 format, stored as environment variable `APNS_PRIVATE_KEY`.
- Token-based authentication (not certificate-based) -- simpler, does not expire.
- Notification scheduling: Vapor background job runs every minute, checks for users with incomplete non-negotiables, dispatches appropriate escalation level.
- Local notifications as fallback: iOS app schedules local notifications for the escalation timeline. If the server push fails, the local notification still fires.
- Custom sounds for different escalation levels (gentle chime, firm alert, urgent klaxon).

---

## ADR-020: Freemium subscription model

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo has ongoing server costs: Vapor backend hosting, PostgreSQL, Redis, Claude API calls, Whoop webhook processing, push notification infrastructure. A one-time purchase cannot sustain these costs. The target audience is university students (18-28), who are price-sensitive but willing to pay for apps that directly impact their fitness and productivity.

### Decision

Freemium model with a Pro subscription at $4.99/month or $39.99/year. Free tier includes core daily experience. Pro tier includes AI features, unlimited social, advanced analytics, and power-user tools.

### Alternatives Considered

**One-time purchase ($14.99-$29.99)**
- Pros: Simple value proposition. No subscription fatigue. Attractive to students who hate recurring charges.
- Cons: Tempo's backend has ongoing costs: hosting (~$15-30/month), PostgreSQL (~$5-15/month), Claude API (~$50-200/month depending on users), APNs infrastructure. With 10,000 one-time purchase users generating weekly AI reports, Claude API costs alone could exceed $500-2,000/month with zero recurring revenue. The math never works. After year one, every user is a pure cost center.
- Why rejected: Backend infrastructure and AI API costs are ongoing. A one-time purchase creates a dying business from day one.

**Free + tips/donations**
- Pros: Zero friction. Goodwill.
- Cons: 1-3% tip conversion rate. Average tip $2-5. At 10,000 users: ~$200-500/month in donations. Backend costs alone exceed this. Not a business model.
- Why rejected: Server costs require predictable revenue.

**Free now, monetize later**
- Pros: Maximum adoption speed. Learn which features to gate.
- Cons: Users who get features for free resist paying later. Setting the expectation of "free" creates a vocal minority who 1-star review when a paywall appears. Every month without revenue is runway burning.
- Why rejected: As a short-term beta strategy (4-8 weeks), this is fine. As a launch strategy, it creates the worst possible monetization transition.

**Higher price ($9.99-$14.99/month)**
- Pros: More revenue per subscriber. Aligns with Fitbod ($12.99), MFP ($9.99).
- Cons: University students have $200-400/month disposable income after essentials. $10/month "requires justification." $5/month is a "no-brainer." At the lower price, the conversion rate difference likely compensates for the per-user revenue difference. The target demographic is price-sensitive.
- Why rejected: Optimizing for conversion in a price-sensitive demographic. $4.99 undercuts most fitness apps while delivering more breadth.

### Consequences

- **Positive:** Recurring revenue covers ongoing costs. Free tier builds word-of-mouth and user base. Low barrier to entry for students. Annual pricing ($3.33/month effective) reduces churn. Free users generate social value (more leaderboard participants).
- **Negative:** Must deliver enough free value to retain users long enough to convert. Server costs exist for free users too (push notifications, basic sync).
- **Risks:** Conversion rate too low (<3%) could mean insufficient revenue. Mitigated by natural upgrade pressure from social features (5-friend limit) and AI features (blurred weekly report preview).
- **What would make us reconsider:** If LTV data shows that a higher price point ($7.99) does not reduce conversion rate, we would increase the price. A/B testing via PostHog feature flags.

### Implementation Notes

- StoreKit 2 for all purchase flows (not legacy StoreKit 1).
- Server-side receipt validation using Apple's App Store Server API v2.
- Free tier check: backend middleware checks subscription status on Pro-gated endpoints. Returns 403 with upgrade prompt payload for free users.
- Student discount: $3.99/month ($29.99/year) with .edu email verification. Implemented as a promotional offer in App Store Connect.
- Paywall shown at natural friction points (blurred weekly report, 6th friend request, 4th non-negotiable), never as an interstitial.

---

## ADR-021: Server-validated XP economy

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo's Arena module has an XP economy: users earn XP for completing workouts, studying, logging meals, and maintaining streaks. XP determines leaderboard rankings and levels. Other users can see your XP and rank. If XP is client-calculated and trusted, users on jailbroken devices could modify their local SQLite database to inflate their XP.

### Decision

XP is server-validated. The iOS app generates XP event proposals locally (for optimistic display) but the server recalculates and reconciles. The server's XP total is authoritative for leaderboards.

### Alternatives Considered

**Client-calculated XP (trust the client)**
- Pros: Works offline. Instant display. No server round-trip. Simple implementation.
- Cons: Trivially exploitable. A jailbroken device or SQLite editor can set XP to any value. One cheater on the leaderboard ruins the experience for all honest users. In competitive contexts (challenges with bragging rights), cheating destroys trust.
- Why rejected: Arena's competitive integrity requires server-side validation.

**Fully server-side XP (no local calculation)**
- Pros: Maximum security. No client trust.
- Cons: XP display requires network connectivity. Completing a workout in a gym with no signal would show no XP gain until later. The "instant gratification" of seeing "+50 XP" after a workout is a key engagement mechanic that must work offline.
- Why rejected: The dopamine hit of seeing XP gain immediately after completing a task is critical for engagement. Delaying it until server sync ruins the moment.

### Consequences

- **Positive:** Leaderboard integrity. Cheating requires compromising the server, not just the client. Users see XP instantly (optimistic display) with server reconciliation. Best of both worlds.
- **Negative:** If the server rejects an XP event (e.g., duplicate), the local display must correct. This "XP correction" could be confusing if visible to the user.
- **Risks:** Server-side XP recalculation bugs could incorrectly deduct legitimate XP. Mitigated by audit logging of all XP events.
- **What would make us reconsider:** If Arena becomes purely casual (no real competition, just personal gamification), server validation is unnecessary overhead.

### Implementation Notes

- iOS app creates `XPEvent` locally in SwiftData with `syncStatus = .pending`.
- Optimistic display: local XP total includes pending events.
- On sync: server validates each event (checks source authenticity, prevents duplicates, applies business rules) and returns the canonical XP total.
- If server total differs from local total by >10%, show a subtle reconciliation ("XP adjusted to match server").
- Server stores all XP events in `xp_events` table with immutable audit trail.

---

## ADR-022: In-app focus timer over system-level Screen Time integration

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo's Accountability module includes a Pomodoro-style focus timer for study sessions. The timer tracks study minutes toward the daily non-negotiable. An alternative approach would be integrating with iOS Screen Time to actually block apps (e.g., block PS5 Remote Play or social media until study is done).

### Decision

In-app focus timer (Pomodoro-style) with escalating notifications. No Screen Time API integration.

### Alternatives Considered

**Screen Time API (ManagedSettings / FamilyControls)**
- Pros: Actually blocks distracting apps. Enforces accountability at the system level. Users cannot cheat by simply switching apps.
- Cons: The Screen Time / FamilyControls API requires the `FamilyControls` entitlement, which Apple restricts to parental control apps. Apple's App Store review guidelines are strict about apps that restrict device functionality -- an app that blocks PS5 Remote Play would likely be rejected unless positioned as a parental control tool. The API also requires Family Sharing setup in some configurations. Additionally, users may reject an app that can control their device at the system level.
- Why rejected: Apple gates the FamilyControls API behind a restricted entitlement. Tempo is not a parental control app. Attempting to use this API would likely result in App Store rejection. Even if approved, the "Tempo wants to control which apps you can use" permission prompt would scare away users.

**Shortcuts/Focus Mode integration**
- Pros: iOS Focus Modes can silence notifications and filter apps. Could trigger a "Study" Focus Mode when the timer starts.
- Cons: Focus Modes are user-configured and cannot be programmatically created or enforced. Tempo can suggest creating a Focus Mode in settings, but cannot activate it. The integration is advisory, not enforceable.
- Why rejected: Too indirect. Suggesting that users set up a Focus Mode is documentation, not a feature.

### Consequences

- **Positive:** Simple, reliable timer implementation. Works on all devices without special entitlements. No App Store rejection risk. Users choose to be accountable (the drill-sergeant notifications provide the enforcement, not system-level blocks).
- **Negative:** Users can cheat by switching apps during a timer session. The "PS5 locked until done" is enforced by notification guilt, not by system-level blocks.
- **Risks:** Users who need hard enforcement may find the timer insufficient. Mitigated by the drill-sergeant notification escalation making it emotionally costly to ignore.
- **What would make us reconsider:** If Apple opens the Screen Time API to non-parental-control apps, or provides a public API for triggering Focus Modes, we would integrate immediately.

### Implementation Notes

- Timer types: Pomodoro (25/5), custom durations (Pro).
- Timer continues running when app is backgrounded (local notification at completion).
- Study minutes accumulated from timer sessions count toward the daily non-negotiable.
- If timer is running and user switches away for >30 seconds, timer pauses automatically (configurable).
- XP awarded per completed timer session.

---

## ADR-023: Seeded JSON exercise library with server-hosted expansion

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

The Training module needs an exercise database with names, muscle groups, equipment requirements, compound/isolation flags, and optional video/image references. This database could be bundled with the app, hosted on the server, or user-generated.

### Decision

Bundle a seed JSON file (`Exercises.json`) with 50 essential exercises in the app binary. The full library (200+ exercises) is hosted on the server and fetched/cached by Pro users. Users can also create custom exercises locally.

### Alternatives Considered

**Server-hosted only (no seed data)**
- Pros: Single source of truth. Updates immediately without app release.
- Cons: First app launch requires internet to display any exercises. Offline workout logging has no exercise list. New user experience depends on server availability.
- Why rejected: Offline-first design requires exercise data to be available without internet. A new user in a gym with poor signal must be able to start logging immediately.

**Fully user-generated (no preset library)**
- Pros: Zero maintenance of exercise database. Users create exactly what they need.
- Cons: New users face a blank slate. Creating "Bench Press" with correct muscle group metadata before logging their first set is terrible UX. Users expect a fitness app to know what a squat is.
- Why rejected: Users expect a fitness app to have a pre-built exercise library. Asking them to build one from scratch is a non-starter.

**Full library bundled in app binary**
- Pros: Everything available offline immediately. No server dependency.
- Cons: 200+ exercises with descriptions and metadata would add ~1-2MB to the app binary. Every exercise update requires an App Store release. The full library is a Pro feature, but bundling it in the free binary means free users download data they cannot use.
- Why rejected: Unnecessary binary size increase. Exercise library updates should not require App Store review.

### Consequences

- **Positive:** Instant availability of core exercises (offline). Full library available to Pro users via server fetch. Custom exercises allow personalization. Exercise updates do not require app releases.
- **Negative:** Two-tier library creates complexity (seed + server-fetched). Sync logic for exercise library updates.
- **Risks:** If the server library diverges from the seed data (renamed exercise, changed metadata), conflicts need resolution.
- **What would make us reconsider:** If app binary size is not a concern (Apple allows larger binaries), bundling the full library simplifies the architecture.

### Implementation Notes

- `Exercises.json` bundled in app Resources folder. Loaded into SwiftData on first launch.
- Server endpoint `GET /v1/exercises` returns the full catalog with pagination. Pro users fetch and cache locally.
- Custom exercises created locally in SwiftData with `isCustom = true` flag. Not synced to server (private to user).
- Exercise metadata: name, muscle group, secondary muscles, equipment, compound flag, instructions text.

---

## ADR-024: PostHog for analytics over Firebase Analytics and Mixpanel

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo needs product analytics: funnel analysis (onboarding completion), retention cohorts (D1/D7/D30), feature usage tracking, and A/B testing for paywall optimization. Tempo is a health-adjacent app that explicitly promises "we never sell your data" and handles HealthKit data under Apple's strict guidelines.

### Decision

PostHog (cloud or self-hosted) for all product analytics, feature flags, and A/B testing. Firebase Crashlytics for crash reporting only.

### Alternatives Considered

**Firebase Analytics**
- Pros: Free. Deep Google ecosystem integration. Mature iOS SDK. BigQuery export for advanced analysis.
- Cons: Data processed by Google. For a health-adjacent app that promises not to share data with third parties, routing analytics through Google's infrastructure contradicts the privacy narrative. Limited to 500 custom event types. No built-in feature flags (requires Firebase Remote Config, which is a separate product with limited capabilities). No session replay.
- Why rejected: The privacy conflict with Google data processing is the primary issue. Secondary: limited event types and no integrated feature flags.

**Mixpanel**
- Pros: Excellent funnel and retention analysis. Good iOS SDK. Powerful segmentation.
- Cons: Cloud-only (no self-hosted option). US data centers only at lower tiers. Expensive above 100K monthly tracked users. No built-in feature flags. No session replay. Privacy concerns similar to any cloud analytics provider, though Mixpanel is more privacy-focused than Google.
- Why rejected: PostHog provides the same funnel/retention analysis plus feature flags, session replay, and self-hosting option -- all in one tool. Mixpanel would require adding a separate tool for feature flags.

**Amplitude**
- Pros: Sophisticated behavioral analytics. Built-in A/B testing.
- Cons: Expensive at scale. Cloud-only. The built-in A/B testing requires their Experiment product (additional pricing). PostHog offers comparable analytics with integrated feature flags at a lower cost.
- Why rejected: PostHog matches Amplitude's core analytics while bundling feature flags and session replay at lower cost.

### Consequences

- **Positive:** One tool for analytics, feature flags, A/B testing, and session replay. Self-hosted option provides the strongest privacy story for a health app. PostHog's free tier (1M events/month cloud) is generous for early-stage. No additional tool needed for feature flags.
- **Negative:** PostHog's iOS SDK is younger than Firebase/Mixpanel SDKs. Fewer tutorials and community resources. Self-hosting requires infrastructure management.
- **Risks:** PostHog could change pricing or deprecate features. Mitigated by the `AnalyticsService` wrapper -- all analytics calls go through a single class, making provider swaps feasible.
- **What would make us reconsider:** If PostHog's iOS SDK has reliability issues (missed events, SDK crashes), we would evaluate Mixpanel as a replacement while keeping the wrapper abstraction.

### Implementation Notes

- `AnalyticsService` singleton wraps PostHog SDK. No module imports PostHog directly.
- Event naming: `snake_case`, `verb_noun` pattern (e.g., `workout_completed`, `dashboard_viewed`).
- All events auto-tagged with: `event_id`, `timestamp`, `session_id`, `app_version`, `device_model`, `screen_name`.
- No health biometric data in analytics events. Only behavioral data (screens viewed, features used, conversion events).
- Feature flags fetched on app launch and cached locally. Flag changes take effect on next launch.

---

## ADR-025: Cloud deployment (Railway/Fly.io) over self-hosted infrastructure

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

The Vapor backend needs to run 24/7 with SSL, domain routing, PostgreSQL, Redis, and zero-downtime deploys. The developer is a university student with limited time for infrastructure operations.

### Decision

Deploy on a managed container platform (Railway or Fly.io) with managed PostgreSQL and Redis. No self-hosted VPS.

### Alternatives Considered

**Self-hosted VPS (DigitalOcean/Hetzner)**
- Pros: Full control. Lower cost at scale ($5-10/month for a VPS). Can run PostgreSQL, Redis, and Vapor on one machine. No vendor lock-in.
- Cons: The developer is responsible for: OS updates, security patches, SSL certificate management (Let's Encrypt automation), PostgreSQL backups and monitoring, Redis configuration, Docker daemon management, firewall rules, DDoS mitigation, uptime monitoring, zero-downtime deployment scripting. For a university student shipping a product, every hour spent on ops is an hour not spent on features.
- Why rejected: The operational burden of a VPS is not justified when managed platforms handle all of it for $10-30/month. At Tempo's early scale, the cost difference between a VPS and Railway is negligible. The time saved is significant.

**AWS (ECS/Fargate + RDS + ElastiCache)**
- Pros: Enterprise-grade. Auto-scaling. Global infrastructure.
- Cons: AWS complexity for a solo developer is immense: IAM roles, VPC configuration, security groups, ECS task definitions, CloudWatch alarms, RDS parameter groups, ElastiCache cluster management. The AWS free tier helps initially but costs escalate unpredictably. The learning curve delays shipping.
- Why rejected: AWS is designed for teams with dedicated DevOps engineers. A solo developer deploying a Vapor app should not need to learn IAM policies.

**Heroku**
- Pros: Simple `git push` deployment. Managed add-ons for PostgreSQL and Redis.
- Cons: Heroku eliminated its free tier in 2022. The Eco/Basic plans have limitations (sleeps after 30 minutes of inactivity, slow cold starts). Heroku's Docker support is less flexible than Railway/Fly.io. Salesforce ownership has led to stagnation.
- Why rejected: Railway and Fly.io are the modern successors to Heroku with better pricing, performance, and Docker support.

### Consequences

- **Positive:** Zero-ops deployment (`git push` or Docker deploy). Managed PostgreSQL with automatic backups. Managed Redis. SSL termination. Health checks. Log aggregation. Focus on code, not infrastructure.
- **Negative:** Vendor lock-in (moderate -- Docker containers are portable). Higher cost than a bare VPS at scale. Less control over infrastructure tuning.
- **Risks:** Railway or Fly.io could change pricing or shut down. Mitigated by Docker-based deployment: the container runs anywhere.
- **What would make us reconsider:** If Tempo reaches a scale where managed platform costs exceed $200/month and a VPS would cost $30/month, the economics shift toward self-hosting with Coolify or Kamal for deployment automation.

### Implementation Notes

- Multi-stage Dockerfile: Swift 5.10 build stage, Ubuntu 22.04 runtime stage.
- Railway.toml or fly.toml for deployment configuration.
- Environment variables managed through the platform's secrets management.
- Health check endpoint: `GET /v1/health/live` returns 200 if the server is running.
- Database migrations run automatically on deploy via Vapor's `--auto-migrate` flag.

---

## ADR-026: PostHog feature flags over LaunchDarkly and custom solutions

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo needs feature flags for: A/B testing paywall variants, gradual feature rollouts, kill switches for buggy features, and experiment-driven development. Feature flags should work on the iOS client and optionally on the backend.

### Decision

Use PostHog's built-in feature flags (same tool as analytics). No separate feature flag service.

### Alternatives Considered

**LaunchDarkly**
- Pros: Industry-leading feature flag platform. Real-time flag updates. Sophisticated targeting (user segments, percentage rollouts, scheduling). Excellent iOS SDK.
- Cons: Expensive ($10/month/seat minimum, plus per-seat pricing that scales with team size). A separate tool from analytics, requiring two integrations, two dashboards, two SDKs. For a solo developer with PostHog already integrated, adding LaunchDarkly doubles the toolchain complexity.
- Why rejected: PostHog provides feature flags as part of its analytics platform. Adding a $10+/month dedicated tool for flags when the analytics tool already includes them is unnecessary cost and complexity.

**Custom feature flag system (server-side config endpoint)**
- Pros: Full control. Zero external dependency. Simple key-value store in PostgreSQL or Redis.
- Cons: Must build: flag management UI (or manage via database queries), percentage-based rollout logic, user targeting, flag evaluation caching, audit logging of flag changes. Reinventing a solved problem. No A/B test statistical analysis built-in.
- Why rejected: Building a custom feature flag system is engineering time spent on infrastructure instead of product features. PostHog provides all of this out of the box.

### Consequences

- **Positive:** One tool for analytics + feature flags + A/B testing. No additional cost. Flags are automatically linked to analytics events (PostHog tracks `$feature_flag_called` automatically). Percentage rollouts and user targeting built-in.
- **Negative:** PostHog's feature flag evaluation is slower than LaunchDarkly's (cached on app launch vs real-time streaming). Flag changes take effect on next app launch, not mid-session.
- **Risks:** If PostHog's feature flag reliability is insufficient (stale flags, evaluation errors), LaunchDarkly is the upgrade path.
- **What would make us reconsider:** If Tempo needs real-time flag updates (kill switch that takes effect within seconds, not on next app launch), LaunchDarkly's streaming architecture would be necessary.

### Implementation Notes

- Feature flags fetched on app launch via `posthog.reloadFeatureFlags()`.
- Cached locally. All evaluations are local (no network call per flag check).
- Flag naming convention: `experiment_<name>` for A/B tests, `feature_<name>` for rollouts, `kill_<name>` for kill switches.
- Every flag evaluation automatically logs to PostHog for experiment analysis.

---

## ADR-027: Firebase Crashlytics for crash reporting over Sentry

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo needs crash reporting with symbolicated stack traces, breadcrumbs, and crash-free user percentage tracking. The app uses Swift, SwiftUI, and SwiftData -- symbolication must support Swift name mangling.

### Decision

Firebase Crashlytics for crash reporting only. No other Firebase products.

### Alternatives Considered

**Sentry**
- Pros: Self-hostable. Rich error tracking beyond crashes (non-fatal errors, performance transactions). Privacy-friendly (can self-host). Good iOS SDK. Breadcrumbs. Source maps.
- Cons: More complex setup than Crashlytics. Self-hosted Sentry requires significant infrastructure (PostgreSQL, Redis, Kafka, ClickHouse, Snuba). Cloud Sentry's free tier is limited (5K errors/month, 1 user). Paid plans start at $26/month. For crash reporting alone, Sentry is over-engineered and over-priced.
- Why rejected: Crashlytics is free, has the best iOS crash symbolication in the industry, and requires minimal setup. Sentry's additional capabilities (performance monitoring, non-fatal error tracking) are valuable but not necessary at launch. If PostHog or Crashlytics miss something, Sentry is the upgrade path.

**Bugsnag**
- Pros: Good iOS SDK. Stability scoring. Release health tracking.
- Cons: Paid ($99/month for small team plan). Less community adoption than Crashlytics or Sentry. No self-hosted option.
- Why rejected: Crashlytics is free and provides equivalent crash reporting capabilities.

### Consequences

- **Positive:** Free. Industry-standard iOS crash symbolication. Minimal setup (one SDK, one plist file). Crash-free user percentage in Firebase console.
- **Negative:** Google dependency (analytics/privacy concern). Mitigated by using Crashlytics ONLY for crashes -- no Firebase Analytics, no other Firebase products. Firebase Crashlytics SDK sends crash data to Google servers.
- **Risks:** Google could deprecate Crashlytics (they deprecated Fabric by acquiring and absorbing it). Extremely unlikely given Firebase's strategic importance to Google.
- **What would make us reconsider:** If the Google data processing concern becomes a liability (e.g., Apple flags it during review, or users complain), Sentry Cloud is the replacement.

### Implementation Notes

- Add `FirebaseCrashlytics` SDK only. Do NOT add `FirebaseAnalytics` or any other Firebase product.
- Disable Firebase Analytics data collection: `FirebaseConfiguration.shared.setLoggerLevel(.min)` and `FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED = YES` in Info.plist.
- Upload dSYM files to Firebase during CI build for symbolication.
- Non-fatal errors: log critical non-crash errors (sync failures, API errors) via `Crashlytics.crashlytics().record(error:)`.

---

## ADR-028: Apple Watch as companion app, not independent

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo plans an Apple Watch app for gym workout logging (set/rep tracking from the wrist), glanceable daily score, rest timer, focus timer control, and complications. The Watch app could be a companion to the iPhone app or an independent app that works without the iPhone nearby.

### Decision

Companion Watch app. The Watch depends on the paired iPhone for data, computation, and backend communication. The Watch is a display and input terminal, not a compute node.

### Alternatives Considered

**Independent Watch app**
- Pros: Works without iPhone nearby (e.g., at the gym with Watch only). Can run its own network stack and authenticate with the backend directly.
- Cons: Tempo's data originates from multiple server-side sources (Whoop API via backend, NutriTrack via backend, Arena leaderboards from PostgreSQL). The Watch would need its own network stack, JWT storage, and authentication flow. SwiftData models and all engine logic (TrainingEngine, RecoveryEngine, ScoringEngine) would need to be compiled for watchOS -- significant code sharing complexity. Battery life on Watch would suffer from network requests and heavy computation. The Watch's limited memory (e.g., 1GB on Series 6) constrains the data model size.
- Why rejected: The complexity of making the Watch independent is enormous for minimal benefit. The vast majority of Apple Watch gym users carry their iPhone. The Watch's value is wrist-level input/output during workouts, not standalone operation.

### Consequences

- **Positive:** Simple architecture. Watch receives a lightweight `WatchSnapshot` from iPhone via Watch Connectivity. All computation happens on iPhone. Battery life preserved. Code sharing limited to DTOs and UI components.
- **Negative:** Watch app does not function without paired iPhone. If a user leaves their phone in a locker and wears their Watch, the Watch has only its last-synced snapshot (not live data).
- **Risks:** Apple could push developers toward independent Watch apps (trend in recent watchOS releases). If App Store review requires Watch apps to function independently, we would need to add minimal standalone capability.
- **What would make us reconsider:** If user feedback strongly requests "Watch-only gym sessions" (phone in locker, Watch on wrist), we would evaluate adding direct HealthKit reads on Watch (available natively) plus local workout logging with post-session sync to iPhone. This is a partial-independence model, not full independence.

### Implementation Notes

- Communication via `WCSession`: `applicationContext` for background updates, `sendMessage` for interactive data, `transferUserInfo` for guaranteed delivery.
- `WatchSnapshot` data model: daily score, recovery zone, next task, non-negotiable progress, XP, leaderboard position. Lightweight, serialized to ~1KB.
- `WatchWorkoutState`: current workout exercises and sets, synced from iPhone at workout start. Set completions sent back to iPhone immediately.
- Complications: `TempoComplicationProvider` refreshed via `transferCurrentComplicationUserInfo` from iPhone when daily score changes.
- Target: watchOS 10.0+ minimum, Apple Watch Series 6+.

---

## ADR-029: iPad support deferred to post-1.0

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

SwiftUI apps can run on iPad with minimal code changes (automatic multi-column navigation, larger canvas). However, designing a compelling iPad experience (not just a stretched iPhone layout) requires thoughtful use of the larger screen: multi-column dashboards, side-by-side views, keyboard support, pointer interaction.

### Decision

Defer iPad support to post-1.0. The initial release targets iPhone only. iPad users can run the iPhone version in compatibility mode.

### Alternatives Considered

**iPad from day one**
- Pros: Larger market. Students study on iPads. Dashboard looks great on larger screens. SwiftUI makes basic iPad support nearly free.
- Cons: "Basic iPad support" (stretched iPhone layout) looks bad and gets 1-star reviews from iPad users who expect better. Proper iPad support requires: multi-column NavigationSplitView, different dashboard layouts, keyboard shortcuts, pointer hover states, drag-and-drop, and testing on multiple iPad sizes. For a solo developer, this is 1-2 extra weeks of work that delays iPhone launch. HealthKit on iPad is limited (no step counting, no heart rate -- iPad has no health sensors). Whoop connects to iPhone, not iPad.
- Why rejected: iPad HealthKit limitations make the app less useful on iPad anyway (no steps, no HR). The development time is better spent on iPhone features. A half-baked iPad version is worse than no iPad version.

**iPad-optimized from day one**
- Pros: Best possible experience for iPad users from launch.
- Cons: Doubles the design surface area. Every screen needs two layouts. Testing matrix grows significantly. Not justified for v1 when HealthKit on iPad is limited.
- Why rejected: Premature optimization. Ship iPhone first, then invest in iPad if demand warrants.

### Consequences

- **Positive:** Focused development on the primary platform (iPhone). Faster time to market. No risk of a mediocre iPad experience damaging reviews.
- **Negative:** iPad users cannot use Tempo (or can only run the iPhone compatibility version). Missing a potential market segment.
- **Risks:** If a competitor launches with a beautiful iPad study dashboard, we miss that audience.
- **What would make us reconsider:** If iPad user requests exceed 15% of feedback after iPhone launch, or if a "study dashboard" feature emerges that is naturally suited to iPad's large screen, we would prioritize iPad support.

### Implementation Notes

- Set Xcode deployment target to iPhone only (not Universal).
- SwiftUI code should use `NavigationStack` (not `NavigationSplitView` which is iPad-oriented) for v1. When iPad support is added, convert to `NavigationSplitView` with adaptive behavior.
- Avoid hardcoded dimensions that would look wrong on iPad. Use `GeometryReader` and relative sizing where possible, so the eventual iPad adaptation is easier.

---

## ADR-030: Android not planned; no cross-platform rewrite

**Status:** Accepted
**Date:** 2026-03-24
**Deciders:** Nicola (solo developer)

### Context

Tempo is built for iOS. Friends, teammates, or potential users may ask about Android. The decision about Android affects architecture choices (should we abstract platform APIs for portability?) and resource allocation.

### Decision

No Android version planned. No cross-platform rewrite. Tempo is iOS-only and the architecture does not prioritize Android portability.

### Alternatives Considered

**Eventual Android (Kotlin/Jetpack Compose native)**
- Pros: Full Android market. Kotlin Multiplatform (KMP) could share business logic with Swift.
- Cons: Building and maintaining two native apps as a solo developer is not sustainable. HealthKit has no Android equivalent (Google Health Connect is the closest, but has different APIs and data types). Whoop integration on Android would require a separate implementation. Push notifications use FCM instead of APNs. The entire service layer would need to be reimplemented.
- Why rejected: A solo developer maintaining two native apps across two platforms with different health APIs, push systems, and UI frameworks would ship features at half speed and fix bugs at double effort.

**Cross-platform rewrite (Flutter/React Native)**
- Pros: Single codebase for both platforms.
- Cons: See ADR-001. Tempo's deep Apple ecosystem integration (HealthKit, EventKit, APNs, WatchKit, WidgetKit, SwiftData) makes a cross-platform rewrite a regression in functionality and user experience. The rewrite would take months and the iOS version would stagnate during that time.
- Why rejected: Rewriting a shipping iOS app in a cross-platform framework is one of the most common and most costly mistakes in mobile development. The loss of native API access and the months of rewrite time outweigh the cross-platform benefit.

**Kotlin Multiplatform (KMP) shared logic**
- Pros: Share business logic (scoring engine, training engine, recovery engine) in Kotlin, with native UI on each platform (SwiftUI on iOS, Compose on Android).
- Cons: KMP is still maturing (especially the iOS interop story). Adding KMP to an existing Swift project requires restructuring the business logic layer into a Kotlin module, which is a significant refactor. The developer does not currently know Kotlin. The benefit only materializes if Android is definitely happening.
- Why rejected: KMP is the correct long-term strategy IF Android becomes necessary. But investing in KMP before validating product-market fit on iOS is premature. Revisit after iOS has proven traction.

### Consequences

- **Positive:** Full focus on one platform. Faster iteration. No abstraction layers that compromise iOS-native capabilities. Deepest possible integration with Apple ecosystem.
- **Negative:** Android users are excluded. If Tempo gains traction, Android demand will grow.
- **Risks:** If the addressable market analysis shows 40%+ Android users in the target demographic (university students in certain regions), significant revenue is left on the table.
- **What would make us reconsider:** If iOS Tempo achieves product-market fit (>10K active users, positive unit economics) and Android demand is validated (>30% of support requests asking for Android), the path forward is: (1) extract business logic into a shared Kotlin Multiplatform module, (2) build Android UI in Jetpack Compose, (3) maintain the REST API contract as the shared interface between platforms and backend.

### Implementation Notes

- Do not add abstraction layers for "future Android portability." They add complexity now for uncertain future benefit.
- The REST API between iOS and Vapor backend IS the platform abstraction. An Android client would consume the same API.
- Keep business logic in the iOS service layer (TrainingEngine, RecoveryEngine, ScoringEngine) clean and well-tested. If KMP extraction is needed later, well-tested algorithms are easier to port than tangled view model code.
