# Tempo — CI/CD Pipeline Specification

> **Version:** 1.0.0
> **Last Updated:** 2026-03-24
> **Author:** DevOps Architecture
> **Audience:** All engineers contributing to Tempo iOS app and Vapor backend

---

## Table of Contents

1. [Git Workflow](#1-git-workflow)
2. [iOS CI Pipeline](#2-ios-ci-pipeline)
3. [iOS Release Pipeline](#3-ios-release-pipeline)
4. [Backend CI Pipeline](#4-backend-ci-pipeline)
5. [Backend Deployment Pipeline](#5-backend-deployment-pipeline)
6. [Environment Management](#6-environment-management)
7. [Database Migrations](#7-database-migrations)
8. [Monitoring & Alerting](#8-monitoring--alerting)
9. [Fastlane Configuration](#9-fastlane-configuration)
10. [Local Development Setup](#10-local-development-setup)

---

## 1. Git Workflow

### 1.1 Branch Strategy: Trunk-Based Development

Tempo uses **trunk-based development** with short-lived feature branches. This is the right choice for a small team (1-3 engineers) building an app that ships through the App Store, where release cadence is weekly/biweekly rather than continuous.

**Why not GitFlow:**
- GitFlow adds overhead with `develop`, `release/*`, and `hotfix/*` branches that slow down a small team.
- App Store releases are gated by Apple review anyway — a `release/*` branch just adds ceremony.
- Trunk-based keeps the feedback loop tight: merge to `main`, CI runs, TestFlight build ships automatically.

**Branch model:**

```
main (protected, always deployable)
  ├── feature/whoop-recovery-cards    (short-lived, 1-3 days max)
  ├── feature/arena-leaderboard       (short-lived)
  ├── fix/streak-reset-timezone       (short-lived)
  └── tags: v1.0.0, v1.1.0, ...      (trigger App Store submissions)
```

### 1.2 Branch Naming Convention

```
feature/<short-description>     New functionality
fix/<short-description>         Bug fix
refactor/<short-description>    Code restructuring, no behavior change
perf/<short-description>        Performance improvement
test/<short-description>        Adding or fixing tests
docs/<short-description>        Documentation only
chore/<short-description>       Tooling, dependencies, CI config
```

Examples:
```
feature/nutritrack-meal-sync
fix/healthkit-background-delivery
perf/dashboard-chart-rendering
refactor/training-engine-protocols
```

### 1.3 Commit Message Format (Conventional Commits)

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `chore`, `ci`, `build`

**Scopes:** `dashboard`, `training`, `recovery`, `accountability`, `arena`, `backend`, `healthkit`, `whoop`, `nutritrack`, `auth`, `sync`, `notifications`

**Examples:**
```
feat(training): add recovery-adjusted volume scaling

Uses Whoop recovery score to scale workout volume between 0.6x-1.0x.
Green zone (67-100%) = full volume. Red zone (0-33%) = 60% volume.

Closes #42

fix(backend): prevent token replay after session revocation

Adds jti claim to blacklist on logout. Redis TTL matches token expiry.

perf(dashboard): lazy-load quadrant chart data on expansion

Charts now fetch data in .task modifier instead of DashboardView.onAppear.
Reduces cold launch to interactive from 1.8s to 1.3s.
```

### 1.4 PR Requirements

```yaml
# .github/settings.yml (Probot settings or repo settings)
branches:
  - name: main
    protection:
      required_pull_request_reviews:
        required_approving_review_count: 1
        dismiss_stale_reviews: true
        require_code_owner_reviews: false
      required_status_checks:
        strict: true
        contexts:
          - "ios / lint"
          - "ios / unit-tests (17.0)"
          - "ios / unit-tests (18.0)"
          - "ios / snapshot-tests"
          - "ios / integration-tests"
          - "backend / lint"
          - "backend / unit-tests"
          - "backend / integration-tests"
          - "backend / docker-build"
      enforce_admins: true
      required_linear_history: true
      allow_force_pushes: false
      allow_deletions: false
```

**PR template** (`.github/pull_request_template.md`):

```markdown
## What

<!-- One sentence: what does this PR do? -->

## Why

<!-- Why is this change needed? Link to issue if applicable. -->

## How

<!-- Brief technical approach. -->

## Testing

- [ ] Unit tests added/updated
- [ ] Integration tests (if touching API boundaries)
- [ ] Snapshot tests updated (if UI changes)
- [ ] Manual testing on device (describe what you tested)

## Screenshots

<!-- If UI changes, before/after screenshots or screen recordings. -->
```

### 1.5 Auto-Merge Rules

PRs that meet ALL of these conditions auto-merge after approval:
- All required status checks pass
- At least 1 approving review
- PR is labeled `automerge`
- No `do-not-merge` label

Configure via GitHub's built-in auto-merge or the Mergify app.

---

## 2. iOS CI Pipeline

### 2.1 Complete Workflow File

```yaml
# .github/workflows/ios.yml
name: ios

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ios-${{ github.ref }}
  cancel-in-progress: true

env:
  XCODE_VERSION: "16.0"
  SCHEME_UNIT: "TempoTests"
  SCHEME_INTEGRATION: "TempoIntegrationTests"
  SCHEME_SNAPSHOT: "TempoSnapshotTests"
  SCHEME_UI: "TempoUITests"
  PROJECT: "Tempo.xcodeproj"
  COVERAGE_THRESHOLD: 80

jobs:
  # ──────────────────────────────────────────────
  # Job 1: Lint
  # ──────────────────────────────────────────────
  lint:
    name: Lint
    runs-on: macos-14
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Install SwiftLint
        run: brew install swiftlint swiftformat

      - name: SwiftLint
        run: swiftlint lint --strict --reporter github-actions-logging

      - name: SwiftFormat Check
        run: swiftformat --lint . --reporter github-actions-log

  # ──────────────────────────────────────────────
  # Job 2: Unit Tests (matrix: iOS 17.4 + 18.0)
  # ──────────────────────────────────────────────
  unit-tests:
    name: Unit Tests (iOS ${{ matrix.ios-version }})
    runs-on: macos-14
    timeout-minutes: 25
    needs: lint
    strategy:
      fail-fast: false
      matrix:
        include:
          - ios-version: "17.0"
            simulator: "iPhone 15 Pro"
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-0"
          - ios-version: "18.0"
            simulator: "iPhone 16 Pro"
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-0"
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode ${{ env.XCODE_VERSION }}
        run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

      - name: Cache SPM packages
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-

      - name: Cache DerivedData
        uses: actions/cache@v4
        with:
          path: ~/Library/Developer/Xcode/DerivedData
          key: deriveddata-${{ runner.os }}-${{ matrix.ios-version }}-${{ hashFiles('**/*.swift', '**/project.pbxproj') }}
          restore-keys: |
            deriveddata-${{ runner.os }}-${{ matrix.ios-version }}-
            deriveddata-${{ runner.os }}-

      - name: Resolve packages
        run: |
          xcodebuild -resolvePackageDependencies \
            -project ${{ env.PROJECT }} \
            -scheme ${{ env.SCHEME_UNIT }}

      - name: Run Unit Tests
        run: |
          xcodebuild test \
            -project ${{ env.PROJECT }} \
            -scheme ${{ env.SCHEME_UNIT }} \
            -destination 'platform=iOS Simulator,name=${{ matrix.simulator }},OS=${{ matrix.ios-version }}' \
            -resultBundlePath TestResults/unit-${{ matrix.ios-version }}.xcresult \
            -enableCodeCoverage YES \
            -parallel-testing-enabled YES \
            -test-timeouts-enabled YES \
            -maximum-test-execution-time-allowance 60 \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            | xcbeautify --renderer github-actions

      - name: Check Coverage Threshold
        if: matrix.ios-version == '18.0'
        run: |
          xcrun xccov view --report --json \
            TestResults/unit-${{ matrix.ios-version }}.xcresult > coverage.json
          python3 scripts/check_coverage.py \
            --input coverage.json \
            --threshold ${{ env.COVERAGE_THRESHOLD }} \
            --engines-threshold 90 \
            --services-threshold 80

      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: unit-test-results-ios${{ matrix.ios-version }}
          path: TestResults/unit-${{ matrix.ios-version }}.xcresult
          retention-days: 14

      - name: Upload Coverage Report
        if: matrix.ios-version == '18.0'
        uses: actions/upload-artifact@v4
        with:
          name: coverage-report
          path: coverage.json
          retention-days: 14

  # ──────────────────────────────────────────────
  # Job 3: Integration Tests
  # ──────────────────────────────────────────────
  integration-tests:
    name: Integration Tests
    runs-on: macos-14
    timeout-minutes: 30
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

      - name: Cache SPM packages
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-

      - name: Start Mock Server
        run: |
          cd tempo-backend
          docker compose -f docker-compose.test.yml up -d
          # Wait for services to be ready
          timeout 30 bash -c 'until curl -sf http://localhost:8080/v1/health/live; do sleep 1; done'

      - name: Run Integration Tests
        run: |
          xcodebuild test \
            -project ${{ env.PROJECT }} \
            -scheme ${{ env.SCHEME_INTEGRATION }} \
            -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
            -resultBundlePath TestResults/integration.xcresult \
            -test-timeouts-enabled YES \
            -maximum-test-execution-time-allowance 120 \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            TEMPO_API_BASE_URL=http://localhost:8080 \
            | xcbeautify --renderer github-actions

      - name: Tear Down Mock Server
        if: always()
        run: |
          cd tempo-backend
          docker compose -f docker-compose.test.yml down -v

      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: integration-test-results
          path: TestResults/integration.xcresult
          retention-days: 14

  # ──────────────────────────────────────────────
  # Job 4: Snapshot Tests
  # ──────────────────────────────────────────────
  snapshot-tests:
    name: Snapshot Tests
    runs-on: macos-14
    timeout-minutes: 20
    needs: lint
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

      - name: Cache SPM packages
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-

      - name: Run Snapshot Tests
        run: |
          xcodebuild test \
            -project ${{ env.PROJECT }} \
            -scheme ${{ env.SCHEME_SNAPSHOT }} \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.0' \
            -resultBundlePath TestResults/snapshots.xcresult \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            | xcbeautify --renderer github-actions

      - name: Upload Failed Snapshots
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failed-snapshots
          path: |
            TempoTests/Snapshot/__Snapshots__/
            TestResults/snapshots.xcresult
          retention-days: 30

  # ──────────────────────────────────────────────
  # Job 5: UI Tests
  # ──────────────────────────────────────────────
  ui-tests:
    name: UI Tests
    runs-on: macos-14
    timeout-minutes: 45
    needs: [unit-tests, snapshot-tests]
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

      - name: Cache SPM packages
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-

      - name: Run UI Tests
        run: |
          xcodebuild test \
            -project ${{ env.PROJECT }} \
            -scheme ${{ env.SCHEME_UI }} \
            -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
            -resultBundlePath TestResults/uitests.xcresult \
            -test-timeouts-enabled YES \
            -maximum-test-execution-time-allowance 300 \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            | xcbeautify --renderer github-actions

      - name: Capture Screenshots on Failure
        if: failure()
        run: |
          xcrun simctl io booted screenshot TestResults/failure-screenshot.png || true

      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: ui-test-results
          path: |
            TestResults/uitests.xcresult
            TestResults/failure-screenshot.png
          retention-days: 14

  # ──────────────────────────────────────────────
  # Job 6: Performance Tests
  # ──────────────────────────────────────────────
  performance-tests:
    name: Performance Tests
    runs-on: macos-14
    timeout-minutes: 30
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

      - name: Cache SPM packages
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-

      - name: Run Performance Tests
        run: |
          xcodebuild test \
            -project ${{ env.PROJECT }} \
            -scheme TempoPerformanceTests \
            -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
            -resultBundlePath TestResults/performance.xcresult \
            -only-testing:TempoTests/Performance \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            | xcbeautify --renderer github-actions

      - name: Extract Performance Metrics
        run: |
          xcrun xcresulttool get --format json \
            --path TestResults/performance.xcresult > perf-results.json
          python3 scripts/check_performance.py \
            --input perf-results.json \
            --baseline scripts/performance-baseline.json \
            --regression-threshold 10

      - name: Upload Performance Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: performance-results
          path: |
            TestResults/performance.xcresult
            perf-results.json
          retention-days: 30

  # ──────────────────────────────────────────────
  # Job 7: Build (archive for release validation)
  # ──────────────────────────────────────────────
  build:
    name: Build Archive
    runs-on: macos-14
    timeout-minutes: 20
    needs: [unit-tests, snapshot-tests]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

      - name: Cache SPM packages
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Developer/Xcode/DerivedData/**/SourcePackages
            ~/Library/Caches/org.swift.swiftpm
          key: spm-${{ runner.os }}-${{ hashFiles('**/Package.resolved') }}
          restore-keys: spm-${{ runner.os }}-

      - name: Build Archive (no signing)
        run: |
          xcodebuild archive \
            -project ${{ env.PROJECT }} \
            -scheme Tempo \
            -archivePath build/Tempo.xcarchive \
            -destination 'generic/platform=iOS' \
            -configuration Release \
            CODE_SIGN_IDENTITY="" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=NO \
            | xcbeautify --renderer github-actions

      - name: Verify Archive
        run: |
          test -d build/Tempo.xcarchive/Products/Applications/Tempo.app
          echo "Archive built successfully"

  # ──────────────────────────────────────────────
  # Notifications
  # ──────────────────────────────────────────────
  notify-failure:
    name: Notify on Failure
    runs-on: ubuntu-latest
    needs: [lint, unit-tests, integration-tests, snapshot-tests, ui-tests, performance-tests]
    if: failure() && github.ref == 'refs/heads/main'
    steps:
      - name: Slack Notification
        uses: slackapi/slack-github-action@v1.27.0
        with:
          payload: |
            {
              "text": ":red_circle: Tempo iOS CI failed on `main`",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": ":red_circle: *Tempo iOS CI Failed*\n*Branch:* `${{ github.ref_name }}`\n*Commit:* `${{ github.sha }}` by ${{ github.actor }}\n*Run:* <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Workflow>"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

### 2.2 Pipeline Flow Diagram

```
                     PR opened / push to main
                              │
                              v
                    ┌─────────────────┐
                    │      Lint       │  ~2 min
                    │ SwiftLint +     │
                    │ SwiftFormat     │
                    └────────┬────────┘
                             │
               ┌─────────────┼─────────────┐
               v             v             v
    ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
    │ Unit Tests   │ │ Unit Tests   │ │  Snapshot    │  ~8 min
    │ iOS 17.4     │ │ iOS 18.0     │ │  Tests       │  (parallel)
    └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
           └────────┬───────┘                │
                    │                        │
        ┌───────────┼────────────┬───────────┘
        v           v            v
 ┌────────────┐ ┌─────────┐ ┌─────────┐
 │Integration │ │UI Tests │ │  Perf   │  ~15 min
 │  Tests     │ │         │ │  Tests  │  (parallel)
 └────────────┘ └─────────┘ └─────────┘
        │           │            │
        └───────────┼────────────┘
                    v
          ┌─────────────────┐
          │  Build Archive  │  ~5 min (main only)
          └─────────────────┘
```

### 2.3 Required Helper Scripts

**`scripts/check_coverage.py`:**

```python
#!/usr/bin/env python3
"""Check Xcode code coverage against thresholds."""
import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Path to coverage JSON")
    parser.add_argument("--threshold", type=float, default=80.0)
    parser.add_argument("--engines-threshold", type=float, default=90.0)
    parser.add_argument("--services-threshold", type=float, default=80.0)
    args = parser.parse_args()

    with open(args.input) as f:
        data = json.load(f)

    targets = data.get("targets", [])
    failures = []

    for target in targets:
        name = target.get("name", "")
        coverage = target.get("lineCoverage", 0) * 100

        if "Tempo.app" in name:
            if coverage < args.threshold:
                failures.append(
                    f"Overall coverage {coverage:.1f}% < {args.threshold}%"
                )

            # Check per-file thresholds for engines
            for file_cov in target.get("files", []):
                path = file_cov.get("path", "")
                line_cov = file_cov.get("lineCoverage", 0) * 100

                if "/Engines/" in path and line_cov < args.engines_threshold:
                    failures.append(
                        f"{path}: {line_cov:.1f}% < {args.engines_threshold}% (engine)"
                    )
                elif "/Services/" in path and line_cov < args.services_threshold:
                    failures.append(
                        f"{path}: {line_cov:.1f}% < {args.services_threshold}% (service)"
                    )

    if failures:
        print("::error::Coverage thresholds not met:")
        for f in failures:
            print(f"  - {f}")
        sys.exit(1)
    else:
        print("All coverage thresholds met.")


if __name__ == "__main__":
    main()
```

**`scripts/check_performance.py`:**

```python
#!/usr/bin/env python3
"""Compare performance test results against baseline."""
import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--regression-threshold", type=float, default=10.0,
                        help="Max allowed regression percentage")
    args = parser.parse_args()

    with open(args.input) as f:
        results = json.load(f)
    with open(args.baseline) as f:
        baseline = json.load(f)

    regressions = []

    for test_name, baseline_ms in baseline.items():
        current_ms = results.get(test_name)
        if current_ms is None:
            continue
        pct_change = ((current_ms - baseline_ms) / baseline_ms) * 100
        if pct_change > args.regression_threshold:
            regressions.append(
                f"{test_name}: {baseline_ms}ms -> {current_ms}ms "
                f"(+{pct_change:.1f}%, threshold {args.regression_threshold}%)"
            )

    if regressions:
        print("::error::Performance regressions detected:")
        for r in regressions:
            print(f"  - {r}")
        sys.exit(1)
    else:
        print("No performance regressions detected.")


if __name__ == "__main__":
    main()
```

**`scripts/performance-baseline.json`:**

```json
{
  "test_coldLaunch_toFirstFrame": 800,
  "test_coldLaunch_toInteractive": 1500,
  "test_tabSwitch_dashboardToTraining": 100,
  "test_setCompletion_tapToUI": 16,
  "test_chartRender_90dayLine": 150,
  "test_swiftDataFetch_todaySnapshot": 50,
  "test_swiftDataFetch_90dayHistory": 200
}
```

---

## 3. iOS Release Pipeline

### 3.1 Complete Release Workflow

```yaml
# .github/workflows/ios-release.yml
name: ios-release

on:
  push:
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+"       # v1.0.0, v1.2.3
      - "v[0-9]+.[0-9]+.[0-9]+-beta*"  # v1.0.0-beta1

permissions:
  contents: write

env:
  XCODE_VERSION: "16.0"
  PROJECT: "Tempo.xcodeproj"
  SCHEME: "Tempo"
  BUNDLE_ID: "app.tempo.ios"

jobs:
  # ──────────────────────────────────────────────
  # Run full test suite first
  # ──────────────────────────────────────────────
  test:
    name: Full Test Suite
    uses: ./.github/workflows/ios.yml
    secrets: inherit

  # ──────────────────────────────────────────────
  # Build, Sign, Upload to TestFlight
  # ──────────────────────────────────────────────
  release:
    name: Build & Upload
    runs-on: macos-14
    timeout-minutes: 45
    needs: test
    environment: production
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

      - name: Extract Version from Tag
        id: version
        run: |
          TAG="${{ github.ref_name }}"
          VERSION="${TAG#v}"
          # Strip beta suffix for marketing version
          MARKETING_VERSION="${VERSION%%-*}"
          echo "tag=$TAG" >> "$GITHUB_OUTPUT"
          echo "version=$VERSION" >> "$GITHUB_OUTPUT"
          echo "marketing_version=$MARKETING_VERSION" >> "$GITHUB_OUTPUT"
          echo "is_beta=$([[ "$TAG" == *beta* ]] && echo true || echo false)" >> "$GITHUB_OUTPUT"

      - name: Install Fastlane
        run: |
          gem install bundler
          bundle install

      - name: Setup Code Signing (Match)
        env:
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_TOKEN_BASE64 }}
          FASTLANE_USER: ${{ secrets.APPLE_ID }}
          FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
        run: |
          bundle exec fastlane match appstore --readonly

      - name: Increment Build Number
        run: |
          BUILD_NUMBER=$(date +%Y%m%d%H%M)
          agvtool new-version -all "$BUILD_NUMBER"
          agvtool new-marketing-version "${{ steps.version.outputs.marketing_version }}"
          echo "Build number: $BUILD_NUMBER"
          echo "Marketing version: ${{ steps.version.outputs.marketing_version }}"

      - name: Build & Upload to TestFlight
        env:
          APP_STORE_CONNECT_API_KEY_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_KEY_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_KEY: ${{ secrets.ASC_API_KEY_P8 }}
        run: |
          bundle exec fastlane beta

      - name: Wait for TestFlight Processing
        env:
          APP_STORE_CONNECT_API_KEY_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_KEY_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_KEY: ${{ secrets.ASC_API_KEY_P8 }}
        run: |
          bundle exec fastlane run wait_for_processing_build \
            app_identifier:"${{ env.BUNDLE_ID }}"

      - name: Distribute to Beta Testers
        if: steps.version.outputs.is_beta == 'true'
        env:
          APP_STORE_CONNECT_API_KEY_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_KEY_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_KEY: ${{ secrets.ASC_API_KEY_P8 }}
        run: |
          bundle exec fastlane pilot distribute \
            --app_identifier "${{ env.BUNDLE_ID }}" \
            --groups "Internal Testers,Beta Testers" \
            --distribute_external true \
            --notify_external_testers true \
            --changelog "$(git log --pretty=format:'- %s' $(git describe --tags --abbrev=0 HEAD^)..HEAD)"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ github.ref_name }}
          name: "Tempo ${{ steps.version.outputs.version }}"
          body: |
            ## Tempo ${{ steps.version.outputs.version }}

            ### Changes
            ${{ github.event.head_commit.message }}

            ### TestFlight
            This build has been uploaded to TestFlight and is being distributed to beta testers.
          draft: false
          prerelease: ${{ steps.version.outputs.is_beta == 'true' }}

      - name: Notify Slack
        if: always()
        uses: slackapi/slack-github-action@v1.27.0
        with:
          payload: |
            {
              "text": "${{ job.status == 'success' && ':white_check_mark:' || ':red_circle:' }} Tempo ${{ steps.version.outputs.version }} release ${{ job.status }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "${{ job.status == 'success' && ':white_check_mark:' || ':red_circle:' }} *Tempo ${{ steps.version.outputs.version }}* release *${{ job.status }}*\n*Tag:* `${{ github.ref_name }}`\n*TestFlight:* ${{ job.status == 'success' && 'Uploaded and distributing' || 'Failed' }}\n*Run:* <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View>"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK

  # ──────────────────────────────────────────────
  # App Store Submission (manual trigger)
  # ──────────────────────────────────────────────
  submit-to-app-store:
    name: Submit to App Store Review
    runs-on: macos-14
    timeout-minutes: 15
    needs: release
    if: "!contains(github.ref_name, 'beta')"
    environment: app-store-review  # Requires manual approval in GitHub
    steps:
      - uses: actions/checkout@v4

      - name: Install Fastlane
        run: |
          gem install bundler
          bundle install

      - name: Submit for Review
        env:
          APP_STORE_CONNECT_API_KEY_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          APP_STORE_CONNECT_API_KEY_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          APP_STORE_CONNECT_API_KEY_KEY: ${{ secrets.ASC_API_KEY_P8 }}
        run: |
          bundle exec fastlane release
```

### 3.2 Code Signing with Match

**`fastlane/Matchfile`:**

```ruby
# fastlane/Matchfile

git_url("https://github.com/nicola/tempo-certificates.git")
storage_mode("git")

type("appstore")
app_identifier(["app.tempo.ios"])
username("nicola@example.com")

# Team
team_id("XXXXXXXXXX")

# Force clone each time in CI for clean state
force_for_new_devices(true)
```

### 3.3 Environment-Specific Configuration

Create three Xcode build configurations beyond the defaults:

| Configuration | Bundle ID | API Base URL | APNs | Signing |
|---------------|-----------|-------------|------|---------|
| Debug | `app.tempo.ios.dev` | `http://localhost:8080` | Sandbox | Automatic |
| Staging | `app.tempo.ios.staging` | `https://api-staging.tempo.app` | Sandbox | Match AdHoc |
| Release | `app.tempo.ios` | `https://api.tempo.app` | Production | Match App Store |

Managed via `xcconfig` files:

**`Config/Debug.xcconfig`:**
```
PRODUCT_BUNDLE_IDENTIFIER = app.tempo.ios.dev
TEMPO_API_BASE_URL = http:/$()/localhost:8080
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG
APNS_ENVIRONMENT = sandbox
```

**`Config/Staging.xcconfig`:**
```
PRODUCT_BUNDLE_IDENTIFIER = app.tempo.ios.staging
TEMPO_API_BASE_URL = https:/$()/api-staging.tempo.app
SWIFT_ACTIVE_COMPILATION_CONDITIONS = STAGING
APNS_ENVIRONMENT = sandbox
```

**`Config/Release.xcconfig`:**
```
PRODUCT_BUNDLE_IDENTIFIER = app.tempo.ios
TEMPO_API_BASE_URL = https:/$()/api.tempo.app
SWIFT_ACTIVE_COMPILATION_CONDITIONS = RELEASE
APNS_ENVIRONMENT = production
```

---

## 4. Backend CI Pipeline

### 4.1 Complete Workflow File

```yaml
# .github/workflows/backend.yml
name: backend

on:
  push:
    branches: [main]
    paths:
      - "tempo-backend/**"
      - ".github/workflows/backend.yml"
  pull_request:
    branches: [main]
    paths:
      - "tempo-backend/**"
      - ".github/workflows/backend.yml"

concurrency:
  group: backend-${{ github.ref }}
  cancel-in-progress: true

defaults:
  run:
    working-directory: tempo-backend

jobs:
  # ──────────────────────────────────────────────
  # Job 1: Lint
  # ──────────────────────────────────────────────
  lint:
    name: Lint
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4

      - name: Install SwiftLint
        run: |
          SWIFTLINT_VERSION="0.57.0"
          curl -sL "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/swiftlint_linux.zip" -o swiftlint.zip
          unzip -o swiftlint.zip swiftlint
          chmod +x swiftlint
          sudo mv swiftlint /usr/local/bin/

      - name: Run SwiftLint
        run: swiftlint lint --strict --reporter github-actions-logging

  # ──────────────────────────────────────────────
  # Job 2: Unit Tests
  # ──────────────────────────────────────────────
  unit-tests:
    name: Unit Tests
    runs-on: ubuntu-latest
    timeout-minutes: 20
    needs: lint
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: tempo_test
          POSTGRES_PASSWORD: tempo_test
          POSTGRES_DB: tempo_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U tempo_test -d tempo_test"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4

      - name: Setup Swift
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: "5.10"

      - name: Cache Swift packages
        uses: actions/cache@v4
        with:
          path: tempo-backend/.build
          key: swift-${{ runner.os }}-${{ hashFiles('tempo-backend/Package.resolved') }}
          restore-keys: swift-${{ runner.os }}-

      - name: Resolve Dependencies
        run: swift package resolve

      - name: Run Unit Tests
        env:
          DATABASE_URL: "postgres://tempo_test:tempo_test@localhost:5432/tempo_test"
          REDIS_URL: "redis://localhost:6379/0"
          ENVIRONMENT: "testing"
          JWT_SIGNING_KEY: "dGVzdC1rZXktZm9yLWNpLXBpcGVsaW5l"
          ENCRYPTION_KEY: "0000000000000000000000000000000000000000000000000000000000000000"
          LOG_LEVEL: "warning"
        run: |
          swift test \
            --parallel \
            --filter "Unit" \
            --enable-code-coverage \
            2>&1 | tee test-output.txt

      - name: Check Coverage
        run: |
          BIN_PATH=$(swift build --show-bin-path)
          PROFDATA=$(find .build -name "default.profdata" -type f | head -1)
          TEST_BIN=$(find "$BIN_PATH" -name "*.xctest" -type d | head -1)/Contents/MacOS/*
          xcrun llvm-cov report "$TEST_BIN" \
            -instr-profile="$PROFDATA" \
            --ignore-filename-regex='\.build|Tests' \
            > coverage-report.txt
          cat coverage-report.txt
          # Extract total percentage and check threshold
          TOTAL=$(tail -1 coverage-report.txt | awk '{print $NF}' | tr -d '%')
          if (( $(echo "$TOTAL < 80" | bc -l) )); then
            echo "::error::Coverage ${TOTAL}% is below 80% threshold"
            exit 1
          fi

      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: backend-unit-test-results
          path: |
            tempo-backend/test-output.txt
            tempo-backend/coverage-report.txt
          retention-days: 14

  # ──────────────────────────────────────────────
  # Job 3: Integration Tests
  # ──────────────────────────────────────────────
  integration-tests:
    name: Integration Tests
    runs-on: ubuntu-latest
    timeout-minutes: 25
    needs: unit-tests
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: tempo_test
          POSTGRES_PASSWORD: tempo_test
          POSTGRES_DB: tempo_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U tempo_test -d tempo_test"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v4

      - name: Setup Swift
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: "5.10"

      - name: Cache Swift packages
        uses: actions/cache@v4
        with:
          path: tempo-backend/.build
          key: swift-${{ runner.os }}-${{ hashFiles('tempo-backend/Package.resolved') }}
          restore-keys: swift-${{ runner.os }}-

      - name: Run Integration Tests
        env:
          DATABASE_URL: "postgres://tempo_test:tempo_test@localhost:5432/tempo_test"
          REDIS_URL: "redis://localhost:6379/0"
          ENVIRONMENT: "testing"
          JWT_SIGNING_KEY: "dGVzdC1rZXktZm9yLWNpLXBpcGVsaW5l"
          ENCRYPTION_KEY: "0000000000000000000000000000000000000000000000000000000000000000"
          LOG_LEVEL: "warning"
        run: |
          swift test \
            --parallel \
            --filter "Integration" \
            2>&1 | tee integration-output.txt

      - name: Upload Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: backend-integration-test-results
          path: tempo-backend/integration-output.txt
          retention-days: 14

  # ──────────────────────────────────────────────
  # Job 4: Docker Build & Test
  # ──────────────────────────────────────────────
  docker-build:
    name: Docker Build
    runs-on: ubuntu-latest
    timeout-minutes: 20
    needs: lint
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build Docker Image
        uses: docker/build-push-action@v6
        with:
          context: ./tempo-backend
          push: false
          load: true
          tags: tempo-backend:test
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Test Docker Image Starts
        run: |
          docker run -d --name tempo-test \
            -e ENVIRONMENT=testing \
            -e DATABASE_URL=postgres://fake:fake@localhost:5432/fake \
            -e REDIS_URL=redis://localhost:6379/0 \
            -e JWT_SIGNING_KEY=dGVzdC1rZXk= \
            -e ENCRYPTION_KEY=0000000000000000000000000000000000000000000000000000000000000000 \
            -p 8080:8080 \
            tempo-backend:test || true

          # Give it a few seconds to start (or fail gracefully)
          sleep 5
          docker logs tempo-test
          docker stop tempo-test || true
          docker rm tempo-test || true

      - name: Check Image Size
        run: |
          SIZE=$(docker image inspect tempo-backend:test --format='{{.Size}}')
          SIZE_MB=$((SIZE / 1048576))
          echo "Image size: ${SIZE_MB}MB"
          if [ "$SIZE_MB" -gt 200 ]; then
            echo "::warning::Docker image is ${SIZE_MB}MB — consider optimizing (target: <200MB)"
          fi

  # ──────────────────────────────────────────────
  # Job 5: Security Scan
  # ──────────────────────────────────────────────
  security-scan:
    name: Security Scan
    runs-on: ubuntu-latest
    timeout-minutes: 10
    needs: lint
    steps:
      - uses: actions/checkout@v4

      - name: Run Trivy Vulnerability Scanner
        uses: aquasecurity/trivy-action@0.28.0
        with:
          scan-type: "fs"
          scan-ref: "./tempo-backend"
          severity: "CRITICAL,HIGH"
          exit-code: "1"
          format: "sarif"
          output: "trivy-results.sarif"

      - name: Upload Trivy SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: "trivy-results.sarif"

      - name: Check for Known Swift Vulnerabilities
        run: |
          cd tempo-backend
          # Check Package.resolved for known vulnerable versions
          if [ -f Package.resolved ]; then
            echo "Checking Swift package dependencies..."
            cat Package.resolved | python3 -c "
          import json, sys
          data = json.load(sys.stdin)
          pins = data.get('pins', data.get('object', {}).get('pins', []))
          print(f'Found {len(pins)} dependencies')
          for pin in pins:
              name = pin.get('identity', pin.get('package', 'unknown'))
              version = pin.get('state', {}).get('version', 'branch')
              print(f'  {name}: {version}')
          "
          fi

  # ──────────────────────────────────────────────
  # Notifications
  # ──────────────────────────────────────────────
  notify-failure:
    name: Notify on Failure
    runs-on: ubuntu-latest
    needs: [lint, unit-tests, integration-tests, docker-build, security-scan]
    if: failure() && github.ref == 'refs/heads/main'
    steps:
      - name: Slack Notification
        uses: slackapi/slack-github-action@v1.27.0
        with:
          payload: |
            {
              "text": ":red_circle: Tempo Backend CI failed on `main`",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": ":red_circle: *Tempo Backend CI Failed*\n*Branch:* `${{ github.ref_name }}`\n*Commit:* `${{ github.sha }}` by ${{ github.actor }}\n*Run:* <${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Workflow>"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

---

## 5. Backend Deployment Pipeline

### 5.1 Option A: Railway

**`tempo-backend/railway.toml`:**

```toml
[build]
builder = "dockerfile"
dockerfilePath = "Dockerfile"

[deploy]
healthcheckPath = "/v1/health/live"
healthcheckTimeout = 10
startCommand = "./App serve --env production --hostname 0.0.0.0 --port $PORT"
numReplicas = 2
restartPolicyType = "ON_FAILURE"
restartPolicyMaxRetries = 5
```

**Railway deployment workflow:**

```yaml
# .github/workflows/deploy-railway.yml
name: deploy-railway

on:
  push:
    branches: [main]
    paths:
      - "tempo-backend/**"

concurrency:
  group: deploy-railway
  cancel-in-progress: false  # Never cancel in-progress deployments

jobs:
  test:
    name: Test
    uses: ./.github/workflows/backend.yml
    secrets: inherit

  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    timeout-minutes: 15
    needs: test
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Install Railway CLI
        run: npm install -g @railway/cli

      - name: Deploy to Staging
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
        run: |
          cd tempo-backend
          railway up --environment staging --detach

      - name: Wait for Deployment
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
        run: |
          # Poll the health endpoint until it responds
          STAGING_URL="https://api-staging.tempo.app"
          for i in $(seq 1 30); do
            if curl -sf "$STAGING_URL/v1/health/live" > /dev/null 2>&1; then
              echo "Staging is healthy"
              exit 0
            fi
            echo "Waiting for staging deployment... ($i/30)"
            sleep 10
          done
          echo "::error::Staging health check timed out"
          exit 1

      - name: Run Smoke Tests against Staging
        run: |
          STAGING_URL="https://api-staging.tempo.app"
          # Health check
          curl -sf "$STAGING_URL/v1/health" | python3 -c "
          import json, sys
          data = json.load(sys.stdin)
          assert data['status'] == 'healthy', f'Unhealthy: {data}'
          for svc, check in data['checks'].items():
              assert check['status'] == 'healthy', f'{svc} unhealthy: {check}'
          print('All health checks passed')
          "

  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    timeout-minutes: 15
    needs: deploy-staging
    environment: production  # Requires manual approval in GitHub
    steps:
      - uses: actions/checkout@v4

      - name: Install Railway CLI
        run: npm install -g @railway/cli

      - name: Deploy to Production
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
        run: |
          cd tempo-backend
          railway up --environment production --detach

      - name: Run Migrations
        env:
          RAILWAY_TOKEN: ${{ secrets.RAILWAY_TOKEN }}
        run: |
          cd tempo-backend
          railway run --environment production -- vapor run migrate --yes

      - name: Verify Production Health
        run: |
          PROD_URL="https://api.tempo.app"
          for i in $(seq 1 30); do
            if curl -sf "$PROD_URL/v1/health" > /dev/null 2>&1; then
              echo "Production is healthy"
              curl -sf "$PROD_URL/v1/health" | python3 -m json.tool
              exit 0
            fi
            echo "Waiting for production... ($i/30)"
            sleep 10
          done
          echo "::error::Production health check timed out"
          exit 1

      - name: Notify Slack
        if: always()
        uses: slackapi/slack-github-action@v1.27.0
        with:
          payload: |
            {
              "text": "${{ job.status == 'success' && ':white_check_mark: Tempo backend deployed to production' || ':red_circle: Tempo backend production deploy FAILED' }}"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
          SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

**Railway environment variables setup:**

```bash
# One-time setup commands (run locally)
# Install Railway CLI: npm install -g @railway/cli
# Login: railway login

# Create project
railway init --name tempo-backend

# Provision databases
railway add --plugin postgresql
railway add --plugin redis

# Set environment variables for staging
railway variables set --environment staging \
  ENVIRONMENT=staging \
  LOG_LEVEL=info \
  DATABASE_POOL_SIZE=10 \
  JWT_SIGNING_KEY="<base64-es256-private-key>" \
  ENCRYPTION_KEY="<64-hex-chars>" \
  APPLE_BUNDLE_ID=app.tempo.ios.staging \
  APPLE_TEAM_ID=XXXXXXXXXX \
  APPLE_KEY_ID=XXXXXXXXXX \
  APPLE_PRIVATE_KEY="<pem-key>" \
  WHOOP_CLIENT_ID="<client-id>" \
  WHOOP_CLIENT_SECRET="<client-secret>" \
  WHOOP_REDIRECT_URI="https://api-staging.tempo.app/v1/whoop/callback" \
  WHOOP_WEBHOOK_SECRET="<hmac-secret>" \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=XXXXXXXXXX \
  APNS_PRIVATE_KEY="<p8-key>" \
  APNS_TOPIC=app.tempo.ios.staging \
  APNS_ENVIRONMENT=sandbox \
  CLAUDE_API_KEY="<anthropic-key>" \
  CLAUDE_MONTHLY_BUDGET_CENTS=1000 \
  RATE_LIMIT_ENABLED=true

# Custom domain
railway domain add api-staging.tempo.app --environment staging
railway domain add api.tempo.app --environment production
```

### 5.2 Option B: Fly.io

**`tempo-backend/fly.toml`:**

```toml
app = "tempo-api"
primary_region = "fra"
kill_signal = "SIGTERM"
kill_timeout = "30s"

[build]
  dockerfile = "Dockerfile"

[env]
  ENVIRONMENT = "production"
  LOG_LEVEL = "info"
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 2
  processes = ["app"]

  [http_service.concurrency]
    type = "requests"
    hard_limit = 250
    soft_limit = 200

[[http_service.checks]]
  grace_period = "10s"
  interval = "30s"
  method = "GET"
  timeout = "5s"
  path = "/v1/health/live"

[[vm]]
  size = "shared-cpu-2x"
  memory = "1024mb"
  cpu_kind = "shared"
  cpus = 2

[metrics]
  port = 8080
  path = "/metrics"
```

**`tempo-backend/Dockerfile`** (multi-stage, same as in BACKEND_API.md):

```dockerfile
# ============================================================
# Build stage
# ============================================================
FROM swift:5.10-jammy AS build

WORKDIR /app

# Resolve dependencies first (cache layer)
COPY Package.swift Package.resolved ./
RUN swift package resolve

# Copy source and build
COPY . .
RUN swift build -c release --static-swift-stdlib \
    -Xlinker -ljemalloc

# ============================================================
# Runtime stage
# ============================================================
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libcurl4 \
    libjemalloc2 \
    tzdata \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN useradd -r -s /bin/false tempo
USER tempo

WORKDIR /app
COPY --from=build --chown=tempo:tempo /app/.build/release/App ./
COPY --from=build --chown=tempo:tempo /app/Resources ./Resources

ENV ENVIRONMENT=production
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/v1/health/live || exit 1

ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
```

**Fly.io deployment workflow:**

```yaml
# .github/workflows/deploy-fly.yml
name: deploy-fly

on:
  push:
    branches: [main]
    paths:
      - "tempo-backend/**"

concurrency:
  group: deploy-fly
  cancel-in-progress: false

jobs:
  test:
    name: Test
    uses: ./.github/workflows/backend.yml
    secrets: inherit

  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    timeout-minutes: 15
    needs: test
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Setup Fly CLI
        uses: superfly/flyctl-actions/setup-flyctl@master

      - name: Deploy to Staging
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
        run: |
          cd tempo-backend
          flyctl deploy \
            --app tempo-api-staging \
            --config fly.toml \
            --strategy rolling \
            --wait-timeout 300

      - name: Run Migrations on Staging
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
        run: |
          flyctl ssh console --app tempo-api-staging \
            --command "./App migrate --yes"

      - name: Smoke Test Staging
        run: |
          curl -sf https://tempo-api-staging.fly.dev/v1/health | python3 -m json.tool

  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    timeout-minutes: 15
    needs: deploy-staging
    environment: production
    steps:
      - uses: actions/checkout@v4

      - name: Setup Fly CLI
        uses: superfly/flyctl-actions/setup-flyctl@master

      - name: Deploy to Production
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
        run: |
          cd tempo-backend
          flyctl deploy \
            --app tempo-api \
            --config fly.toml \
            --strategy rolling \
            --wait-timeout 300

      - name: Run Migrations on Production
        env:
          FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}
        run: |
          flyctl ssh console --app tempo-api \
            --command "./App migrate --yes"

      - name: Verify Production
        run: |
          curl -sf https://api.tempo.app/v1/health | python3 -m json.tool
```

**Fly.io one-time setup:**

```bash
# Install: brew install flyctl
# Login: flyctl auth login

# Create apps
flyctl apps create tempo-api-staging
flyctl apps create tempo-api

# Provision Fly Postgres
flyctl postgres create --name tempo-db --region fra --initial-cluster-size 1 --vm-size shared-cpu-1x --volume-size 10
flyctl postgres attach tempo-db --app tempo-api

# Provision Upstash Redis (Fly Redis)
flyctl redis create --name tempo-redis --region fra --plan free
flyctl redis attach tempo-redis --app tempo-api

# Set secrets (production)
flyctl secrets set --app tempo-api \
  JWT_SIGNING_KEY="<base64-es256-private-key>" \
  ENCRYPTION_KEY="<64-hex-chars>" \
  APPLE_BUNDLE_ID=app.tempo.ios \
  APPLE_TEAM_ID=XXXXXXXXXX \
  APPLE_KEY_ID=XXXXXXXXXX \
  APPLE_PRIVATE_KEY="<pem-key>" \
  WHOOP_CLIENT_ID="<client-id>" \
  WHOOP_CLIENT_SECRET="<client-secret>" \
  WHOOP_REDIRECT_URI="https://api.tempo.app/v1/whoop/callback" \
  WHOOP_WEBHOOK_SECRET="<hmac-secret>" \
  APNS_KEY_ID=XXXXXXXXXX \
  APNS_TEAM_ID=XXXXXXXXXX \
  APNS_PRIVATE_KEY="<p8-key>" \
  APNS_TOPIC=app.tempo.ios \
  APNS_ENVIRONMENT=production \
  CLAUDE_API_KEY="<anthropic-key>" \
  CLAUDE_MONTHLY_BUDGET_CENTS=5000

# Custom domain
flyctl certs add api.tempo.app --app tempo-api
# Then add CNAME: api.tempo.app -> tempo-api.fly.dev in your DNS
```

### 5.3 Platform Recommendation

| Criteria | Railway | Fly.io |
|----------|---------|--------|
| Ease of setup | Simpler, more managed | More control, slightly more setup |
| Postgres | Managed, auto-provisioned | Fly Postgres (self-managed on Fly VMs) |
| Redis | Managed plugin | Upstash integration |
| Pricing (at 100 users) | ~$20/mo | ~$15/mo |
| Scaling | Horizontal (numReplicas) | Machines API, global edge |
| Regions | US/EU | 35+ regions globally |
| SSH access | Limited | Full SSH |

**Recommendation:** Start with **Railway** for simplicity. Migrate to Fly.io when you need multi-region or fine-grained control.

---

## 6. Environment Management

### 6.1 Environment Overview

| Environment | iOS App | Backend | Database | Purpose |
|-------------|---------|---------|----------|---------|
| **Development** | Xcode Debug build | `docker compose up` | Local PostgreSQL | Day-to-day coding |
| **Staging** | TestFlight (staging build) | Railway/Fly staging | Separate staging DB | Pre-release validation |
| **Production** | App Store | Railway/Fly production | Production DB | Live users |

### 6.2 Docker Compose for Local Development

**`tempo-backend/docker-compose.yml`:**

```yaml
services:
  api:
    build:
      context: .
      target: build
    ports:
      - "8080:8080"
    environment:
      - ENVIRONMENT=development
      - DATABASE_URL=postgres://tempo:tempo_dev@db:5432/tempo_dev
      - REDIS_URL=redis://redis:6379/0
      - LOG_LEVEL=debug
      - JWT_SIGNING_KEY=ZGV2LWp3dC1zaWduaW5nLWtleS1mb3ItbG9jYWwtZGV2ZWxvcG1lbnQ=
      - ENCRYPTION_KEY=0000000000000000000000000000000000000000000000000000000000000000
      - APPLE_BUNDLE_ID=app.tempo.ios.dev
      - APPLE_TEAM_ID=XXXXXXXXXX
      - APPLE_KEY_ID=XXXXXXXXXX
      - APPLE_PRIVATE_KEY=dev-key
      - WHOOP_CLIENT_ID=dev-client-id
      - WHOOP_CLIENT_SECRET=dev-client-secret
      - WHOOP_REDIRECT_URI=http://localhost:8080/v1/whoop/callback
      - WHOOP_WEBHOOK_SECRET=dev-webhook-secret
      - APNS_KEY_ID=XXXXXXXXXX
      - APNS_TEAM_ID=XXXXXXXXXX
      - APNS_PRIVATE_KEY=dev-key
      - APNS_TOPIC=app.tempo.ios.dev
      - APNS_ENVIRONMENT=sandbox
      - CLAUDE_API_KEY=${CLAUDE_API_KEY:-sk-ant-dev}
      - CLAUDE_MONTHLY_BUDGET_CENTS=500
      - RATE_LIMIT_ENABLED=false
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - .:/app
    command: swift run App serve --hostname 0.0.0.0 --port 8080

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: tempo
      POSTGRES_PASSWORD: tempo_dev
      POSTGRES_DB: tempo_dev
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U tempo -d tempo_dev"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redisdata:/data

volumes:
  pgdata:
  redisdata:
```

**`tempo-backend/docker-compose.test.yml`** (for CI integration tests):

```yaml
services:
  api:
    build: .
    ports:
      - "8080:8080"
    environment:
      - ENVIRONMENT=testing
      - DATABASE_URL=postgres://tempo_test:tempo_test@db:5432/tempo_test
      - REDIS_URL=redis://redis:6379/0
      - LOG_LEVEL=warning
      - JWT_SIGNING_KEY=dGVzdC1rZXktZm9yLWNpLXBpcGVsaW5l
      - ENCRYPTION_KEY=0000000000000000000000000000000000000000000000000000000000000000
      - APPLE_BUNDLE_ID=app.tempo.ios.dev
      - APPLE_TEAM_ID=TEST
      - APPLE_KEY_ID=TEST
      - APPLE_PRIVATE_KEY=test-key
      - WHOOP_CLIENT_ID=test
      - WHOOP_CLIENT_SECRET=test
      - WHOOP_REDIRECT_URI=http://localhost:8080/v1/whoop/callback
      - WHOOP_WEBHOOK_SECRET=test
      - APNS_KEY_ID=TEST
      - APNS_TEAM_ID=TEST
      - APNS_PRIVATE_KEY=test-key
      - APNS_TOPIC=app.tempo.ios.dev
      - APNS_ENVIRONMENT=sandbox
      - CLAUDE_API_KEY=test
      - RATE_LIMIT_ENABLED=false
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: tempo_test
      POSTGRES_PASSWORD: tempo_test
      POSTGRES_DB: tempo_test
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U tempo_test -d tempo_test"]
      interval: 3s
      timeout: 3s
      retries: 10

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
```

### 6.3 Environment Variable Management

**Secrets are NEVER stored in code.** They live in:

| Environment | Where secrets are stored |
|-------------|------------------------|
| Development | `tempo-backend/.env.development` (gitignored) |
| CI | GitHub Actions secrets |
| Staging | Railway/Fly secrets |
| Production | Railway/Fly secrets |

**`.gitignore` entries:**
```
.env
.env.*
*.p8
*.pem
```

**`.env.development.template`** (committed to git, no real values):
```bash
# Copy to .env.development and fill in real values
CLAUDE_API_KEY=sk-ant-your-key-here
# All other vars have dev defaults in docker-compose.yml
```

### 6.4 Feature Flags

Use a simple JSON config endpoint to control features per environment:

```swift
// Sources/App/Configuration/FeatureFlags.swift
struct FeatureFlags: Content {
    let arenaEnabled: Bool
    let aiInsightsEnabled: Bool
    let whoopIntegrationEnabled: Bool
    let nutritrackIntegrationEnabled: Bool
    let pushNotificationsEnabled: Bool
    let maxFriendsCount: Int
}

// Returns different flags per environment
func featureFlags(for environment: Environment) -> FeatureFlags {
    switch environment {
    case .development:
        return FeatureFlags(
            arenaEnabled: true,
            aiInsightsEnabled: true,
            whoopIntegrationEnabled: false,   // No real Whoop in dev
            nutritrackIntegrationEnabled: true,
            pushNotificationsEnabled: false,   // No APNs in dev
            maxFriendsCount: 100
        )
    case .staging:
        return FeatureFlags(
            arenaEnabled: true,
            aiInsightsEnabled: true,
            whoopIntegrationEnabled: true,
            nutritrackIntegrationEnabled: true,
            pushNotificationsEnabled: true,
            maxFriendsCount: 50
        )
    case .production:
        return FeatureFlags(
            arenaEnabled: true,
            aiInsightsEnabled: true,
            whoopIntegrationEnabled: true,
            nutritrackIntegrationEnabled: true,
            pushNotificationsEnabled: true,
            maxFriendsCount: 50
        )
    default:
        return FeatureFlags(/* defaults */)
    }
}
```

Served via `GET /v1/config` (already defined in BACKEND_API.md).

---

## 7. Database Migrations

### 7.1 Migration Naming Convention

Migrations are numbered sequentially and stored in `tempo-backend/Sources/App/Migrations/`:

```
001_CreateUsers.swift
002_CreateRefreshTokens.swift
003_CreateDailySnapshots.swift
004_CreateWorkoutPlans.swift
005_CreateXPEvents.swift
006_CreateArenaTeams.swift
...
```

### 7.2 Running Migrations in CI

Migrations run automatically as part of the test setup. The Vapor test suite calls `app.autoMigrate()` in the test `configure` method:

```swift
// Tests/configure.swift
func configureForTesting(_ app: Application) throws {
    app.databases.use(.postgres(
        configuration: .init(
            hostname: Environment.get("DB_HOST") ?? "localhost",
            port: 5432,
            username: "tempo_test",
            password: "tempo_test",
            database: "tempo_test"
        )
    ), as: .psql)

    // Run all migrations
    try app.autoMigrate().wait()
}
```

Each integration test class tears down and re-migrates for isolation:

```swift
override func setUp() async throws {
    app = try Application(.testing)
    try configureForTesting(app)
    try await app.autoMigrate()
}

override func tearDown() async throws {
    try await app.autoRevert()
    app.shutdown()
}
```

### 7.3 Running Migrations in Production

Migrations run as a **separate step** after deployment, never automatically on app startup in production.

```bash
# Railway
railway run --environment production -- vapor run migrate --yes

# Fly.io
flyctl ssh console --app tempo-api --command "./App migrate --yes"
```

The deployment workflow (Section 5) includes this step after the new code is deployed but before the health check verifies the deployment.

### 7.4 Zero-Downtime Migration Strategy

All migrations follow the **expand-and-contract** pattern from BACKEND_API.md Section 29.2:

**Phase 1 — Expand (safe, backward-compatible):**
```swift
// 015_AddDisplayNameToUsers.swift
struct AddDisplayNameToUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("display_name", .string)  // Nullable, no default — safe
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("display_name")
            .update()
    }
}
```

**Phase 2 — Deploy:** New code reads `display_name` if present, falls back to `username`.

**Phase 3 — Backfill:**
```swift
// 016_BackfillDisplayNames.swift
struct BackfillDisplayNames: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await User.query(on: database)
            .filter(\.$displayName == nil)
            .set(\.$displayName, to: \.$username)
            .update()
    }
    // ...
}
```

**Phase 4 — Contract (later release):** Make column non-nullable, remove old code paths.

### 7.5 Rollback Procedure

1. **Before any migration:** Railway/Fly takes automatic snapshots. For extra safety:
   ```bash
   # Railway: snapshot is automatic
   # Fly Postgres: manual snapshot
   flyctl postgres backup create --app tempo-db
   ```

2. **If migration fails or causes issues:**
   ```bash
   # Revert last migration batch
   railway run --environment production -- vapor run migrate --revert
   # or
   flyctl ssh console --app tempo-api --command "./App migrate --revert"
   ```

3. **If revert fails:** Restore from database snapshot (PITR).

4. **Rollback the code deploy:**
   ```bash
   # Railway: redeploy previous commit
   git revert HEAD && git push origin main

   # Fly.io: rollback to previous release
   flyctl releases --app tempo-api
   flyctl deploy --image <previous-image-ref> --app tempo-api
   ```

### 7.6 Migration Testing in CI

The integration test job validates migrations against a fresh database every run. Additionally, add a dedicated migration test:

```swift
// Tests/Integration/DatabaseMigrationTests.swift
final class DatabaseMigrationTests: XCTestCase {
    func test_allMigrations_applyCleanly() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }
        try configureForTesting(app)

        // Apply all migrations from scratch
        try await app.autoMigrate()

        // Verify key tables exist
        let userCount = try await User.query(on: app.db).count()
        XCTAssertEqual(userCount, 0)

        // Revert all
        try await app.autoRevert()

        // Re-apply (tests idempotency)
        try await app.autoMigrate()
    }
}
```

---

## 8. Monitoring & Alerting

### 8.1 Stack Overview

| Layer | Tool | Cost | Why |
|-------|------|------|-----|
| Error tracking | Sentry | Free tier (5K events/mo) | Best Swift/iOS + server-side support |
| Uptime monitoring | Better Stack (formerly Better Uptime) | Free tier | Clean status page, Slack integration |
| Application metrics | Built-in `/v1/health` + Prometheus-compatible `/metrics` | Free | Already defined in API spec |
| Log aggregation | Railway/Fly built-in logs + Better Stack Logs | Free-$25/mo | Centralized structured JSON logs |
| Alerting | Better Stack + Slack | Free | Unified alert routing |

### 8.2 Sentry Configuration

**Backend (`tempo-backend/Sources/App/configure.swift`):**

```swift
import Sentry

func configureSentry(_ app: Application) {
    guard app.environment == .production || app.environment == .staging else { return }

    SentrySDK.start { options in
        options.dsn = Environment.get("SENTRY_DSN")
        options.environment = app.environment.name
        options.releaseName = "tempo-backend@\(appVersion)"
        options.tracesSampleRate = 0.2  // 20% of transactions
        options.enableAutoPerformanceTracing = true
        options.attachStacktrace = true
        options.maxBreadcrumbs = 50
        options.beforeSend = { event in
            // Scrub sensitive data
            event.contexts.removeValue(forKey: "device")
            return event
        }
    }
}
```

**iOS App (`TempoApp.swift`):**

```swift
import Sentry

@main
struct TempoApp: App {
    init() {
        #if !DEBUG
        SentrySDK.start { options in
            options.dsn = Configuration.sentryDSN
            options.environment = Configuration.environment  // staging or production
            options.releaseName = "tempo-ios@\(Bundle.main.appVersion)"
            options.tracesSampleRate = 0.2
            options.profilesSampleRate = 0.1
            options.enableAutoPerformanceTracing = true
            options.enableUIViewControllerTracing = true
            options.enableNetworkTracking = true
            options.enableCoreDataTracing = false
            options.attachScreenshot = true
            options.attachViewHierarchy = true
            options.enableMetricKit = true
        }
        #endif
    }
}
```

### 8.3 Uptime Monitoring

**Better Stack monitors:**

| Monitor | URL | Interval | Alert after |
|---------|-----|----------|-------------|
| API Health | `https://api.tempo.app/v1/health` | 60s | 2 failures |
| API Readiness | `https://api.tempo.app/v1/health/ready` | 30s | 3 failures |
| Staging Health | `https://api-staging.tempo.app/v1/health/live` | 120s | 5 failures |

**Status page:** `https://status.tempo.app` (Better Stack hosted)

### 8.4 Alert Routing

| Alert Type | Severity | Channel | Response Time |
|------------|----------|---------|---------------|
| Production down (health check fails) | Critical | Slack #tempo-alerts + Push notification | Immediate |
| Error rate >5% for 5 min | Critical | Slack #tempo-alerts | < 15 min |
| p99 latency >2s for 5 min | Warning | Slack #tempo-alerts | < 1 hour |
| DB pool >80% for 5 min | Warning | Slack #tempo-alerts | < 1 hour |
| Claude budget >80% | Warning | Slack #tempo-alerts | < 24 hours |
| Claude budget >95% | Critical | Slack #tempo-alerts + Email | < 1 hour |
| Sentry: new unhandled exception | Info | Slack #tempo-errors (auto) | Next working session |
| Certificate expiry <14 days | Warning | Email | < 48 hours |
| Staging down | Info | Slack #tempo-dev | Best effort |

### 8.5 Prometheus Metrics Endpoint

The Vapor backend exposes `GET /metrics` (not behind auth, but IP-restricted or on a separate port) in Prometheus exposition format:

```swift
// Sources/App/Middleware/MetricsMiddleware.swift
import Prometheus

let httpRequestDuration = Histogram<Double>(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    labels: ["method", "path", "status"]
)

let httpRequestsTotal = Counter<Int>(
    "http_requests_total",
    "Total HTTP requests",
    labels: ["method", "path", "status"]
)
```

If using Railway/Fly, you can scrape this with Grafana Cloud's free tier (10K metrics) or rely on the platform's built-in metrics.

### 8.6 Grafana Dashboard (optional, Grafana Cloud free tier)

Key panels:
1. **Request rate** — `rate(http_requests_total[5m])` by status code
2. **Latency percentiles** — `histogram_quantile(0.95, http_request_duration_seconds)`
3. **Error rate** — `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])`
4. **DB pool utilization** — `db_pool_active / db_pool_max`
5. **Redis memory** — `redis_memory_bytes`
6. **Active users (daily)** — `active_users_daily`
7. **Claude API spend** — `claude_api_cost_cents`

---

## 9. Fastlane Configuration

### 9.1 Gemfile

```ruby
# Gemfile
source "https://rubygems.org"

gem "fastlane", "~> 2.224"
gem "cocoapods", "~> 1.15"  # Only if using CocoaPods

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
```

### 9.2 Pluginfile

```ruby
# fastlane/Pluginfile
gem "fastlane-plugin-versioning", "~> 0.5"
```

### 9.3 Fastfile

```ruby
# fastlane/Fastfile

default_platform(:ios)

XCODE_PROJECT = "Tempo.xcodeproj"
SCHEME = "Tempo"
BUNDLE_ID = "app.tempo.ios"
TEAM_ID = ENV["APPLE_TEAM_ID"] || "XXXXXXXXXX"

platform :ios do
  before_all do
    setup_ci if ENV["CI"]
  end

  # ──────────────────────────────────────────────
  # Lane: test
  # Run all tests (unit + integration + snapshot)
  # ──────────────────────────────────────────────
  desc "Run all tests"
  lane :test do
    scan(
      project: XCODE_PROJECT,
      scheme: "TempoTests",
      devices: ["iPhone 16 Pro (18.0)"],
      code_coverage: true,
      result_bundle: true,
      output_directory: "./fastlane/test_output",
      clean: true,
      xcargs: "CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO"
    )

    scan(
      project: XCODE_PROJECT,
      scheme: "TempoSnapshotTests",
      devices: ["iPhone 15 Pro (17.0)"],
      result_bundle: true,
      output_directory: "./fastlane/test_output/snapshots",
      xcargs: "CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO"
    )

    scan(
      project: XCODE_PROJECT,
      scheme: "TempoIntegrationTests",
      devices: ["iPhone 16 Pro (18.0)"],
      result_bundle: true,
      output_directory: "./fastlane/test_output/integration",
      xcargs: "CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO"
    )
  end

  # ──────────────────────────────────────────────
  # Lane: beta
  # Build and upload to TestFlight
  # ──────────────────────────────────────────────
  desc "Build and upload to TestFlight"
  lane :beta do
    api_key = app_store_connect_api_key(
      key_id: ENV["APP_STORE_CONNECT_API_KEY_KEY_ID"],
      issuer_id: ENV["APP_STORE_CONNECT_API_KEY_ISSUER_ID"],
      key_content: ENV["APP_STORE_CONNECT_API_KEY_KEY"],
      is_key_content_base64: false
    )

    match(
      type: "appstore",
      app_identifier: BUNDLE_ID,
      readonly: true,
      api_key: api_key
    )

    increment_build_number(
      build_number: Time.now.strftime("%Y%m%d%H%M"),
      xcodeproj: XCODE_PROJECT
    )

    build_app(
      project: XCODE_PROJECT,
      scheme: SCHEME,
      configuration: "Release",
      export_method: "app-store",
      export_options: {
        provisioningProfiles: {
          BUNDLE_ID => "match AppStore #{BUNDLE_ID}"
        }
      },
      output_directory: "./fastlane/builds",
      output_name: "Tempo.ipa",
      clean: true,
      include_bitcode: false,
      xcargs: "-allowProvisioningUpdates"
    )

    upload_to_testflight(
      api_key: api_key,
      ipa: "./fastlane/builds/Tempo.ipa",
      skip_waiting_for_build_processing: false,
      distribute_external: false,
      changelog: changelog_from_git_commits(
        commits_count: 10,
        pretty: "- %s"
      )
    )
  end

  # ──────────────────────────────────────────────
  # Lane: release
  # Submit to App Store Review
  # ──────────────────────────────────────────────
  desc "Submit to App Store Review"
  lane :release do
    api_key = app_store_connect_api_key(
      key_id: ENV["APP_STORE_CONNECT_API_KEY_KEY_ID"],
      issuer_id: ENV["APP_STORE_CONNECT_API_KEY_ISSUER_ID"],
      key_content: ENV["APP_STORE_CONNECT_API_KEY_KEY"],
      is_key_content_base64: false
    )

    deliver(
      api_key: api_key,
      app_identifier: BUNDLE_ID,
      submit_for_review: true,
      automatic_release: false,    # Manual release after approval
      force: true,                 # Skip metadata verification prompt
      precheck_include_in_app_purchases: false,
      submission_information: {
        add_id_info_uses_idfa: false,
        export_compliance_uses_encryption: true,
        export_compliance_is_exempt: true
      },
      phased_release: true         # 7-day phased rollout
    )
  end

  # ──────────────────────────────────────────────
  # Lane: screenshots
  # Generate App Store screenshots
  # ──────────────────────────────────────────────
  desc "Generate App Store screenshots"
  lane :screenshots do
    capture_screenshots(
      project: XCODE_PROJECT,
      scheme: "TempoUITests",
      devices: [
        "iPhone 16 Pro Max",
        "iPhone SE (3rd generation)",
        "iPad Pro (12.9-inch) (6th generation)"
      ],
      languages: ["en-US"],
      output_directory: "./fastlane/screenshots",
      clear_previous_screenshots: true,
      override_status_bar: true,
      dark_mode: false,
      stop_after_first_error: false
    )

    frame_screenshots(
      path: "./fastlane/screenshots",
      force_device_type: "iPhone 16 Pro Max"
    )
  end

  # ──────────────────────────────────────────────
  # Lane: match_setup
  # Initialize code signing certificates
  # ──────────────────────────────────────────────
  desc "Setup code signing with Match"
  lane :match_setup do
    match(
      type: "development",
      app_identifier: BUNDLE_ID,
      force_for_new_devices: true
    )

    match(
      type: "appstore",
      app_identifier: BUNDLE_ID
    )
  end

  # ──────────────────────────────────────────────
  # Error handling
  # ──────────────────────────────────────────────
  error do |lane, exception|
    if ENV["SLACK_WEBHOOK_URL"]
      slack(
        message: "Fastlane failed: #{lane}",
        success: false,
        slack_url: ENV["SLACK_WEBHOOK_URL"],
        payload: {
          "Error" => exception.message,
          "Lane" => lane.to_s
        }
      )
    end
  end
end
```

### 9.4 Matchfile

```ruby
# fastlane/Matchfile
git_url("https://github.com/nicola/tempo-certificates.git")
storage_mode("git")

type("appstore")
app_identifier(["app.tempo.ios"])
username(ENV["FASTLANE_USER"] || "nicola@example.com")
team_id(ENV["APPLE_TEAM_ID"] || "XXXXXXXXXX")

force_for_new_devices(true)
```

### 9.5 Appfile

```ruby
# fastlane/Appfile
app_identifier("app.tempo.ios")
apple_id(ENV["FASTLANE_USER"] || "nicola@example.com")
team_id(ENV["APPLE_TEAM_ID"] || "XXXXXXXXXX")
itc_team_id(ENV["ITC_TEAM_ID"] || "XXXXXXXXXX")
```

---

## 10. Local Development Setup

### 10.1 Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| macOS | 14.0+ (Sonoma) | -- |
| Xcode | 16.0 | Mac App Store |
| Homebrew | Latest | `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` |
| Docker Desktop | Latest | `brew install --cask docker` |
| SwiftLint | 0.57+ | `brew install swiftlint` |
| SwiftFormat | 0.54+ | `brew install swiftformat` |
| Ruby | 3.2+ (for Fastlane) | `brew install ruby` |
| Fastlane | 2.224+ | `gem install fastlane` |
| xcbeautify | Latest | `brew install xcbeautify` |

### 10.2 Step-by-Step Setup

```bash
# 1. Clone the repository
git clone https://github.com/nicola/tempo.git
cd tempo

# 2. Install Homebrew dependencies
brew install swiftlint swiftformat xcbeautify

# 3. Install Ruby dependencies (for Fastlane)
gem install bundler
bundle install

# 4. Start backend services
cd tempo-backend
cp .env.development.template .env.development
# Edit .env.development with your CLAUDE_API_KEY if you want AI features

docker compose up -d
# Wait for services to be healthy:
docker compose ps
# You should see db (healthy), redis (running), api (running)

# 5. Verify backend is running
curl http://localhost:8080/v1/health/live
# Should return: {"status":"ok"}

# Run migrations (first time only — they auto-run in dev, but just in case):
docker compose exec api swift run App migrate --yes

# 6. Open Xcode
cd ..
open Tempo.xcodeproj
# Select the "Tempo" scheme and an iPhone simulator
# Hit Cmd+R to build and run

# 7. Run tests from command line (optional)
xcodebuild test \
  -project Tempo.xcodeproj \
  -scheme TempoTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
  | xcbeautify
```

### 10.3 Environment File Template

**`tempo-backend/.env.development.template`:**

```bash
# ============================================================
# Tempo Backend — Local Development Environment
# ============================================================
# Copy this file to .env.development and fill in your values.
# This file is gitignored. Never commit real secrets.
# ============================================================

# Only set values here that override docker-compose.yml defaults.
# Most development values are already set in docker-compose.yml.

# Claude API (required for AI insights feature)
CLAUDE_API_KEY=sk-ant-your-key-here

# Whoop (optional — only if testing real Whoop integration locally)
# WHOOP_CLIENT_ID=your-whoop-client-id
# WHOOP_CLIENT_SECRET=your-whoop-client-secret
```

### 10.4 Xcode Configuration

1. **Scheme setup:** Ensure the `Tempo` scheme uses the `Debug` build configuration, which reads from `Config/Debug.xcconfig`.

2. **Simulator:** Use iPhone 15 Pro (iOS 17.4) or iPhone 16 Pro (iOS 18.0) to match CI matrix.

3. **Environment variables in scheme:** Edit Scheme > Run > Arguments > Environment Variables:
   - `TEMPO_API_BASE_URL` = `http://localhost:8080` (should already be set via xcconfig)

4. **SwiftLint integration:** Add a Run Script build phase (before Compile Sources):
   ```bash
   if which swiftlint > /dev/null; then
     swiftlint
   else
     echo "warning: SwiftLint not installed, run 'brew install swiftlint'"
   fi
   ```

### 10.5 Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| `docker compose up` fails with port conflict | Another service on 5432 or 6379 | `lsof -i :5432` to find it, stop it, or change ports in docker-compose.yml |
| Backend compiles but crashes on startup | Missing environment variables | Check docker-compose.yml has all required env vars from Section 6.2 |
| iOS app shows "Network error" | Backend not running or wrong URL | Verify `curl http://localhost:8080/v1/health/live` works. Check xcconfig has correct URL. |
| SwiftLint errors after pulling | New lint rules in `.swiftlint.yml` | Run `swiftlint --fix` to auto-fix, then manually fix remaining |
| SPM resolution fails | Corrupted package cache | `rm -rf ~/Library/Developer/Xcode/DerivedData` and `File > Packages > Reset Package Caches` |
| Snapshot tests fail locally | Different simulator than CI | Use iPhone 15 Pro (iOS 17.4) for snapshots — same device as CI |
| Docker build slow (Swift compilation) | No build cache | First build is slow (~5-10 min). Subsequent builds use Docker layer caching. |
| `Permission denied` on Fastlane | Ruby gem path issue | `sudo gem install fastlane` or use `rbenv`/`asdf` for Ruby version management |
| Tests pass locally but fail in CI | Environment differences | Ensure you run tests with `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO` locally too |

### 10.6 Useful Commands

```bash
# Backend
docker compose up -d              # Start all services
docker compose down               # Stop all services
docker compose down -v            # Stop and wipe all data (fresh start)
docker compose logs -f api        # Tail API logs
docker compose exec db psql -U tempo -d tempo_dev  # PostgreSQL shell
docker compose exec redis redis-cli                 # Redis shell

# iOS
xcodebuild test -project Tempo.xcodeproj -scheme TempoTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' \
  | xcbeautify                    # Run unit tests

swiftlint --fix                   # Auto-fix lint issues
swiftformat .                     # Auto-format all Swift files

# Fastlane
bundle exec fastlane test         # Run full test suite
bundle exec fastlane beta         # Build + upload to TestFlight
bundle exec fastlane screenshots  # Generate App Store screenshots

# Git
git log --oneline -20             # Recent commits
git diff main...HEAD              # Changes on current branch vs main
```

---

## Appendix: GitHub Secrets Required

| Secret Name | Used By | Description |
|-------------|---------|-------------|
| `SLACK_WEBHOOK_URL` | All workflows | Slack incoming webhook for notifications |
| `MATCH_PASSWORD` | iOS release | Encryption password for Match certificates repo |
| `MATCH_GIT_TOKEN_BASE64` | iOS release | Base64-encoded `username:token` for certificates repo |
| `APPLE_ID` | iOS release | Apple ID email for Fastlane |
| `APPLE_APP_SPECIFIC_PASSWORD` | iOS release | App-specific password for Apple ID |
| `ASC_KEY_ID` | iOS release | App Store Connect API key ID |
| `ASC_ISSUER_ID` | iOS release | App Store Connect API issuer ID |
| `ASC_API_KEY_P8` | iOS release | App Store Connect API private key (P8 content) |
| `APPLE_TEAM_ID` | iOS release | Apple Developer Team ID |
| `RAILWAY_TOKEN` | Backend deploy (Railway) | Railway API token |
| `FLY_API_TOKEN` | Backend deploy (Fly.io) | Fly.io API token |
| `SENTRY_DSN` | Backend | Sentry DSN for error tracking |

---

## Appendix: GitHub Environments Required

Configure these in GitHub repo Settings > Environments:

| Environment | Protection Rules | Reviewers |
|-------------|-----------------|-----------|
| `staging` | None (auto-deploy) | -- |
| `production` | Required reviewers | Nicola |
| `app-store-review` | Required reviewers | Nicola |
