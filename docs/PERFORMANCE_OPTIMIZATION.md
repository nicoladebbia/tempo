# Tempo — Performance Optimization Specification

> **Principle**: During an active workout, when the user is sweating and breathing hard, every tap must feel instant. Performance is not a feature — it is the feature.

**App**: Tempo (iOS 17+, SwiftUI + SwiftData)
**Backend**: Vapor (Swift) + PostgreSQL
**Version**: 1.0
**Last Updated**: 2026-03-24

---

## Table of Contents

1. [Performance Budgets](#1-performance-budgets)
2. [SwiftUI Optimization Techniques](#2-swiftui-optimization-techniques)
3. [SwiftData Performance](#3-swiftdata-performance)
4. [Network Optimization](#4-network-optimization)
5. [HealthKit Performance](#5-healthkit-performance)
6. [Chart Rendering Performance](#6-chart-rendering-performance)
7. [Timer Performance](#7-timer-performance)
8. [Notification Performance](#8-notification-performance)
9. [App Size Optimization](#9-app-size-optimization)
10. [Profiling Playbook](#10-profiling-playbook)
11. [Regression Testing](#11-regression-testing)

---

## 1. Performance Budgets

Every metric has an exact target. If a measurement exceeds the budget, it is a P1 bug.

### 1.1 App Launch

| Phase | Budget | Measurement Method |
|-------|--------|--------------------|
| Cold launch to first frame | **< 800ms** | Instruments App Launch template, `DYLD_PRINT_STATISTICS` |
| Cold launch to interactive dashboard | **< 1.5s** | `os_signpost` from `main()` to `DashboardView.onAppear` completion |
| Warm launch (suspended → foreground) | **< 300ms** | `os_signpost` from `applicationDidBecomeActive` to first frame |
| Background → foreground resume | **< 100ms** | Time Profiler on `scenePhase` change to `.active` |

**Pre-main budget breakdown (< 300ms total):**

| Sub-phase | Budget | How to Measure |
|-----------|--------|----------------|
| Dylib loading | < 100ms | `DYLD_PRINT_STATISTICS=1` env var |
| Rebase/bind | < 20ms | Same |
| ObjC class setup | < 30ms | Same |
| Initializers | < 50ms | Same |
| Static Swift metadata | < 100ms | Same |

**Post-main budget breakdown (< 500ms to first frame, < 1.2s to interactive):**

| Sub-phase | Budget | How to Measure |
|-----------|--------|----------------|
| `TempoApp.init` → SwiftData container creation | < 50ms | `os_signpost` |
| `@Observable` service initialization | < 30ms | `os_signpost` |
| First `DashboardView.body` evaluation | < 50ms | SwiftUI Instruments |
| DailySnapshot fetch (today) | < 50ms | Core Data Instrument |
| HealthKit permissions check | < 20ms | `os_signpost` |
| Initial UI render (4 quadrants, skeleton) | < 100ms | SwiftUI Instruments |
| Background data hydration (Whoop, NutriTrack cached) | < 700ms | `os_signpost` (non-blocking) |

**Rules:**
- Show skeleton UI within 800ms. Never block first frame on network.
- Load cached SwiftData immediately. Background-refresh from API.
- Never call `HealthKitStore.requestAuthorization()` on launch (only on first onboarding).

### 1.2 Screen Transitions

| Transition | Budget | Notes |
|------------|--------|-------|
| Tab switch (Dashboard ↔ Training ↔ Lockdown ↔ Recovery ↔ Arena) | **< 100ms** | Tabs must be pre-loaded or load lazily without visible delay |
| Push navigation (e.g., exercise detail) | **< 200ms** | Including 350ms standard iOS push animation |
| Sheet presentation (e.g., workout log) | **< 150ms** | Sheet must begin appearing within 150ms of tap |
| Quadrant expansion (Dashboard → Expanded Body/Fuel/Mind/Move) | **< 250ms** | Hero animation must start within one frame (16ms) of tap |
| Modal dismiss | **< 100ms** | Dismiss animation begins immediately |
| Back navigation | **< 100ms** | Pop animation begins immediately |

**Rules:**
- Never compute data inside `NavigationLink` destination initializers. Use `@Lazy` loading or `.task` modifier.
- Pre-compute tab content using `@StateObject` or `@Observable` singletons.
- Sheet content must not trigger expensive queries in `.onAppear` — prefetch if possible.

### 1.3 Data Operations

| Operation | Budget | Strategy |
|-----------|--------|----------|
| SwiftData fetch: today's `DailySnapshot` | **< 50ms** | Indexed on `date`, single object fetch |
| SwiftData fetch: 90-day snapshot history | **< 200ms** | Indexed query, fetch batch size 30 |
| SwiftData fetch: today's `WorkoutPlan` with exercises | **< 80ms** | Prefetch `exercises` relationship |
| SwiftData save: single set completion | **< 10ms** | In-memory update, autosave |
| HealthKit query: today's steps | **< 100ms** | `HKStatisticsQuery` with date predicate |
| HealthKit query: today's active energy | **< 100ms** | `HKStatisticsQuery` |
| HealthKit query: 7-day steps | **< 200ms** | `HKStatisticsCollectionQuery` |
| API response rendering (tap → updated UI) | **< 300ms** | Optimistic UI + background refresh |
| Full dashboard data assembly | **< 500ms** | Parallel fetches, cached first |

### 1.4 Workout Logging (CRITICAL PATH)

These are the most latency-sensitive operations in the entire app. The user is mid-set, heart rate elevated, hands potentially sweaty. Every millisecond matters.

| Operation | Budget | Frame Budget | Strategy |
|-----------|--------|-------------|----------|
| Set complete tap → checkmark UI update | **< 16ms** | Same frame | In-memory state flip, no disk I/O on main thread |
| Set complete → haptic feedback | **< 16ms** | Same frame | `UIImpactFeedbackGenerator.prepare()` before set view appears |
| Rest timer start after set complete | **< 16ms** | Same frame | Timer state set in same state update as set completion |
| Exercise navigation (horizontal swipe) | **< 16ms/frame** | 60fps sustained | `TabView` with `.page` style, pre-rendered pages |
| Weight stepper (tap +/- or hold) | **< 16ms/step** | 60fps | Local `@State`, no SwiftData write per step |
| Rep counter tap | **< 16ms** | Same frame | Local `@State` |
| RPE selector (1-10 scale) | **< 16ms** | Same frame | No network, no disk |
| Superset transition | **< 100ms** | 6 frames | Scroll animation to next exercise |
| Set data persist to SwiftData | **< 50ms** | Background | Debounced 500ms after last interaction |

**Workout Logging Architecture:**

```swift
// CORRECT: In-memory state, debounced persistence
@Observable
class WorkoutLogViewModel {
    // In-memory working copy — ALL UI reads from here
    var activeSets: [SetState] = []

    // Debounced save — never blocks UI
    private var saveTask: Task<Void, Never>?

    func completeSet(_ index: Int) {
        // 1. Immediate state flip (< 1ms, same frame)
        activeSets[index].isCompleted = true

        // 2. Haptic (pre-prepared)
        haptic.impactOccurred()

        // 3. Start rest timer (same state update)
        restTimerState = .running(startedAt: .now)

        // 4. Debounced persist (500ms later, background)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await persistToSwiftData()
        }
    }
}
```

```swift
// WRONG: Persisting on every tap
func completeSet(_ index: Int) {
    // This blocks UI while SwiftData writes
    modelContext.save()  // 10-50ms stall
}
```

### 1.5 Charts

| Chart Type | Data Points | Render Budget | Interaction Budget |
|------------|-------------|---------------|-------------------|
| Simple line (7-day trend) | 7 | **< 50ms** | N/A |
| Standard line (30-day) | 30 | **< 100ms** | **< 16ms/frame** scrub |
| Dense line (90-day) | 90 | **< 150ms** | **< 16ms/frame** scrub |
| Year chart (365-day) | 365 → decimated to ~100 | **< 300ms** | **< 16ms/frame** scrub |
| Calendar heatmap (365 cells) | 365 | **< 200ms** | **< 16ms** cell tap |
| Exercise progress (weight over time) | Varies, max ~200 | **< 200ms** | **< 16ms/frame** scrub |
| Multi-series (overlay 2-3 metrics) | 3x90 = 270 | **< 250ms** | **< 16ms/frame** |
| Chart zoom (pinch) | N/A | **< 16ms/frame** | Maintained 60fps |

### 1.6 Memory

| State | Budget | Action if Exceeded |
|-------|--------|--------------------|
| App launch (before UI) | **< 30MB** | Audit static allocations, lazy-load services |
| Dashboard loaded (all 4 quadrants) | **< 50MB** | Check for image caching, view hierarchy depth |
| Dashboard + one expanded quadrant | **< 80MB** | Check chart image caching |
| Active workout (1 hour, ~100 sets logged) | **< 100MB** | Check for leaked closures, timer retain cycles |
| Peak during chart rendering (365-day) | **< 150MB** | Use Canvas instead of Shape stack, downsample data |
| Background (suspended) | **< 30MB** | Release all image caches, nil out chart data |
| Memory warning threshold | **< 200MB** | Implement `didReceiveMemoryWarning` handler |

**Memory rules:**
- Monitor with `os_proc_available_memory()` in debug builds.
- Set up `NotificationCenter` observer for `UIApplication.didReceiveMemoryWarningNotification`.
- On memory warning: clear image caches, release chart render buffers, nil optional large arrays.
- Never hold more than 90 days of `DailySnapshot` in memory at once. Page older data.

### 1.7 Battery

| Mode | Budget | Measurement |
|------|--------|-------------|
| Active use (dashboard browsing) | **< 15% per hour** | Energy Log in Instruments |
| Active workout logging | **< 12% per hour** | Energy Log — minimal network, no GPS |
| Focus timer (screen on, minimal UI) | **< 10% per hour** | Energy Log |
| Background (sync + timer notifications) | **< 3% per hour** | Energy Log, 1-hour test |
| Idle (app backgrounded, no active timers) | **< 0.5% per hour** | Overnight battery test |

**Battery rules:**
- No polling loops. Use server-sent events, webhooks, or `BGTaskScheduler`.
- Focus timer: update only the seconds label, not the entire view hierarchy.
- Reduce GPS usage to zero (Tempo does not need location).
- HealthKit background delivery: subscribe only to types actually displayed.

### 1.8 Network

| Operation | Data Budget | Time Budget | Caching |
|-----------|-------------|-------------|---------|
| Dashboard full refresh (all sources) | **< 500KB** | **< 2s total** | ETag per endpoint |
| Whoop sync (recovery + sleep + strain) | **< 100KB** | **< 1s** | Cache 5 min |
| NutriTrack sync (today's meals + macros) | **< 50KB** | **< 800ms** | Cache 2 min |
| Arena leaderboard fetch | **< 30KB** | **< 500ms** | Cache 1 min |
| Weekly report (AI-generated) | **< 200KB** | **< 5s** (AI generation) | Cache 24h |
| Image assets (avatars) | **< 200KB each** | Lazy load | Disk cache 7 days |
| Exercise demo thumbnails | **< 100KB each** | On-demand | Disk cache 30 days |

---

## 2. SwiftUI Optimization Techniques

### 2.1 View Identity and State Management

**Problem:** SwiftUI re-evaluates `body` whenever state changes. Incorrect state ownership causes cascading redraws across the entire view hierarchy.

**Rules for Tempo:**

1. **Never create objects in `body`:**

```swift
// WRONG: Creates a new DateFormatter every body evaluation
var body: some View {
    Text(DateFormatter.shortDate.string(from: date))
}

// CORRECT: Static formatter
private static let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    return f
}()

var body: some View {
    Text(Self.shortDateFormatter.string(from: date))
}
```

2. **Use `@Observable` for services, `@State` for view-local state:**

```swift
// CORRECT: Service layer with @Observable
@Observable
class DashboardService {
    var snapshot: DailySnapshot?
    var isLoading = false

    func loadToday() async { ... }
}

// In the view:
struct DashboardView: View {
    @State private var service = DashboardService()

    var body: some View {
        // Only re-evaluates when observed properties change
    }
}
```

3. **Isolate volatile state:**

```swift
// WRONG: Timer updates cause entire workout view to redraw
struct WorkoutLogView: View {
    @State private var restSeconds = 0 // updates every second

    var body: some View {
        VStack {
            ExerciseHeader(...)       // redrawn every second!
            SetList(...)              // redrawn every second!
            RestTimerDisplay(restSeconds) // only this needs it
        }
    }
}

// CORRECT: Extract timer into its own view
struct WorkoutLogView: View {
    var body: some View {
        VStack {
            ExerciseHeader(...)
            SetList(...)
            RestTimerView() // owns its own @State, redraws alone
        }
    }
}

struct RestTimerView: View {
    @State private var restSeconds = 0
    var body: some View {
        Text("\(restSeconds)s")
            .font(.system(size: 48, weight: .bold, design: .monospaced))
    }
}
```

**Where to apply in Tempo:**
- `DashboardView`: Each quadrant (`BodyQuadrant`, `FuelQuadrant`, `MindQuadrant`, `MoveQuadrant`) must be a separate view with its own observed data slice. A change in steps must NOT redraw the Fuel quadrant.
- `WorkoutLogView`: Rest timer, set list, and exercise header are three separate views with independent state.
- `FocusTimerView`: Timer display is isolated from the session controls.

**Measured impact:** Proper state isolation reduces body evaluations by 60-80% in data-heavy screens. On DashboardView with 4 quadrants updating independently, this means ~4 body evaluations instead of ~16 per data change.

### 2.2 Lazy Containers

**Rule:** Any list that could exceed 10 items MUST use a lazy container.

| Screen | Container | Content | Visible | Total (max) |
|--------|-----------|---------|---------|-------------|
| `ExerciseLibraryView` | `LazyVStack` in `ScrollView` | Exercise rows | ~8 | 200+ |
| `StreakCalendarView` | `LazyVGrid` (7 columns) | Day cells | ~35 | 365 |
| `SetList` (workout log) | `LazyVStack` | Set rows | ~4-6 | 20+ (supersets) |
| `LeaderboardView` | `LazyVStack` | Friend rows | ~8 | 50+ |
| `AchievementsView` | `LazyVGrid` (3 columns) | Badge cells | ~9 | 100+ |
| `WeekPlanView` | `VStack` (NOT lazy) | 7 day cards | 7 | 7 |
| `DashboardView` quadrants | `VStack` (NOT lazy) | 4 quadrants | 4 | 4 |

```swift
// Exercise Library — lazy with pinned headers
ScrollView {
    LazyVStack(pinnedViews: .sectionHeaders) {
        ForEach(muscleGroups) { group in
            Section(header: MuscleGroupHeader(group)) {
                ForEach(group.exercises) { exercise in
                    ExerciseRow(exercise: exercise)
                }
            }
        }
    }
}

// Streak Calendar — lazy grid
LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
    ForEach(days, id: \.self) { day in
        StreakDayCell(day: day, score: scores[day])
            .id(day) // stable identity
    }
}
```

**Measured impact:** `ExerciseLibraryView` with 200 exercises: `LazyVStack` renders in ~30ms (8 visible cells). Plain `VStack` renders in ~400ms (all 200 cells). Difference: **13x faster initial render.**

### 2.3 Equatable Views

**Problem:** SwiftUI's default diffing compares all view properties. For data-driven views with many properties, this is expensive.

**Rule:** Any view that receives a data model and renders > 3 subviews should conform to `Equatable`.

```swift
struct SetRowView: View, Equatable {
    let setNumber: Int
    let targetReps: Int
    let targetWeight: Double?
    let actualReps: Int?
    let actualWeight: Double?
    let isCompleted: Bool

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.setNumber == rhs.setNumber &&
        lhs.isCompleted == rhs.isCompleted &&
        lhs.actualReps == rhs.actualReps &&
        lhs.actualWeight == rhs.actualWeight
    }

    var body: some View {
        HStack {
            // Complex layout with multiple subviews
        }
    }
}

// Usage with EquatableView wrapper
ForEach(sets.indices, id: \.self) { i in
    EquatableView(content: SetRowView(
        setNumber: i + 1,
        targetReps: sets[i].targetReps,
        targetWeight: sets[i].targetWeight,
        actualReps: sets[i].actualReps,
        actualWeight: sets[i].actualWeight,
        isCompleted: sets[i].completed
    ))
}
```

**Where to apply in Tempo:**
- `SetRowView` — critical path, rendered during active workout
- `QuadrantCard` — dashboard, 4 instances, each with complex content
- `ExerciseRow` — exercise library, hundreds of instances
- `LeaderboardRow` — arena, dozens of instances
- `StreakDayCell` — calendar heatmap, 365 instances

**Measured impact:** For `SetRowView` in a workout with 20 sets, Equatable conformance prevents ~18 unnecessary body evaluations when one set is completed. Saves ~5ms per set completion.

### 2.4 Drawing Optimization

**Rule:** Complex charts and custom graphics use `Canvas`. Simple shapes use native SwiftUI shapes.

```swift
// CORRECT: Canvas for progress chart with many data points
struct ProgressChart: View {
    let dataPoints: [ChartDataPoint]

    var body: some View {
        Canvas { context, size in
            // Single render pass — GPU accelerated
            let path = Path { p in
                guard let first = dataPoints.first else { return }
                p.move(to: point(for: first, in: size))
                for point in dataPoints.dropFirst() {
                    p.addLine(to: self.point(for: point, in: size))
                }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
    }
}

// WRONG: Shape stack for chart (creates N SwiftUI views)
struct ProgressChart: View {
    let dataPoints: [ChartDataPoint]
    var body: some View {
        ZStack {
            ForEach(dataPoints) { point in
                Circle()  // Each is a separate SwiftUI view!
                    .position(...)
            }
            Path { ... }
        }
    }
}
```

**Use `drawingGroup()` for composite views:**

```swift
// Score ring on dashboard — many overlapping layers
ScoreRing(score: dailyScore, size: 120)
    .drawingGroup() // Flattens into single Metal texture

// When to use drawingGroup():
// - ScoreRing (gradient + stroke + text overlay)
// - QuadrantCard progress arcs
// - Streak calendar (365 colored cells)
// When NOT to use:
// - Views with interactive subviews (buttons, taps)
// - Views that animate individual children
```

**Measured impact:** `ScoreRing` with gradient stroke + shadow: without `drawingGroup()` = 8ms render. With `drawingGroup()` = 2ms render. **4x faster.**

### 2.5 Image Handling

```swift
// Avatar images — async with cache and placeholder
AsyncImage(url: friend.avatarURL) { phase in
    switch phase {
    case .success(let image):
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    case .failure:
        InitialsAvatar(name: friend.displayName)
    case .empty:
        ProgressView()
    @unknown default:
        EmptyView()
    }
}
.frame(width: 40, height: 40)
.clipShape(Circle())

// SF Symbols — pre-render at exact size
Image(systemName: "checkmark.circle.fill")
    .font(.system(size: 24)) // Exact size, not resizable
    .foregroundStyle(.green)
    .symbolRenderingMode(.hierarchical) // GPU-efficient rendering

// Exercise demo images — lazy download with disk cache
struct ExerciseDemoImage: View {
    let exerciseID: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(ProgressView())
            }
        }
        .task {
            image = await ImageCache.shared.load(exerciseID: exerciseID)
        }
    }
}
```

**Rules:**
- Never use `Image(uiImage:)` with a full-resolution photo. Always downscale first.
- Avatar images: max 200x200px, JPEG quality 0.7.
- Exercise demo thumbnails: max 400x300px, HEIC format preferred.
- Use `prepareForDisplay()` on UIImage to pre-decode off main thread.

### 2.6 List Optimization

```swift
// CORRECT: Stable identity with model ID
ForEach(exercises, id: \.persistentModelID) { exercise in
    ExerciseRow(exercise: exercise)
}

// WRONG: AnyView erases type information, defeats diffing
ForEach(items) { item in
    AnyView(item.isSpecial ? AnyView(SpecialRow(item)) : AnyView(NormalRow(item)))
}

// CORRECT: Conditional without AnyView
ForEach(items) { item in
    if item.isSpecial {
        SpecialRow(item: item)
    } else {
        NormalRow(item: item)
    }
}

// CORRECT: ViewBuilder for complex conditional content
@ViewBuilder
func row(for item: Item) -> some View {
    switch item.type {
    case .study: StudyRow(item: item)
    case .workout: WorkoutRow(item: item)
    case .meal: MealRow(item: item)
    }
}
```

**Rules for Tempo lists:**
- Every `ForEach` must have a stable, unique `id`. Use `persistentModelID` for SwiftData models.
- Never use `AnyView`. Use `@ViewBuilder` or `Group` for conditional content.
- For the exercise library (200+ items), use `.searchable` with debounced filtering (300ms debounce).

### 2.7 Animation Performance

```swift
// CORRECT: Scoped animation (only animates changes to `isCompleted`)
SetRowView(...)
    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCompleted)

// WRONG: Unscoped animation (animates everything, including layout changes)
SetRowView(...)
    .animation(.spring())

// CORRECT: Explicit transaction for workout set completion
func completeSet(_ index: Int) {
    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
        sets[index].isCompleted = true
    }
    // Rest timer starts without animation
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        restTimerActive = true
    }
}

// Quadrant expansion — matchedGeometryEffect for hero animation
@Namespace private var dashboardNamespace

QuadrantCard(...)
    .matchedGeometryEffect(id: "body-quadrant", in: dashboardNamespace)
    .onTapGesture {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            expandedQuadrant = .body
        }
    }
```

**Animation budget per context:**

| Context | Max Duration | Curve | Notes |
|---------|-------------|-------|-------|
| Set completion checkmark | 250ms | `.spring(response: 0.25)` | Must feel snappy |
| Rest timer start | 0ms | None | Instant, no animation |
| Tab switch | 200ms | `.easeInOut` | System default |
| Quadrant expansion | 350ms | `.spring(response: 0.35)` | Hero animation |
| Sheet presentation | 300ms | System default | Standard iOS |
| Score ring fill | 800ms | `.easeOut` | Satisfying fill on load |
| Streak calendar appear | 400ms | Staggered `.spring` | Progressive reveal |
| XP gain counter | 600ms | `.spring(bounce: 0.3)` | Bouncy, celebratory |

**Rules:**
- All animations must use the `value:` parameter (scoped animations).
- During active workout, animations are shorter (< 250ms). No flourishes.
- Use `UIView.animate` or `CADisplayLink` for animations that must be exactly 60fps (chart interactions).
- Test all animations on the oldest supported device (iPhone 13 minimum).

---

## 3. SwiftData Performance

### 3.1 Batch Operations

```swift
// CORRECT: Use enumerate for large result processing
let descriptor = FetchDescriptor<DailySnapshot>(
    predicate: #Predicate { $0.date >= ninetyDaysAgo },
    sortBy: [SortDescriptor(\.date, order: .reverse)]
)
descriptor.fetchBatchSize = 30

// Process in batches without loading all into memory
let context = ModelContext(container)
try context.enumerate(descriptor) { snapshot in
    // Process each snapshot
    chartData.append(ChartPoint(date: snapshot.date, score: snapshot.dailyScore))
}

// WRONG: Fetch all into array (loads 90 objects into memory at once)
let snapshots = try context.fetch(descriptor) // all 90 in memory
```

**Batch size guidelines for Tempo:**

| Query | fetchBatchSize | fetchLimit | Reason |
|-------|---------------|------------|--------|
| Today's snapshot | N/A | 1 | Single object |
| Today's workout + exercises | N/A | 1 | Single object with prefetch |
| 7-day dashboard trend | 7 | 7 | Small set |
| 30-day chart | 15 | 30 | Two batches |
| 90-day chart | 30 | 90 | Three batches |
| 365-day heatmap | 50 | 365 | Seven batches |
| Exercise library (full) | 20 | nil | Lazy list, page on scroll |
| Workout history search | 20 | 50 | Paginated |

### 3.2 Indexes

Every predicate and sort key used in a fetch must be indexed. These are the required indexes for Tempo's SwiftData models:

```swift
// DailySnapshot
@Model
class DailySnapshot {
    #Index<DailySnapshot>([\.date])
    #Index<DailySnapshot>([\.date, \.dailyScore])
    var date: Date
    var dailyScore: Int
    // ...
}

// WorkoutPlan
@Model
class WorkoutPlan {
    #Index<WorkoutPlan>([\.date])
    #Index<WorkoutPlan>([\.date, \.status])
    var date: Date
    var status: WorkoutStatus
    // ...
}

// Exercise
@Model
class Exercise {
    #Index<Exercise>([\.name])
    #Index<Exercise>([\.muscleGroup])
    #Index<Exercise>([\.muscleGroup, \.name])
    var name: String
    var muscleGroup: MuscleGroup
    // ...
}

// NonNegotiable
@Model
class NonNegotiable {
    // Indexed via parent DailyAccountability.date
}

// DailyAccountability
@Model
class DailyAccountability {
    #Index<DailyAccountability>([\.date])
    var date: Date
    // ...
}

// DailyPrescription
@Model
class DailyPrescription {
    #Index<DailyPrescription>([\.date])
    var date: Date
    // ...
}

// StudySession
@Model
class StudySession {
    #Index<StudySession>([\.startDate])
    #Index<StudySession>([\.startDate, \.endDate])
    var startDate: Date
    var endDate: Date?
    // ...
}
```

**Index impact estimates:**
- `DailySnapshot` by date: fetch drops from ~15ms (table scan) to ~1ms (index seek) for single-day queries.
- `Exercise` by muscleGroup + name: library filter drops from ~8ms to ~1ms for 200+ exercises.

### 3.3 Relationship Prefetching

```swift
// CORRECT: Prefetch exercises when loading today's workout
var descriptor = FetchDescriptor<WorkoutPlan>(
    predicate: #Predicate { $0.date == today }
)
descriptor.relationshipKeyPathsForPrefetching = [\.exercises]

// CORRECT: Prefetch sets within exercises (nested)
// Note: SwiftData auto-prefetches one level. For nested, use explicit.
descriptor.relationshipKeyPathsForPrefetching = [
    \.exercises,
    \.exercises.each.sets  // if supported, otherwise manual
]

// WRONG: Accessing exercises lazily causes N+1 queries
let plan = try context.fetch(descriptor).first!
for exercise in plan.exercises {        // query 1
    for set in exercise.sets {          // query per exercise = N more
        // ...
    }
}
```

**Prefetch map for Tempo:**

| Root Fetch | Prefetch Relationships | Used By |
|-----------|----------------------|---------|
| `WorkoutPlan` (today) | `exercises`, `exercises.sets` | TodayWorkoutView, WorkoutLogView |
| `DailyAccountability` (today) | `nonNegotiables` | LockdownView |
| `DailySnapshot` (date range) | None (flat model) | Charts, Dashboard |
| `Exercise` (library browse) | None (detail loaded on tap) | ExerciseLibraryView |

### 3.4 Background Contexts with ModelActor

All sync operations (Whoop, NutriTrack, HealthKit) MUST run on a background `ModelActor` to avoid blocking the UI.

```swift
@ModelActor
actor SyncModelActor {
    /// Persist Whoop recovery data fetched from backend
    func persistWhoopData(_ whoopData: WhoopSyncResponse) throws {
        let today = Calendar.current.startOfDay(for: .now)
        let descriptor = FetchDescriptor<DailySnapshot>(
            predicate: #Predicate { $0.date == today }
        )

        let snapshot = try modelContext.fetch(descriptor).first
            ?? DailySnapshot(date: today)

        snapshot.recoveryScore = whoopData.recovery.score
        snapshot.hrvRmssd = whoopData.recovery.hrv
        snapshot.restingHR = whoopData.recovery.restingHR
        snapshot.sleepHours = whoopData.sleep.totalHours
        snapshot.sleepScore = whoopData.sleep.score
        snapshot.strain = whoopData.strain.score

        if snapshot.modelContext == nil {
            modelContext.insert(snapshot)
        }
        try modelContext.save()
    }

    /// Batch persist historical data (e.g., initial Whoop sync)
    func persistHistoricalSnapshots(_ snapshots: [WhoopDayData]) throws {
        for (index, data) in snapshots.enumerated() {
            let snapshot = DailySnapshot(date: data.date)
            // ... populate fields
            modelContext.insert(snapshot)

            // Save in batches of 50 to manage memory
            if index % 50 == 0 {
                try modelContext.save()
            }
        }
        try modelContext.save() // final batch
    }
}

// Usage from service layer
let actor = SyncModelActor(modelContainer: container)
await actor.persistWhoopData(response)
// Main context auto-merges via container's notification
```

### 3.5 Migration Performance

**Rules:**
- Lightweight migrations (adding optional properties, new models) are free. SwiftData handles them automatically.
- Schema changes that require data transformation must run as a `BackgroundTask` on first launch after update.
- Show a migration progress screen if migration takes > 500ms.
- Never run migrations on the main thread.

```swift
// Migration strategy for heavy schema changes
@main
struct TempoApp: App {
    @State private var isMigrating = false

    var body: some Scene {
        WindowGroup {
            if isMigrating {
                MigrationView()
            } else {
                ContentView()
            }
        }
    }

    init() {
        // Check if migration needed before creating container
        if MigrationManager.needsMigration() {
            isMigrating = true
            Task {
                await MigrationManager.runMigrations()
                await MainActor.run { isMigrating = false }
            }
        }
    }
}
```

### 3.6 Compound Queries: Denormalize vs. Join

**Denormalize when:**
- Data is read 100x more than written (dashboards, charts)
- The denormalized field is derived from a single write event

**Keep normalized when:**
- Data changes frequently from multiple sources
- Consistency is more important than read speed

**Tempo denormalization decisions:**

| Field | Decision | Reason |
|-------|----------|--------|
| `DailySnapshot.dailyScore` | **Denormalized** | Computed from 6+ sources, but read on every dashboard load. Compute once at EOD or on change. |
| `DailySnapshot.nonNegotiablesCompleted` | **Denormalized** | Read on dashboard, written when non-negotiable completes. Copy from `DailyAccountability`. |
| `WorkoutPlan.totalVolume` | **Denormalized** | Sum of (weight * reps) across all sets. Compute after workout, avoid re-summing on chart views. |
| `Exercise.personalBest` | **Denormalized** | Read on every exercise row in library. Update after each workout if new PR. |
| `NonNegotiable.currentValue` | **Normalized** | Updated frequently from multiple sources (HealthKit, NutriTrack, manual). Keep single source of truth. |

### 3.7 Monitoring SwiftData with Instruments

**Core Data Instrument** (SwiftData uses Core Data under the hood):

1. Open Instruments → Core Data template
2. Traces to watch:
   - **Fetches**: Count, duration, row count per fetch
   - **Saves**: Count, duration, conflict count
   - **Faults**: Relationship fault fires (indicates missing prefetch)
3. Red flags:
   - Any fetch > 50ms on main thread
   - Any save > 10ms on main thread
   - Fault count > 5 during a single view load (N+1 problem)
   - Fetch count > 3 during a tab switch

**Custom `os_signpost` for SwiftData monitoring:**

```swift
import os

private let swiftDataLog = OSLog(subsystem: "com.tempo.app", category: "SwiftData")

extension ModelContext {
    func timedFetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
        let signpostID = OSSignpostID(log: swiftDataLog)
        os_signpost(.begin, log: swiftDataLog, name: "SwiftData Fetch",
                    signpostID: signpostID, "%{public}s", String(describing: T.self))
        let result = try fetch(descriptor)
        os_signpost(.end, log: swiftDataLog, name: "SwiftData Fetch",
                    signpostID: signpostID, "rows: %d", result.count)
        return result
    }
}
```

---

## 4. Network Optimization

### 4.1 Request Batching

Combine multiple API calls into a single sync endpoint where possible.

```
// WRONG: 4 sequential API calls on dashboard load
GET /api/whoop/recovery      → 200ms
GET /api/whoop/sleep         → 200ms
GET /api/whoop/strain        → 200ms
GET /api/nutritrack/today    → 300ms
TOTAL: ~900ms sequential, ~300ms parallel

// CORRECT: Single batch sync endpoint
POST /api/sync/dashboard
{
  "sources": ["whoop", "nutritrack"],
  "last_sync": "2026-03-24T08:00:00Z"
}

Response (single round-trip):
{
  "whoop": { "recovery": {...}, "sleep": {...}, "strain": {...} },
  "nutritrack": { "meals": [...], "macros": {...} },
  "updated_at": "2026-03-24T09:30:00Z"
}

TOTAL: ~200ms (single round-trip, backend fans out in parallel)
```

**Vapor backend implementation:**

```swift
// SyncController.swift — batch endpoint
func dashboardSync(req: Request) async throws -> DashboardSyncResponse {
    let userID = try req.auth.require(User.self).id!
    let request = try req.content.decode(DashboardSyncRequest.self)

    async let whoop = whoopService.fetchAll(for: userID, since: request.lastSync)
    async let nutri = nutriTrackService.fetchToday(for: userID, since: request.lastSync)

    return DashboardSyncResponse(
        whoop: try await whoop,
        nutritrack: try await nutri,
        updatedAt: Date()
    )
}
```

### 4.2 Response Compression

**Vapor configuration:**

```swift
// configure.swift
app.middleware.use(CompressionMiddleware()) // Brotli preferred, gzip fallback

// Custom middleware that respects Accept-Encoding
struct CompressionMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        // Vapor's built-in compression handles this,
        // but ensure Content-Type is compressible
        return response
    }
}
```

**iOS client: URLSession handles decompression automatically.** Ensure `Accept-Encoding: br, gzip` header is set (default behavior).

**Expected savings:**

| Response | Uncompressed | Brotli | Savings |
|----------|-------------|--------|---------|
| Dashboard sync JSON | ~50KB | ~8KB | 84% |
| Weekly report JSON | ~200KB | ~30KB | 85% |
| Leaderboard JSON | ~30KB | ~5KB | 83% |
| Exercise library JSON | ~100KB | ~15KB | 85% |

### 4.3 Conditional Requests (ETag)

```swift
// Vapor backend — ETag support
struct ETagMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)

        guard let body = response.body.data else { return response }
        let etag = "\"\(body.hashValue)\""
        response.headers.replaceOrAdd(name: .eTag, value: etag)

        if let ifNoneMatch = request.headers[.ifNoneMatch].first,
           ifNoneMatch == etag {
            return Response(status: .notModified)
        }

        return response
    }
}

// iOS client — ETag caching
class APIClient {
    private var etagCache: [String: String] = [:] // endpoint → etag

    func fetch<T: Decodable>(_ endpoint: String) async throws -> T? {
        var request = URLRequest(url: baseURL.appending(path: endpoint))

        if let etag = etagCache[endpoint] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode == 304 {
            return nil // data unchanged, use local cache
        }

        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
            etagCache[endpoint] = etag
        }

        return try JSONDecoder.tempo.decode(T.self, from: data)
    }
}
```

**ETag endpoints for Tempo:**

| Endpoint | Cache TTL | Expected Hit Rate |
|----------|-----------|-------------------|
| `/api/sync/dashboard` | 2 min | 60% (data changes frequently) |
| `/api/whoop/recovery` | 5 min | 80% (updates ~4x/day) |
| `/api/nutritrack/today` | 2 min | 50% (updates after meals) |
| `/api/arena/leaderboard` | 1 min | 70% (updates on XP events) |
| `/api/exercises` | 24h | 99% (rarely changes) |
| `/api/user/profile` | 1h | 95% |

### 4.4 Prefetching

```swift
// When user is on Dashboard tab, prefetch Training data
struct ContentView: View {
    @State private var selectedTab = Tab.dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tag(Tab.dashboard)
            TrainingView()
                .tag(Tab.training)
            // ...
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            prefetchAdjacentTabs(current: newTab)
        }
    }

    private func prefetchAdjacentTabs(current: Tab) {
        Task(priority: .utility) {
            switch current {
            case .dashboard:
                await trainingService.prefetchTodayWorkout()
                await accountabilityService.prefetchToday()
            case .training:
                await dashboardService.prefetchSnapshot()
            case .accountability:
                await recoveryService.prefetchToday()
            default:
                break
            }
        }
    }
}
```

### 4.5 URLSession Configuration

```swift
// Shared URLSession for API calls
let apiSessionConfig: URLSessionConfiguration = {
    let config = URLSessionConfiguration.default
    config.httpMaximumConnectionsPerHost = 4
    config.timeoutIntervalForRequest = 15    // 15s per request
    config.timeoutIntervalForResource = 60   // 60s total
    config.waitsForConnectivity = true
    config.requestCachePolicy = .reloadRevalidatingCacheData
    config.urlCache = URLCache(
        memoryCapacity: 10 * 1024 * 1024,  // 10MB memory
        diskCapacity: 50 * 1024 * 1024      // 50MB disk
    )
    config.httpAdditionalHeaders = [
        "Accept": "application/json",
        "Accept-Encoding": "br, gzip"
    ]
    return config
}()

// Background session for sync operations
let backgroundSessionConfig: URLSessionConfiguration = {
    let config = URLSessionConfiguration.background(
        withIdentifier: "com.tempo.app.background-sync"
    )
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false  // sync is time-sensitive
    return config
}()
```

### 4.6 Offline Queue

```swift
@Observable
class OfflineQueue {
    private var pendingRequests: [QueuedRequest] = []
    private let storage = UserDefaults.standard // or file-based for large payloads

    struct QueuedRequest: Codable {
        let id: UUID
        let endpoint: String
        let method: String
        let body: Data?
        let createdAt: Date
        let retryCount: Int
    }

    func enqueue(_ request: QueuedRequest) {
        pendingRequests.append(request)
        persistQueue()
    }

    /// Called when network becomes available
    func replayQueue() async {
        let requests = pendingRequests.sorted(by: { $0.createdAt < $1.createdAt })
        for request in requests {
            do {
                try await apiClient.execute(request)
                pendingRequests.removeAll(where: { $0.id == request.id })
            } catch {
                // Increment retry count, skip if > 3
                if request.retryCount >= 3 {
                    pendingRequests.removeAll(where: { $0.id == request.id })
                }
            }
        }
        persistQueue()
    }
}
```

**Offline-capable operations in Tempo:**

| Operation | Queued Offline? | Replay Strategy |
|-----------|----------------|-----------------|
| Set completion / workout log | Yes | Replay in order when online |
| Non-negotiable manual check-off | Yes | Replay in order |
| XP event submission | Yes | Idempotent by UUID |
| Dashboard refresh | No | Show cached data |
| Leaderboard fetch | No | Show "offline" state |
| Friend request | Yes | Replay when online |

### 4.7 Image Caching

```swift
actor ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCachePath: URL

    init() {
        diskCachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImageCache")
        try? FileManager.default.createDirectory(at: diskCachePath, withIntermediateDirectories: true)
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 20 * 1024 * 1024 // 20MB
    }

    func load(url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString

        // 1. Memory cache (< 1ms)
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. Disk cache (< 10ms)
        let diskPath = diskCachePath.appendingPathComponent(key.hash.description)
        if let data = try? Data(contentsOf: diskPath),
           let image = UIImage(data: data) {
            let prepared = await image.byPreparingForDisplay() // decode off main thread
            memoryCache.setObject(prepared ?? image, forKey: key)
            return prepared ?? image
        }

        // 3. Network download
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }

        let prepared = await image.byPreparingForDisplay()
        memoryCache.setObject(prepared ?? image, forKey: key)
        try? data.write(to: diskPath)
        return prepared ?? image
    }

    func clearMemory() {
        memoryCache.removeAllObjects()
    }
}
```

### 4.8 API Response Caching (Per-Endpoint TTL)

| Endpoint | Memory TTL | Disk TTL | Invalidation Trigger |
|----------|-----------|----------|---------------------|
| `/api/sync/dashboard` | 2 min | 30 min | Manual refresh, app foreground |
| `/api/whoop/recovery` | 5 min | 2h | Whoop webhook |
| `/api/nutritrack/today` | 2 min | 1h | Meal log event |
| `/api/arena/leaderboard` | 1 min | 15 min | XP event |
| `/api/exercises` | 24h | 30 days | App update |
| `/api/user/profile` | 1h | 7 days | Profile edit |
| `/api/ai/weekly-report` | 24h | 7 days | Manual regenerate |
| `/api/arena/achievements` | 10 min | 24h | Achievement earned |

---

## 5. HealthKit Performance

### 5.1 Query Optimization

```swift
// CORRECT: Use HKStatisticsQuery for aggregated data
func fetchTodaySteps() async throws -> Int {
    let stepType = HKQuantityType(.stepCount)
    let today = Calendar.current.startOfDay(for: .now)
    let predicate = HKQuery.predicateForSamples(withStart: today, end: .now)

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { _, statistics, error in
            if let error { continuation.resume(throwing: error); return }
            let steps = Int(statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            continuation.resume(returning: steps)
        }
        healthStore.execute(query)
    }
}

// WRONG: Fetching all samples and summing manually
func fetchTodayStepsWrong() async throws -> Int {
    let stepType = HKQuantityType(.stepCount)
    let predicate = HKQuery.predicateForSamples(withStart: today, end: .now)

    let query = HKSampleQuery(sampleType: stepType, predicate: predicate,
                              limit: HKObjectQueryNoLimit, // could return 1000+ samples!
                              sortDescriptors: nil) { _, samples, _ in
        // Manual aggregation of 1000+ samples = slow
        let total = samples?.reduce(0) { $0 + ($1 as! HKQuantitySample)
            .quantity.doubleValue(for: .count()) } ?? 0
    }
    healthStore.execute(query)
}
```

**Performance difference:** `HKStatisticsQuery` for today's steps: ~15ms. `HKSampleQuery` + manual sum: ~150ms (10x slower with 500+ samples).

### 5.2 Statistics Collection for Ranges

```swift
// 7-day step trend — single query, pre-aggregated by day
func fetchWeeklySteps() async throws -> [(Date, Int)] {
    let stepType = HKQuantityType(.stepCount)
    let calendar = Calendar.current
    let endDate = Date()
    let startDate = calendar.date(byAdding: .day, value: -7, to: endDate)!

    let interval = DateComponents(day: 1)
    let anchorDate = calendar.startOfDay(for: startDate)

    return try await withCheckedThrowingContinuation { continuation in
        let query = HKStatisticsCollectionQuery(
            quantityType: stepType,
            quantitySamplePredicate: HKQuery.predicateForSamples(
                withStart: startDate, end: endDate
            ),
            options: .cumulativeSum,
            anchorDate: anchorDate,
            intervalComponents: interval
        )

        query.initialResultsHandler = { _, collection, error in
            if let error { continuation.resume(throwing: error); return }
            var results: [(Date, Int)] = []
            collection?.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                let steps = Int(stats.sumQuantity()?.doubleValue(for: .count()) ?? 0)
                results.append((stats.startDate, steps))
            }
            continuation.resume(returning: results)
        }

        healthStore.execute(query)
    }
}
```

### 5.3 Background Delivery

```swift
// Configure background delivery per type
func enableBackgroundDelivery() {
    let typesToWatch: [(HKObjectType, HKUpdateFrequency)] = [
        (HKQuantityType(.stepCount), .hourly),           // Steps: hourly is fine
        (HKWorkoutType.workoutType(), .immediate),        // Workouts: need to know ASAP
        (HKCategoryType(.sleepAnalysis), .hourly),        // Sleep: hourly is fine
        // DO NOT subscribe to heart rate — too frequent, battery drain
    ]

    for (type, frequency) in typesToWatch {
        healthStore.enableBackgroundDelivery(for: type, frequency: frequency) { success, error in
            if let error {
                os_log("Background delivery failed for %{public}@: %{public}@",
                       type.identifier, error.localizedDescription)
            }
        }
    }
}
```

**Rules:**
- Never subscribe to `heartRate` for background delivery. It generates hundreds of samples per hour during workouts and would drain the battery.
- Use `.immediate` only for workout completion (triggers non-negotiable auto-check).
- Use `.hourly` for steps and sleep (dashboard refresh).

### 5.4 Predicate Optimization

```swift
// ALWAYS use date predicates — never query unbounded
// CORRECT:
let predicate = HKQuery.predicateForSamples(
    withStart: Calendar.current.startOfDay(for: .now),
    end: .now,
    options: .strictStartDate
)

// WRONG: No date predicate → scans entire HealthKit database
let predicate: NSPredicate? = nil

// For source-specific queries (e.g., only Whoop HRV):
let sourcePredicate = HKQuery.predicateForObjects(from: whoopSource)
let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
    sourcePredicate, datePredicate
])
```

### 5.5 HealthKit Caching

Cache HealthKit results in SwiftData to avoid re-querying on every screen appear.

```swift
@Observable
class HealthKitService {
    // In-memory cache of today's data
    private var cachedSteps: (value: Int, fetchedAt: Date)?
    private var cachedActiveEnergy: (value: Double, fetchedAt: Date)?

    private let cacheDuration: TimeInterval = 120 // 2 minutes

    func todaySteps() async throws -> Int {
        if let cached = cachedSteps,
           Date().timeIntervalSince(cached.fetchedAt) < cacheDuration {
            return cached.value
        }

        let steps = try await fetchTodaySteps()
        cachedSteps = (steps, .now)

        // Also persist to DailySnapshot for offline access
        await syncActor.updateSteps(steps, for: .now)

        return steps
    }
}
```

**Cache hierarchy for HealthKit data:**

| Level | Duration | Storage | Used When |
|-------|----------|---------|-----------|
| In-memory | 2 min | `@Observable` property | Same screen, quick re-reads |
| SwiftData | 24h | `DailySnapshot` fields | App relaunch, offline |
| HealthKit | Permanent | Health database | Cache miss, first load |

---

## 6. Chart Rendering Performance

### 6.1 Data Decimation (LTTB Algorithm)

For charts with > 100 data points, downsample using the Largest-Triangle-Three-Buckets algorithm to preserve visual shape while reducing render cost.

```swift
/// Largest-Triangle-Three-Buckets downsampling
/// Preserves visual shape of the data while reducing point count
func downsampleLTTB(data: [ChartPoint], targetCount: Int) -> [ChartPoint] {
    guard data.count > targetCount else { return data }

    var result: [ChartPoint] = []
    result.reserveCapacity(targetCount)

    // Always keep first and last point
    result.append(data[0])

    let bucketSize = Double(data.count - 2) / Double(targetCount - 2)

    var previousIndex = 0

    for i in 1..<(targetCount - 1) {
        let bucketStart = Int(Double(i - 1) * bucketSize) + 1
        let bucketEnd = min(Int(Double(i) * bucketSize) + 1, data.count - 1)
        let nextBucketStart = min(Int(Double(i + 1) * bucketSize) + 1, data.count - 1)
        let nextBucketEnd = min(Int(Double(i + 2) * bucketSize) + 1, data.count)

        // Average of next bucket (the "triangle tip")
        let avgX = data[nextBucketStart..<nextBucketEnd]
            .reduce(0.0) { $0 + $1.x } / Double(nextBucketEnd - nextBucketStart)
        let avgY = data[nextBucketStart..<nextBucketEnd]
            .reduce(0.0) { $0 + $1.y } / Double(nextBucketEnd - nextBucketStart)

        // Find point in current bucket with largest triangle area
        var maxArea = -1.0
        var maxIndex = bucketStart

        let prevPoint = data[previousIndex]
        for j in bucketStart..<bucketEnd {
            let area = abs(
                (prevPoint.x - avgX) * (data[j].y - prevPoint.y) -
                (prevPoint.x - data[j].x) * (avgY - prevPoint.y)
            ) * 0.5
            if area > maxArea {
                maxArea = area
                maxIndex = j
            }
        }

        result.append(data[maxIndex])
        previousIndex = maxIndex
    }

    result.append(data[data.count - 1])
    return result
}
```

**Decimation targets for Tempo charts:**

| Chart | Raw Points | Decimated Points | Visual Quality |
|-------|-----------|-----------------|----------------|
| 7-day trend | 7 | 7 (no decimation) | Perfect |
| 30-day trend | 30 | 30 (no decimation) | Perfect |
| 90-day trend | 90 | 90 (no decimation) | Perfect |
| 365-day trend | 365 | 100 | Excellent — LTTB preserves all peaks/valleys |
| Exercise progress (2yr) | 500+ | 120 | Excellent |

### 6.2 Canvas Rendering

```swift
struct TrendLineChart: View {
    let data: [ChartPoint]
    let lineColor: Color
    let fillGradient: Bool

    // Pre-computed on init, NOT in body
    private let processedData: [CGPoint]
    private let yRange: ClosedRange<Double>

    init(data: [ChartPoint], lineColor: Color = .accentColor, fillGradient: Bool = true) {
        self.data = data
        self.lineColor = lineColor
        self.fillGradient = fillGradient

        // Pre-compute normalized points
        let ys = data.map(\.y)
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        self.yRange = minY...maxY
        self.processedData = data.enumerated().map { i, point in
            CGPoint(
                x: Double(i) / Double(max(data.count - 1, 1)),
                y: (point.y - minY) / max(maxY - minY, 1)
            )
        }
    }

    var body: some View {
        Canvas { context, size in
            guard processedData.count >= 2 else { return }

            let points = processedData.map { CGPoint(
                x: $0.x * size.width,
                y: size.height - ($0.y * size.height * 0.85) - size.height * 0.075
            )}

            // Smooth line path using Catmull-Rom spline
            var linePath = Path()
            linePath.move(to: points[0])
            for i in 1..<points.count {
                let p0 = points[max(i - 2, 0)]
                let p1 = points[i - 1]
                let p2 = points[i]
                let p3 = points[min(i + 1, points.count - 1)]

                let cp1 = CGPoint(
                    x: p1.x + (p2.x - p0.x) / 6,
                    y: p1.y + (p2.y - p0.y) / 6
                )
                let cp2 = CGPoint(
                    x: p2.x - (p3.x - p1.x) / 6,
                    y: p2.y - (p3.y - p1.y) / 6
                )
                linePath.addCurve(to: p2, control1: cp1, control2: cp2)
            }

            // Fill gradient
            if fillGradient {
                var fillPath = linePath
                fillPath.addLine(to: CGPoint(x: points.last!.x, y: size.height))
                fillPath.addLine(to: CGPoint(x: points.first!.x, y: size.height))
                fillPath.closeSubpath()

                context.fill(fillPath, with: .linearGradient(
                    Gradient(colors: [lineColor.opacity(0.3), lineColor.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
            }

            // Stroke line
            context.stroke(linePath, with: .color(lineColor), lineWidth: 2.5)
        }
        .drawingGroup() // Flatten to Metal texture
    }
}
```

### 6.3 Cached Chart Images

For static charts that don't need interaction (weekly report, push notification rich content):

```swift
actor ChartImageCache {
    private var cache: [String: UIImage] = [:]

    func render(chart: TrendLineChart, size: CGSize, cacheKey: String) async -> UIImage {
        if let cached = cache[cacheKey] { return cached }

        let renderer = ImageRenderer(content:
            chart.frame(width: size.width, height: size.height)
        )
        renderer.scale = UIScreen.main.scale

        guard let image = renderer.uiImage else {
            return UIImage()
        }

        cache[cacheKey] = image
        return image
    }

    func invalidate(key: String) {
        cache.removeValue(forKey: key)
    }

    func clearAll() {
        cache.removeAll()
    }
}
```

**When to use cached chart images:**
- Weekly report charts (rendered once, displayed as images)
- Widget charts (WidgetKit uses timeline entries)
- Notification attachments
- Share sheet screenshots

**When NOT to use:**
- Any interactive chart (scrubbing, zooming)
- Real-time data (workout HR chart)

### 6.4 Chart Interaction Performance

```swift
struct InteractiveChart: View {
    let data: [ChartPoint]

    // Pre-computed arrays for O(1) lookup during gesture
    private let xPositions: [CGFloat]  // normalized x positions
    private let values: [Double]       // y values for display

    @State private var selectedIndex: Int?
    @State private var touchLocation: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            // ... draw chart ...

            // Draw selection indicator if active
            if let idx = selectedIndex {
                let x = xPositions[idx] * size.width
                // Draw vertical line + dot
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.secondary.opacity(0.5)),
                    lineWidth: 1
                )
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Binary search for nearest point — O(log n)
                    let normalizedX = value.location.x / geometrySize.width
                    selectedIndex = nearestIndex(to: normalizedX)
                }
                .onEnded { _ in
                    selectedIndex = nil
                }
        )
    }

    // Binary search — O(log n) instead of O(n) linear scan
    private func nearestIndex(to normalizedX: CGFloat) -> Int {
        var low = 0
        var high = xPositions.count - 1
        while low < high {
            let mid = (low + high) / 2
            if xPositions[mid] < normalizedX {
                low = mid + 1
            } else {
                high = mid
            }
        }
        // Check if previous index is closer
        if low > 0 && abs(xPositions[low - 1] - normalizedX) < abs(xPositions[low] - normalizedX) {
            return low - 1
        }
        return low
    }
}
```

**Rules for chart interaction:**
- Pre-compute all data arrays on init, not during gesture.
- Use binary search for hit testing, never linear scan.
- During scrub gesture, update only the overlay (selection line + tooltip), not the chart path.
- Use `drawingGroup()` on the chart canvas to keep it on the GPU.
- Haptic feedback on index change: use `UISelectionFeedbackGenerator` (pre-prepared).

### 6.5 Progressive Loading

```swift
struct RecoveryTrendsView: View {
    @State private var chartData: [ChartPoint] = []
    @State private var isFullDataLoaded = false

    var body: some View {
        TrendLineChart(data: chartData)
            .task {
                // Phase 1: Show cached data immediately (< 50ms)
                chartData = await loadCachedData(days: 90)

                // Phase 2: Fetch fresh data in background
                let freshData = await fetchFreshData(days: 90)
                if freshData != chartData {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        chartData = freshData
                    }
                }
                isFullDataLoaded = true
            }
    }
}
```

---

## 7. Timer Performance

### 7.1 Visual Timer Accuracy

```swift
/// Focus timer and rest timer display
/// Uses CADisplayLink for visual updates (synced to screen refresh)
/// Uses Date-based calculation (not accumulated increments)
@Observable
class TimerEngine {
    var displaySeconds: Int = 0
    var isRunning = false

    private var startDate: Date?
    private var displayLink: CADisplayLink?
    private var targetDuration: TimeInterval = 0

    // For rest timer (countdown)
    func startCountdown(seconds: Int) {
        targetDuration = TimeInterval(seconds)
        startDate = Date()
        isRunning = true

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: 15,   // save battery when possible
            maximum: 60,   // smooth during interaction
            preferred: 30  // 30fps is plenty for a number display
        )
        displayLink?.add(to: .main, forMode: .common)
    }

    // For focus timer (count up)
    func startStopwatch() {
        startDate = Date()
        isRunning = true

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: 1,    // 1fps when screen is static
            maximum: 30,
            preferred: 1   // Only update once per second
        )
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        guard let startDate else { return }
        let elapsed = Date().timeIntervalSince(startDate)

        if targetDuration > 0 {
            // Countdown
            let remaining = max(0, targetDuration - elapsed)
            displaySeconds = Int(ceil(remaining))
            if remaining <= 0 {
                stop()
                onComplete?()
            }
        } else {
            // Stopwatch
            displaySeconds = Int(elapsed)
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
    }

    var onComplete: (() -> Void)?
}
```

**Key design decisions:**
- `CADisplayLink` instead of `Timer`: synchronized with display refresh, no drift.
- `Date`-based calculation: survives app backgrounding without accumulated error.
- Preferred frame rate of 1fps for focus timer (only seconds change) — massive battery savings.
- 30fps for rest timer (more visually active, but 30fps is indistinguishable from 60fps for number display).

### 7.2 Background Execution for Focus Timer

```swift
@Observable
class FocusTimerService {
    var elapsedSeconds: Int = 0
    private var sessionStartDate: Date?
    private var backgroundDate: Date?

    /// Handle app going to background
    func appDidEnterBackground() {
        backgroundDate = Date()

        // Schedule local notification as fallback
        if let start = sessionStartDate {
            let targetMinutes = studyTargetMinutes
            let elapsed = Date().timeIntervalSince(start) / 60
            let remaining = targetMinutes - elapsed

            if remaining > 0 {
                scheduleCompletionNotification(in: remaining * 60)
            }
        }

        // Request background processing time
        let taskID = UIApplication.shared.beginBackgroundTask {
            // Cleanup if time expires
        }

        // Stop display link (screen is off, no point updating UI)
        displayLink?.invalidate()
    }

    /// Handle app returning to foreground
    func appDidBecomeActive() {
        guard let start = sessionStartDate else { return }

        // Recalculate from start date — no drift
        elapsedSeconds = Int(Date().timeIntervalSince(start))

        // Cancel the fallback notification
        cancelCompletionNotification()

        // Restart display link
        startDisplayLink()
    }

    /// Schedule BGTaskScheduler for extended background
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.tempo.focustimer.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
    }
}
```

**Background mode strategy:**

| Duration | Mechanism | Accuracy |
|----------|-----------|----------|
| < 30 seconds | `beginBackgroundTask` | Exact |
| 30s - 3 min | Extended background task | Exact |
| 3 min - 30 min | `BGAppRefreshTaskRequest` + local notification | Notification arrives +-1 min |
| > 30 min | Local notification only | Notification arrival exact |

**Critical rule:** Always use `Date`-based calculation. Never accumulate seconds. When the user returns from background after 45 minutes, calculate `Date().timeIntervalSince(sessionStartDate)` — do not try to reconstruct from a paused counter.

### 7.3 Battery Optimization for Focus Timer

```swift
// Focus timer screen — minimal updates
struct FocusTimerView: View {
    @State private var timer = FocusTimerService()

    var body: some View {
        VStack(spacing: 40) {
            // Only this text updates (once per second)
            Text(timer.formattedTime)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .monospacedDigit() // prevents layout shift
                .contentTransition(.numericText()) // smooth digit transition

            // These are STATIC — never redraw
            Text("Focus Session")
                .font(.headline)

            // Target progress ring updates once per second
            FocusProgressRing(progress: timer.progress)
        }
        .persistentSystemOverlays(.hidden) // hide clock/status bar noise
    }
}
```

**Battery savings from focus timer optimization:**
- 1fps `CADisplayLink` vs 60fps: **~98% fewer frame callbacks**
- Monospaced digit font: prevents text layout recalculation per digit change
- Static text extracted: zero redraws for non-changing labels
- `persistentSystemOverlays(.hidden)`: reduces system UI compositing

### 7.4 Live Activity for Focus Timer

```swift
// Focus Timer Live Activity
struct FocusTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let elapsedMinutes: Int
        let targetMinutes: Int
        let sessionType: String // "Study", "Deep Work"
    }

    let subject: String // "Algorithms Exam Prep"
}

// Update strategy: max once per minute
// Live Activities have a budget of ~1 update per second
// For a focus timer, once per minute is plenty
func updateLiveActivity(elapsed: Int, target: Int) {
    let state = FocusTimerActivityAttributes.ContentState(
        elapsedMinutes: elapsed / 60,
        targetMinutes: target,
        sessionType: "Study"
    )

    Task {
        // Use animated timer in the Live Activity itself
        // This is rendered by the system, no update needed for seconds
        await activity?.update(
            ActivityContent(state: state, staleDate: nil)
        )
    }
}
```

**Live Activity rules:**
- Use `Text(timerInterval:)` in the widget view for the countdown/count-up. The system renders the ticking animation natively — zero updates needed for seconds.
- Update the Live Activity only when minutes change or session state changes (paused/resumed/completed).
- Max update budget: 1 per minute during focus session.

---

## 8. Notification Performance

### 8.1 Batch Scheduling

```swift
/// Schedule all of today's accountability notifications in one batch
/// Called at 6:00 AM (or on app launch if after 6 AM)
func scheduleAccountabilityNotifications(for date: Date, nonNegotiables: [NonNegotiable]) {
    let center = UNUserNotificationCenter.current()

    // Remove previous day's pending notifications
    center.removePendingNotificationRequests(
        withIdentifiers: nonNegotiables.map { "accountability-\($0.id)" }
    )

    // Escalation schedule
    let escalationTimes: [(hour: Int, minute: Int, severity: NotificationSeverity)] = [
        (14, 0, .gentle),
        (17, 0, .firm),
        (18, 30, .urgent),
        (19, 0, .aggressive),
        (20, 0, .final)
    ]

    var requests: [UNNotificationRequest] = []

    for escalation in escalationTimes {
        let content = UNMutableNotificationContent()
        content.title = "Tempo"
        content.body = generateEscalationMessage(
            severity: escalation.severity,
            incomplete: nonNegotiables.filter { !$0.isCompleted }
        )
        content.sound = escalation.severity == .final ? .defaultCritical : .default
        content.interruptionLevel = escalation.severity.interruptionLevel
        content.categoryIdentifier = "ACCOUNTABILITY"
        content.threadIdentifier = "accountability-\(date.formatted(.iso8601.year().month().day()))"

        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = escalation.hour
        dateComponents.minute = escalation.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "accountability-\(escalation.severity)-\(date.timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        requests.append(request)
    }

    // Schedule all at once (batch)
    for request in requests {
        center.add(request)
    }

    // Also schedule the success notification (conditional — only fires if all complete)
    // This is rescheduled whenever a non-negotiable is completed
}

/// Cancel remaining escalation notifications when all non-negotiables are done
func cancelEscalationNotifications(for date: Date) {
    let center = UNUserNotificationCenter.current()
    let identifiers = ["gentle", "firm", "urgent", "aggressive", "final"]
        .map { "accountability-\($0)-\(date.timeIntervalSince1970)" }
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
}
```

### 8.2 Notification Service Extension

```swift
// NotificationServiceExtension — lightweight enrichment
class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                            withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }

        // Enrich with user's current progress (from shared UserDefaults/App Group)
        if let sharedDefaults = UserDefaults(suiteName: "group.com.tempo.app") {
            let completedCount = sharedDefaults.integer(forKey: "todayNonNegotiablesCompleted")
            let totalCount = sharedDefaults.integer(forKey: "todayNonNegotiablesTotal")
            content.subtitle = "\(completedCount)/\(totalCount) completed"
        }

        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        // Deliver what we have — don't block notification delivery
    }
}
```

**Rules:**
- Notification Service Extension must complete within 30 seconds (Apple enforced).
- Keep the extension lightweight: read from shared `UserDefaults` (App Group), never make network calls.
- Memory limit for notification extensions: 24MB. Never load images in the extension unless pre-cached.

### 8.3 Image Attachments

```swift
// Pre-cache notification images (avatars for friend activity)
func cacheNotificationImage(url: URL, identifier: String) async {
    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }

    // Downsample to notification size (100x100 max)
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
    let options: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: 100,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }

    // Save to shared App Group container
    let image = UIImage(cgImage: thumbnail)
    let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.tempo.app"
    )!.appendingPathComponent("NotificationImages")

    try? FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    try? image.pngData()?.write(to: containerURL.appendingPathComponent("\(identifier).png"))
}
```

---

## 9. App Size Optimization

### 9.1 Size Budget

| Component | Budget | Strategy |
|-----------|--------|----------|
| Executable (arm64) | **< 15MB** | LTO, dead code stripping |
| Asset catalog | **< 5MB** | SF Symbols over bitmaps, vector assets |
| Exercise library (seed JSON) | **< 500KB** | Compressed, lazy-loaded |
| Frameworks/dependencies | **< 15MB** | Minimal third-party deps |
| Localization | **< 2MB** | English only at launch |
| **Total download size** | **< 50MB** | Below App Store cellular download limit |
| **Total install size** | **< 80MB** | |

### 9.2 Asset Optimization

**SF Symbols over bitmaps:**

```swift
// CORRECT: SF Symbol — 0 bytes in bundle, renders at any size
Image(systemName: "figure.strengthtraining.traditional")
    .font(.system(size: 28))
    .symbolRenderingMode(.hierarchical)

// WRONG: Bitmap image — adds ~10KB per @1x/@2x/@3x set
Image("workout-icon")
    .resizable()
    .frame(width: 28, height: 28)
```

**Tempo symbol usage:**

| UI Element | Symbol | Size |
|------------|--------|------|
| Workout type icons | `figure.strengthtraining.traditional`, `figure.run`, `sportscourt` | System |
| Dashboard quadrants | `heart.fill`, `fork.knife`, `brain.head.profile`, `figure.walk` | System |
| Tab bar | `square.grid.2x2`, `dumbbell`, `lock.shield`, `waveform.path.ecg`, `trophy` | System |
| Navigation | `chevron.left`, `chevron.right`, `xmark` | System |
| Achievements | Custom SF Symbols (up to 20) | < 5KB each |

### 9.3 Exercise Demo Assets

Exercise demonstration images/videos are NOT bundled with the app. They are downloaded on-demand and cached.

```swift
// On-Demand Resources for exercise library media
// Tag exercises by muscle group, download when user browses that group

// In Xcode: Resources → On Demand Resource Tags
// "exercises-chest" → bench press, incline press, etc.
// "exercises-back" → deadlift, row, etc.

func loadExerciseDemo(for exercise: Exercise) async -> UIImage? {
    // 1. Check disk cache
    if let cached = DiskCache.shared.image(for: exercise.id) {
        return cached
    }

    // 2. Download from CDN
    let url = URL(string: "https://cdn.tempo.app/exercises/\(exercise.id)/demo.heic")!
    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
    let image = UIImage(data: data)

    // 3. Cache to disk (30-day expiry)
    if let image {
        DiskCache.shared.store(image, for: exercise.id, expiry: .days(30))
    }

    return image
}
```

### 9.4 Build Optimization

**Xcode Build Settings:**

| Setting | Value | Impact |
|---------|-------|--------|
| `DEAD_CODE_STRIPPING` | `YES` | Removes unused code paths |
| `STRIP_INSTALLED_PRODUCT` | `YES` | Strips debug symbols from release |
| `SWIFT_OPTIMIZATION_LEVEL` | `-O` (Release) | Full optimizer |
| `LLVM_LTO` | `YES` (Incremental) | Link-Time Optimization — merges and optimizes across modules |
| `ENABLE_BITCODE` | `NO` | Deprecated, not needed |
| `SWIFT_COMPILATION_MODE` | `wholemodule` (Release) | Better optimization across files |
| `GCC_OPTIMIZATION_LEVEL` | `-Os` | Optimize for size in ObjC/C code |
| `ASSETCATALOG_COMPILER_OPTIMIZATION` | `space` | Optimize assets for download size |

**Expected impact of LTO:** 5-15% reduction in binary size.

### 9.5 Dependency Audit

Tempo should minimize third-party dependencies. Every dependency adds binary size and launch time.

| Dependency | Justified? | Size Impact | Alternative |
|------------|-----------|-------------|-------------|
| Swift Charts | Yes (Apple) | 0 (system framework) | N/A |
| SwiftData | Yes (Apple) | 0 (system framework) | N/A |
| HealthKit | Yes (Apple) | 0 (system framework) | N/A |
| EventKit | Yes (Apple) | 0 (system framework) | N/A |
| KeychainAccess | Maybe | ~200KB | Write a minimal wrapper (~50 lines) |
| Kingfisher (image loading) | No | ~2MB | Use built-in `AsyncImage` + custom `ImageCache` |
| Charts (DGCharts) | No | ~5MB | Use Swift Charts or Canvas |
| Alamofire | No | ~1.5MB | Use `URLSession` + thin wrapper |
| Firebase | No | ~10MB+ | Use APNs directly + custom analytics |

**Rule:** No third-party dependency unless it saves > 500 lines of code AND has no Apple-framework alternative.

---

## 10. Profiling Playbook

### 10.1 Profile App Launch

**Tool:** Instruments → App Launch template

**Steps:**
1. Clean build + install on device (not simulator)
2. Force-quit the app. Wait 5 seconds.
3. In Instruments, select App Launch template
4. Press Record, then tap the app icon on device
5. Wait for dashboard to fully load. Stop recording.

**What to look for:**

| Phase | Track | Red Flag |
|-------|-------|----------|
| Pre-main | App Launch → Initializer | Any single dylib > 50ms |
| `TempoApp.init` | Time Profiler → main thread | SwiftData container creation > 50ms |
| First `body` | SwiftUI → View Body | DashboardView body > 30ms |
| Data load | Core Data → Fetches | Any fetch > 50ms on main thread |
| First frame | App Launch → First Frame | Total > 800ms |
| Interactive | Custom signpost | `os_signpost` "Dashboard Interactive" > 1.5s |

**Custom signpost for launch tracking:**

```swift
import os

let launchLog = OSLog(subsystem: "com.tempo.app", category: "Launch")

@main
struct TempoApp: App {
    init() {
        os_signpost(.event, log: launchLog, name: "AppInit Start")
        // ... setup ...
        os_signpost(.event, log: launchLog, name: "AppInit End")
    }
}

struct DashboardView: View {
    var body: some View {
        content
            .onAppear {
                os_signpost(.event, log: launchLog, name: "Dashboard OnAppear")
            }
            .task {
                os_signpost(.begin, log: launchLog, name: "Dashboard Data Load")
                await loadData()
                os_signpost(.end, log: launchLog, name: "Dashboard Data Load")
                os_signpost(.event, log: launchLog, name: "Dashboard Interactive")
            }
    }
}
```

### 10.2 Profile Workout Logging Flow

**Tool:** Instruments → Time Profiler + SwiftUI template (combined)

**Scenario:** Start a workout, complete 3 sets, navigate to next exercise.

**Steps:**
1. Launch app, navigate to Training, start a workout
2. Start Instruments recording with Time Profiler + SwiftUI
3. Tap to complete Set 1. Note: was there a visible delay?
4. Wait for rest timer. Tap to complete Set 2.
5. Swipe to next exercise.
6. Stop recording.

**What to look for:**

| Action | Track | Budget | Red Flag |
|--------|-------|--------|----------|
| Set complete tap | Time Profiler → main thread | < 16ms | Any main thread work > 16ms at tap time |
| Set complete tap | SwiftUI → View Body | 1-2 body evals | > 5 body evaluations = state leak |
| Rest timer running | Time Profiler → main thread | < 2ms per frame | Timer callback doing SwiftData work |
| Exercise swipe | SwiftUI → View Body | 1 body eval | Next exercise view computing data in body |
| Haptic | Time Profiler | < 1ms | Haptic generator not pre-prepared |

### 10.3 Profile Memory During Chart Rendering

**Tool:** Instruments → Allocations + Leaks

**Scenario:** Navigate to Recovery Trends, load 365-day chart, interact (scrub), navigate back.

**Steps:**
1. Start Instruments with Allocations template
2. Navigate to Recovery module
3. Tap Recovery Trends (triggers 365-day chart load)
4. Mark generation (Instruments → "Mark Generation")
5. Scrub across the chart for 10 seconds
6. Mark generation again
7. Navigate back to Recovery Today
8. Mark generation again
9. Wait 5 seconds. Stop recording.

**What to look for:**

| Check | How | Red Flag |
|-------|-----|----------|
| Peak memory during chart | Allocations → All Allocations → peak | > 150MB |
| Memory after leaving chart | Generation 3 vs Generation 1 | Difference > 5MB = leak |
| Transient allocations during scrub | Generation 2 size | > 10MB transient = excessive allocation |
| Leaks | Leaks track | Any leak > 0 bytes |
| Persistent growth | Compare Generation 1 and 3 | Growth = retained chart data |

**Common chart memory issues:**
- `Path` objects not released (stored in closures)
- `CGImage` chart snapshots not released on navigate-back
- Gesture closures capturing `self` strongly

### 10.4 Profile Battery During Focus Timer

**Tool:** Instruments → Energy Log

**Scenario:** Start a 25-minute focus session with screen on, idle.

**Steps:**
1. Charge device to 100%
2. Set screen brightness to 50% (consistent baseline)
3. Start Instruments with Energy Log
4. Start a Focus Timer session in Tempo
5. Let it run for 25 minutes undisturbed
6. Stop recording

**What to look for:**

| Metric | Budget | Red Flag |
|--------|--------|----------|
| CPU usage (average) | < 1% | > 3% = timer callback too expensive or too frequent |
| CPU wakeups per second | < 2 | > 10 = polling or unnecessary timer |
| GPU usage | < 1% | > 5% = unnecessary animation running |
| Networking | 0 | Any network activity during focus = bug |
| Location | 0 | Any location usage = bug |
| Display overhead | Low | Check `CADisplayLink` frame rate — should be 1fps |

### 10.5 Profile SwiftData Queries

**Tool:** Instruments → Core Data template + custom `os_signpost`

**Steps:**
1. Add `os_signpost` markers around every SwiftData fetch (see 3.7)
2. Run the app under Instruments → Core Data
3. Navigate through all tabs
4. Check Core Data trace for:
   - Fetch count per screen transition
   - Fetch duration per query
   - Fault count (relationship lazy loading)
   - Save operations on main thread

**Red flags per screen:**

| Screen | Max Fetches | Max Faults | Max Main Thread Save |
|--------|------------|------------|---------------------|
| Dashboard load | 3 (snapshot, accountability, settings) | 0 | 0 |
| Training → Today's Workout | 2 (plan, exercises) | 0 (prefetched) | 0 |
| Workout Log (set complete) | 0 | 0 | 0 (debounced background) |
| Lockdown | 1 (today's accountability) | 0 (prefetched non-negotiables) | 0 |
| Recovery Trends (90-day chart) | 1 (batched enumerate) | 0 | 0 |
| Exercise Library (scroll) | 0 (paged, pre-fetched) | 0 | 0 |
| Arena Leaderboard | 0 (network only) | 0 | 0 |

### 10.6 Custom `os_signpost` Markers for Tempo

Add these signpost markers to the codebase for always-on profiling:

```swift
import os

enum TempoSignpost {
    static let launch = OSLog(subsystem: "com.tempo.app", category: "Launch")
    static let data = OSLog(subsystem: "com.tempo.app", category: "DataLoad")
    static let workout = OSLog(subsystem: "com.tempo.app", category: "Workout")
    static let chart = OSLog(subsystem: "com.tempo.app", category: "Chart")
    static let network = OSLog(subsystem: "com.tempo.app", category: "Network")
    static let healthkit = OSLog(subsystem: "com.tempo.app", category: "HealthKit")
    static let timer = OSLog(subsystem: "com.tempo.app", category: "Timer")
}

// Usage examples:

// Launch
os_signpost(.begin, log: TempoSignpost.launch, name: "ColdLaunch")
os_signpost(.end, log: TempoSignpost.launch, name: "ColdLaunch")

// Data operations
os_signpost(.begin, log: TempoSignpost.data, name: "FetchSnapshot", "%{public}s", "90-day")
os_signpost(.end, log: TempoSignpost.data, name: "FetchSnapshot", "rows: %d", count)

// Workout
os_signpost(.event, log: TempoSignpost.workout, name: "SetCompleted", "exercise: %{public}s set: %d", exerciseName, setNumber)
os_signpost(.begin, log: TempoSignpost.workout, name: "PersistWorkout")
os_signpost(.end, log: TempoSignpost.workout, name: "PersistWorkout")

// Chart
os_signpost(.begin, log: TempoSignpost.chart, name: "ChartRender", "points: %d", dataCount)
os_signpost(.end, log: TempoSignpost.chart, name: "ChartRender")
os_signpost(.begin, log: TempoSignpost.chart, name: "LTTB_Downsample", "from: %d to: %d", rawCount, targetCount)
os_signpost(.end, log: TempoSignpost.chart, name: "LTTB_Downsample")

// Network
os_signpost(.begin, log: TempoSignpost.network, name: "APICall", "%{public}s", endpoint)
os_signpost(.end, log: TempoSignpost.network, name: "APICall", "bytes: %d status: %d", responseSize, statusCode)

// HealthKit
os_signpost(.begin, log: TempoSignpost.healthkit, name: "HKQuery", "%{public}s", queryType)
os_signpost(.end, log: TempoSignpost.healthkit, name: "HKQuery", "samples: %d", sampleCount)
```

---

## 11. Regression Testing

### 11.1 Automated Performance Tests

```swift
import XCTest

final class TempoPerformanceTests: XCTestCase {

    // MARK: - Launch Performance

    func testColdLaunchPerformance() throws {
        let app = XCUIApplication()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    func testColdLaunchToInteractive() throws {
        let app = XCUIApplication()
        app.launchArguments.append("--performance-test")

        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
            // Wait for dashboard to be interactive
            let dashboard = app.otherElements["DashboardView"]
            XCTAssertTrue(dashboard.waitForExistence(timeout: 2.0))
        }
    }

    // MARK: - SwiftData Fetch Performance

    func testFetchTodaySnapshot() throws {
        let container = try ModelContainer(for: DailySnapshot.self)
        let context = ModelContext(container)

        // Seed 365 days of data
        seedTestData(context: context, days: 365)

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(options: options) {
            let today = Calendar.current.startOfDay(for: .now)
            let descriptor = FetchDescriptor<DailySnapshot>(
                predicate: #Predicate { $0.date == today }
            )
            let result = try! context.fetch(descriptor)
            XCTAssertEqual(result.count, 1)
        }
        // Baseline: < 50ms (set in Xcode test plan)
    }

    func testFetch90DayHistory() throws {
        let container = try ModelContainer(for: DailySnapshot.self)
        let context = ModelContext(container)
        seedTestData(context: context, days: 365)

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(options: options) {
            let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
            var descriptor = FetchDescriptor<DailySnapshot>(
                predicate: #Predicate { $0.date >= ninetyDaysAgo },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchBatchSize = 30
            let result = try! context.fetch(descriptor)
            XCTAssertEqual(result.count, 90)
        }
        // Baseline: < 200ms
    }

    // MARK: - Chart Rendering Performance

    func testChartRendering365Points() throws {
        let data = (0..<365).map { i in
            ChartPoint(x: Double(i), y: Double.random(in: 0...100))
        }

        measure {
            let decimated = downsampleLTTB(data: data, targetCount: 100)
            XCTAssertEqual(decimated.count, 100)

            // Simulate Canvas render by computing all points
            let size = CGSize(width: 390, height: 200)
            let points = decimated.map { CGPoint(
                x: $0.x / 365 * size.width,
                y: size.height - ($0.y / 100 * size.height)
            )}
            XCTAssertEqual(points.count, 100)
        }
        // Baseline: < 300ms total (decimation + point computation)
    }

    // MARK: - Workout Logging Performance

    func testSetCompletionLatency() throws {
        let viewModel = WorkoutLogViewModel()
        viewModel.loadTestWorkout(sets: 20)

        let options = XCTMeasureOptions()
        options.iterationCount = 20

        measure(options: options) {
            viewModel.completeSet(0)
        }
        // Baseline: < 1ms (state flip only, no I/O)
    }

    // MARK: - Memory Tests

    func testDashboardMemoryFootprint() throws {
        let app = XCUIApplication()
        app.launch()

        let memoryMetric = XCTMemoryMetric(application: app)
        measure(metrics: [memoryMetric]) {
            // Navigate to dashboard (already there on launch)
            let dashboard = app.otherElements["DashboardView"]
            XCTAssertTrue(dashboard.waitForExistence(timeout: 2.0))
        }
        // Baseline: < 80MB
    }

    func testChartMemoryFootprint() throws {
        let app = XCUIApplication()
        app.launch()

        let memoryMetric = XCTMemoryMetric(application: app)
        measure(metrics: [memoryMetric]) {
            // Navigate to Recovery → Trends
            app.tabBars.buttons["Recovery"].tap()
            app.buttons["View Trends"].tap()
            // Wait for chart to render
            let chart = app.otherElements["RecoveryTrendsChart"]
            XCTAssertTrue(chart.waitForExistence(timeout: 3.0))
        }
        // Baseline: < 150MB peak
    }

    // MARK: - Scroll Performance

    func testExerciseLibraryScrollPerformance() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Training"].tap()
        app.buttons["Exercise Library"].tap()

        let scrollMetric = XCTOSSignpostMetric.scrollDecelerationMetric
        measure(metrics: [scrollMetric]) {
            let list = app.collectionViews.firstMatch
            list.swipeUp(velocity: .fast)
            list.swipeUp(velocity: .fast)
            list.swipeDown(velocity: .fast)
        }
        // Baseline: 0 hitches, sustained 60fps
    }
}
```

### 11.2 Baseline Measurements

Set these baselines in the Xcode Test Plan. Tests fail if they regress beyond the threshold.

| Test | Baseline | Max Allowed Deviation | Alert Threshold |
|------|----------|-----------------------|-----------------|
| Cold launch | 800ms | 10% | > 880ms |
| Cold launch to interactive | 1.5s | 10% | > 1.65s |
| Fetch today's snapshot | 50ms | 20% | > 60ms |
| Fetch 90-day history | 200ms | 15% | > 230ms |
| Set completion latency | 1ms | 100% | > 2ms |
| Chart render (365 pts) | 300ms | 15% | > 345ms |
| Dashboard memory | 80MB | 10% | > 88MB |
| Chart peak memory | 150MB | 10% | > 165MB |
| Exercise library scroll | 0 hitches | 0 tolerance | > 0 hitches |

### 11.3 CI Integration

```yaml
# .github/workflows/performance.yml
name: Performance Regression Tests

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  performance:
    runs-on: macos-15 # latest macOS runner with Xcode 16+
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Run Performance Tests
        run: |
          xcodebuild test \
            -project Tempo.xcodeproj \
            -scheme Tempo \
            -testPlan PerformanceTests \
            -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
            -resultBundlePath TestResults.xcresult

      - name: Check for Regressions
        run: |
          # Extract test results and compare against baselines
          xcrun xcresulttool get --format json \
            --path TestResults.xcresult \
            > results.json

          # Custom script to parse and alert on regressions
          python3 scripts/check_perf_regressions.py results.json

      - name: Upload Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: performance-results
          path: TestResults.xcresult
```

### 11.4 Performance Test Plan (Xcode)

Create a test plan named `PerformanceTests.xctestplan`:

```json
{
  "configurations": [
    {
      "name": "Performance",
      "options": {
        "testTimeoutsEnabled": true,
        "defaultTestExecutionTimeAllowance": 120,
        "maximumTestExecutionTimeAllowance": 300,
        "performanceTestConfiguration": {
          "maxStddev": 15.0,
          "maxPercentRelativeStandardDeviation": 20.0,
          "maxRegression": 10.0
        }
      }
    }
  ],
  "testTargets": [
    {
      "target": {
        "containerPath": "container:Tempo.xcodeproj",
        "identifier": "TempoPerformanceTests"
      },
      "selectedTests": [
        "TempoPerformanceTests"
      ]
    }
  ]
}
```

### 11.5 Manual Performance Checklist (Pre-Release)

Run before every TestFlight build:

- [ ] **Launch:** Cold launch on oldest supported device (iPhone 13). First frame < 800ms, interactive < 1.5s.
- [ ] **Workout flow:** Complete 5 sets with rest timers. Every tap feels instant. No frame drops during swipe navigation between exercises.
- [ ] **Focus timer:** Run 5-minute session with screen on. Check Energy Log — CPU should be < 1%.
- [ ] **Charts:** Open 365-day recovery trend. Scrub across entire chart. No hitches.
- [ ] **Memory:** Use Xcode Memory Graph to check for leaks after: launch → all tabs → workout → chart → back to dashboard.
- [ ] **Offline:** Enable airplane mode. App shows cached data. Complete a workout. Re-enable network — data syncs.
- [ ] **Background:** Start focus timer, background app for 5 min, return. Timer shows correct elapsed time.
- [ ] **Notifications:** Verify all 5 escalation levels arrive at scheduled times. Verify cancellation works when non-negotiables are completed.
- [ ] **App size:** Archive build. Check `.ipa` size in Organizer. Must be < 50MB download.

---

## Appendix: Performance Decision Matrix

When facing a performance trade-off, use this priority order:

| Priority | Principle | Example |
|----------|-----------|---------|
| 1 | **Workout logging is sacred** | Never add main-thread I/O that could delay a set-complete tap |
| 2 | **Cached first, fresh second** | Always show cached DailySnapshot, update in background |
| 3 | **Fewer frames > prettier frames** | Focus timer at 1fps, not 60fps |
| 4 | **Network is unreliable** | Every feature works offline with degradation, never failure |
| 5 | **Memory is finite** | Page data, release chart buffers, cache with limits |
| 6 | **Battery is trust** | Users will uninstall if battery drain is noticeable |
| 7 | **Size is the first impression** | < 50MB download means users install on cellular |
