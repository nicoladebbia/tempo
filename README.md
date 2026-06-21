# Tempo

> Your life operating system — a native iOS app that unifies training, recovery, nutrition, focus, and social accountability into one adaptive daily plan.

## What it does

Tempo pulls together signals from Apple HealthKit, Whoop, Apple Calendar, and WeatherKit to build a single picture of your day. It scores your readiness each morning, adapts your training and nutrition to how recovered you are, keeps you accountable with focus sessions and non-negotiables, and gamifies the whole thing with XP, achievements, and friend leaderboards. An on-device/proxied AI coach ties it together — it plans your day, answers questions, and learns your preferences over time.

The app is organized around a tabbed life-OS dashboard. State persists locally with SwiftData and syncs through a Swift (Vapor) backend that brokers integrations, push notifications, subscriptions, and metered AI calls.

## Modules

- **Dashboard** — The home view. A daily plan and a four-quadrant life score (Move, Fuel, Mind, Body) with drill-down detail views, a welcome banner, weekly reports, and data export.
- **Training** — Adaptive workout programming. Today's workout, active workout tracking with rest timers and inline set feedback, an exercise library, week/month plans, match-schedule awareness (football practice), progress charts, and workout history. An AI program planner and safety floor adjust load to recovery.
- **Recovery** — Morning check-in, readiness scoring, sleep and strain detail, recovery trends, weekly summaries, AI recovery insights, and Whoop connection management.
- **Accountability (Lockdown)** — Focus timer with Live Activities, focus history, streak calendar, non-negotiable setup, and weekly accountability tracking.
- **Arena** — Social and gamification layer. XP engine, achievements, challenges, activity feed, a friend system, and a weekly leaderboard.
- **Coach** — Conversational AI coach with chat history, an onboarding interview, persistent memory, learned preferences/outcomes, voice input, and weekly self-grade cards.
- **Nutrition** — Meal logging, food and barcode search, dietary-profile setup, macro/target tracking, AI-generated meals, grocery lists (with receipt scanning and Reminders export), and a nutrition coach.

## Tech stack

**iOS app**
- Swift 6 (strict/complete concurrency), SwiftUI, SwiftData for local persistence
- iOS 17.4+ deployment target; portrait-only, dark mode
- HealthKit, WeatherKit, EventKit (Calendar/Reminders), Speech, WidgetKit + Live Activities, App Intents
- Companion watchOS app (TempoWatch) and a home-screen/Lock Screen widget (TempoWidget)
- Dependencies: PostHog (analytics), Firebase Crashlytics, Lottie, Inject (debug-only SwiftUI hot reload), swift-snapshot-testing (tests)
- AI features call Anthropic Claude, proxied/metered through the backend

**Backend** (`tempo-backend/`)
- Vapor 4 on Swift 6, Fluent ORM with PostgreSQL, Redis, Vapor Queues (background jobs)
- JWT (ES256) auth, APNs push, App Store subscription verification, Whoop OAuth + webhooks, AI spend metering/caching

**Project tooling**
- XcodeGen (`project.yml`) generates the Xcode project — do not edit `.xcodeproj` by hand
- SwiftLint + SwiftFormat enforced as pre-build phases; Fastlane for release automation
- Three configurations: Debug (dev), Staging, Release

## Build & run

Requirements:
- macOS with Xcode 26.5+
- [XcodeGen](https://github.com/yonyz/XcodeGen) (`brew install xcodegen`)
- SwiftLint and SwiftFormat (`brew install swiftlint swiftformat`)
- An Apple Developer team for code signing (HealthKit, Live Activities, and push require a real device/provisioning)

Generate and open the iOS project:

```bash
cd Tempo
xcodegen generate
open Tempo.xcodeproj
```

Build and run the **Tempo** scheme (Debug config uses the `app.tempo.Tempo.dev` bundle id). Set `ANTHROPIC_API_KEY`, `TEMPO_API_BASE_URL`, and `TEMPO_ENVIRONMENT` via the `Tempo/Configuration/*.xcconfig` files for the configuration you build.

Backend (Vapor):

```bash
cd tempo-backend
swift run App
```

Requires PostgreSQL and Redis. Configuration is via environment variables (see `Sources/App/configure.swift`).

## Project status

Pre-release, targeting App Store launch (marketing version 1.0.0). Active development happens on the `training-intelligence` branch. The codebase has unit, snapshot, and UI test targets; the deeper design rationale lives in `ARCHITECTURE.md` and `MULTI_AGENT.md`.
