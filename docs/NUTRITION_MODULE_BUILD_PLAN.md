# Native Nutrition Module — Build Plan

> **Version:** 1.0.0
> **Created:** 2026-03-25
> **Author:** Build Engineering
> **Purpose:** Complete build plan for replacing NutriTrack (external Flask dependency) with a native, local-first nutrition module inside the Tempo iOS app. Each step is self-contained, dependency-ordered, and executable without asking questions.
> **Invariant:** If step NX.Y needs something, that something was built in a prior step or already exists in the codebase. No exceptions.

---

## Overview

Tempo currently relies on NutriTrack — a self-hosted Flask app — for all nutrition data. This is a hard dependency on an external server that the user must run themselves, which is a non-starter for public App Store release. This build plan replaces NutriTrack with a fully native nutrition module: local-first SwiftData models, USDA FoodData Central + OpenFoodFacts for food search, VisionKit barcode scanning, Claude Vision for photo-based meal logging, and AI coaching via Claude Haiku/Sonnet. The module integrates with HealthKit for nutrition writes, the Dashboard fuel quadrant, the Arena XP system, and the accountability non-negotiables.

**Architectural approach:** Local-first. All meal data lives in SwiftData. Food databases are queried via REST (USDA, OpenFoodFacts) and cached locally. AI features (photo analysis, coaching) call the Tempo backend which proxies to Claude API. No external Flask server required. NutriTrack remains as an optional import path in Settings for existing users.

---

## How to Use This Plan

1. **Work sequentially within each phase.** Steps within a phase are ordered by dependency.
2. **Parallelizable phases are marked in the Dependency Graph** at the end of this document.
3. **Each step is 1-3 hours.** If it takes longer, something is wrong — re-read the referenced docs.
4. **Acceptance criteria are binary.** Either the criteria is met or it is not. No "mostly done."
5. **File paths are relative to the project root** (`Tempo/Tempo/` for iOS app code).
6. **Existing code:** Phases N1 and parts of N2/N3 have partial implementations. Each step notes what exists and what needs to change.

---

## Architecture Summary

```
┌──────────────────────────────────────────────────────────┐
│                NATIVE NUTRITION MODULE                     │
│                                                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │ MealLogging │  │  FoodSearch  │  │   Photo     │      │
│  │    View     │  │    View      │  │  Analysis   │      │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘      │
│         │                │                 │              │
│  ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐      │
│  │MealLogging  │  │ FoodSearch  │  │  Photo      │      │
│  │  Service    │  │  Service    │  │  Analysis   │      │
│  │             │  │(USDA + OFF) │  │  Service    │      │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘      │
│         │                │                 │              │
│  ┌──────┴────────────────┴─────────────────┴──────┐      │
│  │           SwiftData (Local-First)               │      │
│  │  MealLog │ MealFoodItem │ CachedFood │ Target  │      │
│  └────────────────────────┬───────────────────────┘      │
│                           │                               │
│  ┌────────────────────────┴───────────────────────┐      │
│  │              Integration Layer                   │      │
│  │  HealthKit Writes │ Dashboard │ Arena XP │ Notif │      │
│  └──────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
         │ HTTPS (AI features only)
         ▼
┌──────────────────────┐
│   Tempo Backend      │
│   Claude API Proxy   │
│  (Haiku + Sonnet)    │
└──────────────────────┘
```

**Data layer:** SwiftData models — `MealLog`, `MealFoodItem`, `NutritionTarget`, `CachedFood` (already created in Phase N1)
**Service layer:** `FoodSearchService` (USDA + OFF), `MealLoggingService`, `PhotoAnalysisService`, `NutritionCoachService`
**UI layer:** `MealLoggingView`, `FoodSearchView`, `PhotoAnalysisView`, `BarcodeScannerView`, `DailyNutritionSummaryView`, `NutritionTargetSetupView`
**AI layer:** Claude Haiku (real-time meal feedback, daily summary), Claude Sonnet (photo analysis, weekly review)
**Integration:** HealthKit nutrition writes, Dashboard fuel quadrant, Arena XP actions, Accountability meal tracking

---

## Phase N1: Data Models & Schema (2-3 hours)

**Prerequisites:** Phase 0 and Phase 1 of main build plan (project scaffolding, existing models)
**Docs to reference:** `docs/DATA_MODELS_IOS.md`, `docs/MODULE_DASHBOARD.md` Section 2 (FuelQuadrantData)

> **Status:** All 5 files in this phase already exist and are registered in `TempoSchemaV1`. Review for completeness against this spec and fix any gaps.

---

### N1.1 Create/Verify NutritionEnums.swift

**Time estimate:** 30 minutes
**Prerequisites:** None (existing file)
**Docs:** `docs/DATA_MODELS_IOS.md` Section 2 (Enums)
**Existing file:** `Tempo/Tempo/Models/Nutrition/NutritionEnums.swift`
**What to verify/build:**
The file already contains `MealType`, `MealSource`, `FoodDataSource`, and `NutritionCoachingTrigger`. Verify:
1. `MealType` has `sortOrder` computed property and `icon` (SF Symbols) — both exist.
2. `MealSource` includes `.photo`, `.barcode`, `.manual`, `.voice`, `.imported` — exists.
3. `FoodDataSource` includes `.usda`, `.openFoodFacts`, `.claude`, `.manual` — exists.
4. `NutritionCoachingTrigger` covers all coaching events — exists.
5. **Add if missing:** `PortionUnit` enum for portion sizing:
   ```swift
   enum PortionUnit: String, Codable, CaseIterable, Sendable {
       case grams, ounces, cups, tablespoons, teaspoons, pieces, slices, servings
       var abbreviation: String { ... }
       var gramsMultiplier: Double { ... } // approximate conversion to grams
   }
   ```

**Acceptance criteria:**
- All enums compile under strict concurrency
- Every enum conforms to `String, Codable, Sendable`
- `MealType.allCases` returns 4 cases in correct sort order
- `PortionUnit` exists with gram conversion factors

**Files created/modified:**
- `Tempo/Tempo/Models/Nutrition/NutritionEnums.swift` (modified — add `PortionUnit`)

---

### N1.2 Verify MealLog + MealFoodItem Models

**Time estimate:** 30 minutes
**Prerequisites:** N1.1
**Docs:** `docs/DATA_MODELS_IOS.md`, `docs/MODULE_DASHBOARD.md` Section 2.2 (FuelQuadrantData)
**Existing files:** `Tempo/Tempo/Models/Nutrition/MealLog.swift`, `Tempo/Tempo/Models/Nutrition/MealFoodItem.swift`
**What to verify:**
Both models exist with full implementations. The `MealLog` has:
- `@Attribute(.unique) var id: UUID`
- `mealTypeRaw`, `loggedAt`, `photoData`, macro totals, `dayDate`, `syncedToHealthKit`, `syncedToBackend`
- `@Relationship(deleteRule: .cascade, inverse: \MealFoodItem.mealLog) var items`
- Computed properties: `mealType`, `source`, `orderedItems`, `formattedTime`, `formattedCalories`
- Full DTO with `toDTO()` method

The `MealFoodItem` has:
- Per-serving macros, quantity multiplier, computed totals
- `@Relationship(deleteRule: .nullify) var mealLog: MealLog?`
- Full DTO

**Verify no conflicts** with the duplicate `MealLog`/`MealFoodItem` definitions in `MealLoggingService.swift` (the service file at `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift` also contains `@Model` class definitions — these must be deduplicated). The canonical models are in `Tempo/Tempo/Models/Nutrition/`. Remove duplicate definitions from service files.

**Acceptance criteria:**
- Only ONE `MealLog` `@Model` definition exists (in `Models/Nutrition/MealLog.swift`)
- Only ONE `MealFoodItem` `@Model` definition exists (in `Models/Nutrition/MealFoodItem.swift`)
- `MealLoggingService.swift` references the model from `Models/Nutrition/`, does not redefine it
- Cascade delete works: deleting a `MealLog` deletes its `MealFoodItem`s
- Both DTO extensions produce valid Codable output

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift` (remove duplicate model definitions)

---

### N1.3 Verify NutritionTarget Model

**Time estimate:** 15 minutes
**Prerequisites:** N1.1
**Existing file:** `Tempo/Tempo/Models/Nutrition/NutritionTarget.swift`
**What to verify:**
Model exists with `calorieTarget`, `proteinTargetGrams`, `carbsTargetGrams`, `fatTargetGrams`, `mealsPerDay`, `effectiveFrom`, `isActive`. Computed properties for macro percentages and macro-calorie matching. Full DTO.

**Acceptance criteria:**
- `NutritionTarget` compiles under strict concurrency
- `macrosMatchCalories` returns `true` when macro-derived calories are within 50 kcal of `calorieTarget`
- `isActive` allows only one active target at a time (enforced at service layer, not model layer)

**Files:** No changes needed if model matches spec.

---

### N1.4 Verify CachedFood Model

**Time estimate:** 15 minutes
**Prerequisites:** N1.1
**Existing files:** `Tempo/Tempo/Models/Nutrition/CachedFood.swift`, also duplicate in `Tempo/Tempo/Services/Nutrition/FoodSearchService.swift`
**What to verify:**
There are TWO `CachedFood` `@Model` definitions — one in `Models/Nutrition/CachedFood.swift` (comprehensive, per-100g macros, barcode, USDA FDC ID, OFF product code, `toMealFoodItem()` conversion) and one in `FoodSearchService.swift` (simpler, per-serving macros, `useCount`). **These must be deduplicated.**

**Action:** Keep the `Models/Nutrition/CachedFood.swift` version as canonical (it is more comprehensive). Merge the `useCount` field from the service version into the canonical model. Update `FoodSearchService.swift` to import from `Models/Nutrition/` and remove its local `CachedFood` definition.

**Acceptance criteria:**
- Only ONE `CachedFood` `@Model` definition exists (in `Models/Nutrition/CachedFood.swift`)
- `CachedFood` includes `useCount: Int` for frequency-based sorting
- `FoodSearchService` references the canonical `CachedFood`
- `CachedFood.toMealFoodItem()` produces a valid `MealFoodItem`
- `searchKeywords` supports local search

**Files modified:**
- `Tempo/Tempo/Models/Nutrition/CachedFood.swift` (add `useCount` field if not present)
- `Tempo/Tempo/Services/Nutrition/FoodSearchService.swift` (remove duplicate `CachedFood` definition)

---

### N1.5 Verify TempoModelContainer Schema Registration

**Time estimate:** 15 minutes
**Prerequisites:** N1.2, N1.3, N1.4
**Existing file:** `Tempo/Tempo/Models/Schema/TempoSchemaV1.swift`
**What to verify:**
`TempoSchemaV1.models` already includes `MealLog.self`, `MealFoodItem.self`, `NutritionTarget.self`, `CachedFood.self` (confirmed — lines 35-38). No action needed unless model deduplication in N1.2/N1.4 causes compile issues.

**Acceptance criteria:**
- App launches on simulator without SwiftData crash
- All 4 nutrition models are in `TempoSchemaV1.models`
- No duplicate `@Model` classes cause ambiguity

**Files:** No changes needed if N1.2 and N1.4 deduplication is clean.

---

## Phase N2: Food Search Service (3-4 hours)

**Prerequisites:** Phase N1
**Docs to reference:** `docs/INTEGRATION_SPECS.md` Section 3 (NutriTrack — for understanding what we're replacing), `docs/DEPENDENCIES.md` (no new third-party deps)

> **Status:** `FoodSearchService.swift` and `NutritionDTOs.swift` already exist with USDA and OpenFoodFacts implementations. Review and fill gaps.

---

### N2.1 Verify/Refactor FoodSearchService Protocol + DTOs

**Time estimate:** 1 hour
**Prerequisites:** N1.4 (canonical `CachedFood`)
**Existing files:** `Tempo/Tempo/Services/Nutrition/FoodSearchService.swift`, `Tempo/Tempo/Services/Nutrition/NutritionDTOs.swift`
**What to verify/build:**
1. `NutritionDTOs.swift` contains `FoodSearchResult`, `MealFoodItemInput`, `DailyNutritionSummary`, `NutritionError`, USDA response types (`FdcSearchResponse`, `FdcFood`, `FdcFoodNutrient`), and OpenFoodFacts response types (`OFFProductResponse`, `OFFProduct`, `OFFNutriments`). **Verify there are no duplicate type definitions** across `NutritionDTOs.swift` and `NutritionEnums.swift` (the existing code has `MealType`, `MealSource`, `FoodDataSource` defined in BOTH files — deduplicate).
2. `FoodSearchServiceProtocol` already defines `searchUSDA`, `lookupBarcode`, `searchLocal`, `cacheFood`. **Add missing method:** `searchAll(query:context:) async throws -> [FoodSearchResult]` that combines local + USDA results with local results ranked first.

**Action:** Deduplicate enum definitions. Keep canonical versions in `NutritionEnums.swift`. Remove duplicates from `NutritionDTOs.swift`. Add `searchAll` convenience method.

**Acceptance criteria:**
- No duplicate type definitions across nutrition files
- `FoodSearchServiceProtocol` has `searchAll` method
- `FoodSearchResult` is `Sendable`, `Identifiable`, `Equatable`
- `NutritionError` covers all error cases: `foodNotFound`, `barcodeNotFound`, `searchFailed`, `rateLimited`, `networkError`, `photoAnalysisFailed`, `noFoodDetected`, `unclearPhoto`, `mealNotFound`, `healthKitWriteFailed`, `contextUnavailable`

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/NutritionDTOs.swift` (remove duplicate enums, add `searchAll` to protocol)
- `Tempo/Tempo/Services/Nutrition/FoodSearchService.swift` (implement `searchAll`)

---

### N2.2 Verify USDA FoodData Central API Integration

**Time estimate:** 30 minutes
**Prerequisites:** N2.1
**Existing file:** `Tempo/Tempo/Services/Nutrition/FoodSearchService.swift`
**What to verify:**
The USDA integration already exists with:
- API key from `Info.plist` with `DEMO_KEY` fallback
- `searchUSDA(query:)` hitting `https://api.nal.usda.gov/fdc/v1/foods/search`
- Rate limit handling (HTTP 429 with `Retry-After`)
- Response parsing via `FdcSearchResponse`
- `pageSize=25`, `dataType=Foundation,SR Legacy,Branded`

**Verify:** That `FdcFood.toFoodSearchResult()` correctly extracts calories, protein, carbs, fat from USDA's nutrient array (nutrient IDs: 1008=Energy, 1003=Protein, 1005=Carbs, 1004=Fat, 1079=Fiber, 2000=Sugars, 1093=Sodium).

**Acceptance criteria:**
- USDA search returns results with complete macro data
- Missing nutrients default to 0, not nil (except fiber, sugar, sodium which can be nil)
- Rate limit (HTTP 429) is handled gracefully
- Network errors produce `NutritionError.searchFailed`

**Files:** No changes needed if existing implementation is correct.

---

### N2.3 Verify OpenFoodFacts Barcode Lookup

**Time estimate:** 30 minutes
**Prerequisites:** N2.1
**Existing file:** `Tempo/Tempo/Services/Nutrition/FoodSearchService.swift`
**What to verify:**
The OFF integration already exists with:
- `lookupBarcode(_:)` hitting `https://world.openfoodfacts.org/api/v2/product/{barcode}`
- `User-Agent` header set (required by OFF terms of use)
- 404 handling (product not found)
- Response parsing via `OFFProductResponse`

**Verify:** That `OFFProduct.toFoodSearchResult(barcode:)` correctly extracts nutriments per 100g and converts to per-serving using `serving_quantity`. Handle missing `nutriments` gracefully.

**Acceptance criteria:**
- Barcode lookup returns `nil` for unknown barcodes (not an error)
- Products with incomplete nutrition data return partial results with available fields
- `User-Agent` header is present on every request
- Rate limit (HTTP 429) handled

**Files:** No changes needed if existing implementation is correct.

---

### N2.4 Verify Local CachedFood Search

**Time estimate:** 15 minutes
**Prerequisites:** N1.4, N2.1
**Existing file:** `Tempo/Tempo/Services/Nutrition/FoodSearchService.swift`
**What to verify:**
`searchLocal(query:context:)` uses `#Predicate` on `searchKeywords.contains(lowered)` with results sorted by `useCount` descending. This is correct.

**Acceptance criteria:**
- Local search returns cached foods matching the query
- Results are sorted by frequency of use (most-used first)
- Empty query returns empty array

**Files:** No changes needed.

---

### N2.5 Pre-Seed Top 200 Common Foods

**Time estimate:** 2 hours
**Prerequisites:** N1.4, N2.1
**What to build:**
1. `Tempo/Tempo/Resources/CommonFoods.json` — JSON file with 200 common foods, each containing: `name`, `brand` (null for generic), `caloriesPer100g`, `proteinPer100g`, `carbsPer100g`, `fatPer100g`, `fiberPer100g`, `defaultServingGrams`, `defaultServingLabel`, `searchKeywords`, `category` (protein, carb, fat, dairy, fruit, vegetable, grain, snack, beverage).
   - Include: chicken breast, rice, eggs, oats, banana, apple, broccoli, salmon, ground beef, pasta, bread, milk, yogurt, cheese, peanut butter, olive oil, avocado, sweet potato, quinoa, tofu, whey protein, almonds, etc.
   - All values from USDA FoodData Central (verified).
2. `Tempo/Tempo/Services/Nutrition/CommonFoodsLoader.swift` — Service that:
   - Loads `CommonFoods.json` on first launch
   - Inserts as `CachedFood` entries with `dataSource = .usda`
   - Is idempotent (checks if seeded via `UserDefaults` flag)
   - Runs on background thread to avoid blocking launch

**Acceptance criteria:**
- `CommonFoods.json` parses without error
- At least 200 foods across all categories
- Every food has valid macro data (calories > 0, protein/carbs/fat >= 0)
- `CommonFoodsLoader` is idempotent (running twice does not duplicate)
- Seeding completes in < 2 seconds on iPhone 15
- Local food search for "chicken" returns results immediately after seeding

**Files created:**
- `Tempo/Tempo/Resources/CommonFoods.json`
- `Tempo/Tempo/Services/Nutrition/CommonFoodsLoader.swift`

---

## Phase N3: Meal Logging Service (3-4 hours)

**Prerequisites:** Phase N1, Phase N2
**Docs to reference:** `docs/INTEGRATION_SPECS.md` Section 2 (HealthKit — writeNutrition), `docs/MODULE_DASHBOARD.md` Section 2.3 (score calculation — nutrition component)

> **Status:** `MealLoggingService.swift` exists with core CRUD and HealthKit sync. Needs refactoring to use canonical models and additions for daily summary and scoring integration.

---

### N3.1 Refactor MealLoggingService — Remove Duplicate Models

**Time estimate:** 1 hour
**Prerequisites:** N1.2, N1.4
**Existing file:** `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift`
**What to build:**
The service file currently contains duplicate `@Model` definitions for `MealLog` and `MealFoodItem`. These must be removed. The service should import and use the canonical models from `Models/Nutrition/`.

1. Remove the `@Model final class MealLog { ... }` block (lines 19-80 of current file)
2. Remove the `@Model final class MealFoodItem { ... }` block (lines 84-131 of current file)
3. Update `MealLoggingService` implementation to use the canonical models' API (the canonical `MealLog` init takes slightly different parameters)
4. Update `MealFoodItem` creation to use the canonical model's init (which takes individual macro parameters, not a `MealFoodItemInput`)
5. Keep the `MealLoggingServiceProtocol` and `MealLoggingService` implementation

**Acceptance criteria:**
- `MealLoggingService.swift` contains NO `@Model` definitions
- All service methods work with canonical models from `Models/Nutrition/`
- `logMeal` creates a `MealLog` with correct `dayDate` normalization
- `todaySummary` returns accurate daily totals
- File compiles with no ambiguous type references

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift` (major refactor)

---

### N3.2 Implement Meal CRUD Operations

**Time estimate:** 45 minutes
**Prerequisites:** N3.1
**Existing:** CRUD already exists in `MealLoggingService`. Verify completeness.
**What to verify/build:**
1. `logMeal(type:items:photo:source:context:)` — Creates `MealLog` + `MealFoodItem` children, saves, returns meal. Already exists.
2. `updateMeal(_:items:context:)` — Deletes old items, adds new, recalculates totals. Already exists.
3. `deleteMeal(_:context:)` — Deletes meal (cascade deletes items). Already exists.
4. `fetchTodayMeals(context:)` — Fetches meals where `dayDate == startOfDay(for: Date())`. Already exists.
5. `fetchMeals(for:context:)` — Fetches meals for any date. Already exists.
6. **Add:** `fetchMealsForWeek(containing date: Date, context: ModelContext) -> [Date: [MealLog]]` — Returns a dictionary of date -> meals for the week containing the given date. Needed for weekly review.
7. **Add:** `recentFoods(limit: Int, context: ModelContext) -> [CachedFood]` — Returns most recently used foods sorted by `useCount`. Needed for quick-add in UI.

**Acceptance criteria:**
- All 7 methods work correctly
- `fetchMealsForWeek` returns 7 days of data
- `recentFoods` returns up to `limit` items sorted by frequency
- All date comparisons use `Calendar.current.startOfDay(for:)` for normalization

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift` (add 2 methods)

---

### N3.3 Implement Daily Summary Calculation

**Time estimate:** 30 minutes
**Prerequisites:** N3.2
**Existing:** `todaySummary(context:)` exists but reads targets from `DailySnapshot`. Update to read from `NutritionTarget`.
**What to build:**
Update `todaySummary` to:
1. Fetch today's meals and sum macros (already done)
2. Fetch the active `NutritionTarget` (where `isActive == true`) for targets instead of reading from `DailySnapshot`
3. Return `DailyNutritionSummary` with both consumed values and targets
4. **Add:** Compute `mealCompliancePercentage` — percentage of planned meals logged (meals logged / `NutritionTarget.mealsPerDay * 100`)
5. **Add:** Compute `proteinAdherencePercentage`, `calorieAdherencePercentage` — how close to target

**Acceptance criteria:**
- `todaySummary` returns accurate totals from native `MealLog` data
- Targets come from `NutritionTarget`, not `DailySnapshot`
- Percentages are clamped 0-100 (overeating does NOT reduce score per `MODULE_DASHBOARD.md` Section 2.3)
- If no active `NutritionTarget` exists, target fields are nil

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift` (update `todaySummary`)
- `Tempo/Tempo/Services/Nutrition/NutritionDTOs.swift` (update `DailyNutritionSummary` struct if needed)

---

### N3.4 Implement HealthKit Nutrition Writes

**Time estimate:** 30 minutes
**Prerequisites:** N3.1
**Existing:** `syncToHealthKit(_:)` already exists in `MealLoggingService` and calls `healthKit.writeNutrition(NutritionSample(...))`. The `HealthKitService` already implements `writeNutrition` as an `HKCorrelation` with `HKQuantitySample`s for dietary energy, protein, carbs, and fat.
**What to verify:**
1. `syncToHealthKit` is called after every successful `logMeal` (already done in background `Task`)
2. Updated meals trigger a re-sync (mark `syncedToHealthKit = false` on update, then re-sync)
3. Deleted meals do NOT attempt to delete from HealthKit (HealthKit samples are write-only from third-party apps)

**Add:** Batch sync for historical import — `syncUnsyncedMeals(context:)` method that finds all meals where `syncedToHealthKit == false` and syncs them sequentially. Called on app launch if HealthKit is authorized.

**Acceptance criteria:**
- Every logged meal writes to HealthKit within 5 seconds
- Updated meals re-write to HealthKit (creating new samples — HealthKit handles deduplication)
- `syncUnsyncedMeals` processes all pending meals
- HealthKit write failures are logged but do not block meal logging

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift` (add `syncUnsyncedMeals`, verify update re-sync)

---

### N3.5 Register Nutrition Services in ServiceContainer

**Time estimate:** 30 minutes
**Prerequisites:** N3.1, N2.1
**Existing file:** `Tempo/Tempo/App/ServiceContainer.swift`
**What to build:**
Add `FoodSearchService` and `MealLoggingService` to the `ServiceContainer`:
1. Add properties:
   - `let foodSearch: FoodSearchServiceProtocol`
   - `let mealLogging: MealLoggingServiceProtocol`
2. Add to `init` parameters and assignment
3. Update `ServiceContainer.mock()` to create mock/stub instances
4. Update `TempoApp.swift` to instantiate real services and pass to container
5. Call `CommonFoodsLoader.seedIfNeeded(context:)` during app launch sequence

**Acceptance criteria:**
- `ServiceContainer` exposes `foodSearch` and `mealLogging`
- Mock container provides stub implementations for SwiftUI previews
- `CommonFoodsLoader` runs on first launch
- App still launches without crashes

**Files modified:**
- `Tempo/Tempo/App/ServiceContainer.swift`
- `Tempo/Tempo/TempoApp.swift`

---

## Phase N4: Nutrition UI — Core (5-6 hours)

**Prerequisites:** Phase N2, Phase N3
**Docs to reference:** `docs/DESIGN_SYSTEM.md` (all color tokens, typography, spacing), `docs/MODULE_DASHBOARD.md` Section 4 (Fuel quadrant expanded view), `docs/UX_COPY_BIBLE.md` (drill-sergeant copy)

> **Status:** `MealLoggingView.swift` exists but needs connection to real services. All other views are new.

---

### N4.1 Create NutritionViewModel

**Time estimate:** 1.5 hours
**Prerequisites:** N3.2, N3.3
**What to build:**
`Tempo/Tempo/ViewModels/NutritionViewModel.swift` — `@Observable @MainActor` class:
1. Properties:
   - `todaySummary: DailyNutritionSummary` (refreshed on meal changes)
   - `todayMeals: [MealLog]` (sorted by `loggedAt`)
   - `activeTarget: NutritionTarget?`
   - `isLoading: Bool`
   - `error: NutritionError?`
2. Methods:
   - `loadToday()` — fetches meals and summary for today
   - `logMeal(type:items:photo:source:)` — delegates to `MealLoggingService`, refreshes state
   - `deleteMeal(_:)` — delegates to service, refreshes state
   - `updateTarget(_:)` — saves new `NutritionTarget`
   - `refreshSummary()` — recalculates daily totals
3. Computed properties:
   - `calorieProgress: Double` (0.0-1.0 for ring fill)
   - `proteinProgress: Double`
   - `mealsLoggedText: String` (e.g., "2/4 meals" or "All 4 meals logged")
   - `isCalorieTargetMet: Bool`
   - `isProteinTargetMet: Bool`
4. Integration with `ModelContext` for SwiftData queries
5. Publishes changes for SwiftUI reactivity

**Acceptance criteria:**
- ViewModel compiles under strict concurrency (`@MainActor`, `@Observable`)
- `loadToday()` fetches meals and calculates summary
- `calorieProgress` returns 0.0 when no target is set
- All state changes trigger SwiftUI view updates

**Files created:**
- `Tempo/Tempo/ViewModels/NutritionViewModel.swift`

---

### N4.2 Create FoodSearchView

**Time estimate:** 1.5 hours
**Prerequisites:** N2.1, N4.1
**Docs:** `docs/DESIGN_SYSTEM.md` (search bar, list cells, color tokens)
**What to build:**
`Tempo/Tempo/Views/Nutrition/FoodSearchView.swift` — Searchable list for finding foods:
1. **Search bar** at top with `.searchable` modifier
2. **Section: Recent Foods** — shows `recentFoods(limit: 10)` when search is empty
3. **Section: Local Results** — `CachedFood` matches from local database (instant)
4. **Section: USDA Results** — API results with 300ms debounce (only triggers after user stops typing)
5. **Each cell** shows: food name, brand (if any), calories per serving, serving size
6. **Tap action:** presents a `PortionPickerSheet` (quantity stepper + serving size selector) then adds to meal
7. **Add Custom Food** button at bottom — navigates to manual entry form
8. **Empty state:** "No foods found. Try a different search or add a custom food."
9. Design tokens: `tempo.color.bg.primary` background, `tempo.color.surface.card` cells, `tempo.body` font for names, `tempo.caption1` for macros

**Acceptance criteria:**
- Local results appear instantly (no network delay)
- USDA results appear within 2 seconds of search debounce
- Portion picker allows quantity adjustment (0.25 increments)
- Selected food is passed back to `MealLoggingView` via callback/binding
- Empty query shows recent foods
- Loading indicator while USDA search is in progress

**Files created:**
- `Tempo/Tempo/Views/Nutrition/FoodSearchView.swift`

---

### N4.3 Create BarcodeScannerView

**Time estimate:** 1 hour
**Prerequisites:** N2.3
**Docs:** `docs/DEPENDENCIES.md` (no third-party deps — use VisionKit)
**What to build:**
`Tempo/Tempo/Views/Nutrition/BarcodeScannerView.swift` — Camera-based barcode scanner:
1. Use `DataScannerViewController` (VisionKit, iOS 16+) wrapped in `UIViewControllerRepresentable`
2. Scan types: `.barcode(symbologies: [.ean8, .ean13, .upca, .upce, .code128])`
3. On barcode detected: call `FoodSearchService.lookupBarcode(_:)`
4. **Success:** dismiss scanner, present food details with portion picker
5. **Not found:** show banner "Product not found in database. Try searching by name." with option to dismiss
6. **Camera permission denied:** show settings redirect view
7. Torch toggle button (for low-light scanning)
8. Design: fullscreen camera with semi-transparent overlay, barcode targeting box, result card slides up from bottom

**Acceptance criteria:**
- Scanner activates camera and detects EAN-13 barcodes
- Found products show name + macros with add-to-meal option
- Not-found barcodes show clear fallback message
- Camera permission is requested properly
- Scanner stops when a barcode is found (prevents repeated scans)

**Files created:**
- `Tempo/Tempo/Views/Nutrition/BarcodeScannerView.swift`

---

### N4.4 Refactor MealLoggingView (Connect to Real Services)

**Time estimate:** 1 hour
**Prerequisites:** N4.1, N4.2, N4.3
**Existing file:** `Tempo/Tempo/Views/Nutrition/MealLoggingView.swift`
**What to build:**
The existing `MealLoggingView` has the correct UI structure (meal type picker, food items list, sticky bottom bar) but uses a local `FoodItem` struct and a callback closure. Refactor to:
1. Use `NutritionViewModel` for state management
2. Replace local `FoodItem` with `MealFoodItemInput` from `NutritionDTOs`
3. Remove the duplicate `MealType` enum defined inside the view (use `NutritionEnums.MealType`)
4. Connect "Add Food" button to `FoodSearchView` (sheet)
5. Connect camera button to `PhotoAnalysisView` (Phase N5 — wire placeholder for now)
6. Connect barcode button to `BarcodeScannerView`
7. "Save Meal" button calls `viewModel.logMeal(type:items:photo:source:)`
8. Success triggers haptic feedback (`UINotificationFeedbackGenerator.success`) and dismissal
9. Add running macro totals bar at bottom (calories, protein, carbs, fat)

**Acceptance criteria:**
- Meal type picker works (breakfast/lunch/dinner/snack)
- Adding food items from search updates the running totals
- Saving a meal persists to SwiftData and dismisses the view
- Each food item in the list has swipe-to-delete
- Quantity can be edited inline (tap the serving text)
- Empty state shows "Add your first food item" with prominent + button

**Files modified:**
- `Tempo/Tempo/Views/Nutrition/MealLoggingView.swift` (major refactor)

---

### N4.5 Create DailyNutritionSummaryView

**Time estimate:** 1.5 hours
**Prerequisites:** N4.1
**Docs:** `docs/MODULE_DASHBOARD.md` Section 4 (Expanded Quadrant Views — Fuel), `docs/DESIGN_SYSTEM.md`
**What to build:**
`Tempo/Tempo/Views/Nutrition/DailyNutritionSummaryView.swift` — Full detail view for nutrition (replaces NutriTrack-powered fuel detail):
1. **Calorie ring** — large centered ring showing consumed/target with `tempo.color.accent.violet` fill. Animated fill on appear (`tempo.motion.data` = 800ms spring).
2. **Macro bars** — horizontal progress bars for protein, carbs, fat. Each shows `Xg / Yg` with percentage.
3. **Meal timeline** — list of today's meals, each showing: meal type icon, time, item count, total calories. Tap to expand and show individual items.
4. **"Log Meal" button** — prominent CTA at bottom, presents `MealLoggingView` as sheet.
5. **Quick stats row:** Meals logged (e.g., "3/4"), protein adherence (e.g., "92%"), remaining calories.
6. **Empty state:** "No meals logged today. Tap below to start tracking." with drill-sergeant prompt: "Food is fuel. Log it."
7. **Stale data indicator:** Not needed (data is local — always fresh). Show "Last meal: 2h 15m ago" timestamp.
8. Navigation: accessible from Dashboard fuel quadrant tap.

**Acceptance criteria:**
- Calorie ring animates on appear
- Macro bars show correct percentages
- Meal timeline shows all today's meals in chronological order
- Tapping a meal expands to show food items
- "Log Meal" button presents `MealLoggingView`
- View updates reactively when meals are added/deleted

**Files created:**
- `Tempo/Tempo/Views/Nutrition/DailyNutritionSummaryView.swift`

---

### N4.6 Create NutritionTargetSetupView

**Time estimate:** 1 hour
**Prerequisites:** N4.1
**Docs:** `docs/ONBOARDING_AND_NOTIFICATIONS.md` (onboarding step format), `docs/DESIGN_SYSTEM.md`
**What to build:**
`Tempo/Tempo/Views/Nutrition/NutritionTargetSetupView.swift` — Target configuration view used in onboarding and settings:
1. **Calorie target** — stepper (1200-5000, step 50) with recommended range based on `UserProfile.estimatedBMR` if available
2. **Protein target** — stepper (50-400g, step 5) with recommendation: `1.6 * weightKg` for athletes
3. **Carbs target** — stepper (50-600g, step 5)
4. **Fat target** — stepper (20-200g, step 5)
5. **Meals per day** — segmented control (2, 3, 4, 5)
6. **Macro balance indicator** — shows if macro-derived calories match calorie target (within 50 kcal). Warning badge if they don't match.
7. **"Calculate from body stats" button** — auto-fills targets based on `UserProfile` weight, height, age, activity level using Mifflin-St Jeor equation.
8. **Save** creates or updates `NutritionTarget` with `isActive = true` (deactivates previous active target)

**Acceptance criteria:**
- All steppers have correct ranges and increments
- Macro balance indicator updates live as values change
- "Calculate from body stats" produces reasonable defaults (e.g., 2400 kcal / 180g P / 280g C / 80g F for a 75kg active male)
- Saving persists to SwiftData
- Previous active target is deactivated (only one active at a time)

**Files created:**
- `Tempo/Tempo/Views/Nutrition/NutritionTargetSetupView.swift`

---

### N4.7 Update Dashboard Fuel Quadrant with Native Data

**Time estimate:** 1 hour
**Prerequisites:** N4.1, N4.5
**Existing files:** `Tempo/Tempo/Views/Dashboard/DashboardView.swift`, `Tempo/Tempo/Views/Dashboard/FuelQuadrantDetailView.swift`, `Tempo/Tempo/ViewModels/DashboardViewModel.swift`
**What to build:**
1. **DashboardViewModel:** Replace NutriTrack service data source for the Fuel quadrant with native `MealLoggingService.todaySummary()`. Remove `nutriTrack` dependency for fuel data. Keep NutriTrack connection status checks for backward compatibility (show import option).
2. **Fuel quadrant card:** Show native data — calories consumed/target, macro bars, meals logged count. Add "Log Meal" quick action button (small + icon in corner).
3. **Fuel quadrant tap:** Navigate to `DailyNutritionSummaryView` instead of the NutriTrack-powered detail view.
4. **FuelQuadrantDetailView:** Replace with navigation to `DailyNutritionSummaryView` or refactor to use native data.
5. Update `FuelQuadrantData` source from `.nutritrack | .disconnected` to `.native | .noTarget` (no target = show setup prompt).

**Acceptance criteria:**
- Fuel quadrant shows data from native SwiftData meals, not NutriTrack
- Calorie ring fills correctly based on consumed vs target
- "Log Meal" quick action opens `MealLoggingView`
- Tapping fuel quadrant navigates to `DailyNutritionSummaryView`
- No crashes when `NutritionTarget` is not yet configured (shows setup prompt)
- Daily score calculation uses native nutrition data

**Files modified:**
- `Tempo/Tempo/ViewModels/DashboardViewModel.swift` (fuel data source change)
- `Tempo/Tempo/Views/Dashboard/DashboardView.swift` (fuel quadrant navigation)
- `Tempo/Tempo/Views/Dashboard/FuelQuadrantDetailView.swift` (refactor or replace)

---

## Phase N5: Photo Analysis (3-4 hours)

**Prerequisites:** Phase N3, Phase N4.4
**Docs to reference:** `docs/AI_INTELLIGENCE_ENGINE.md` Section 2 (Claude API config), Section 5 (cost management)

---

### N5.1 Create Claude API Client (iOS-Side)

**Time estimate:** 1.5 hours
**Prerequisites:** N3.5 (ServiceContainer)
**Docs:** `docs/AI_INTELLIGENCE_ENGINE.md` Section 2.5 (API client config), `docs/BACKEND_API.md` (auth headers)
**What to build:**
`Tempo/Tempo/Services/AI/ClaudeAPIClient.swift` — Client that calls the Tempo backend's AI proxy endpoint (NOT direct to Anthropic — all AI calls go through the Tempo backend for budget tracking, rate limiting, and API key security):
1. Protocol: `ClaudeAPIClientProtocol`
   - `func analyzePhoto(imageData: Data, mealType: MealType) async throws -> PhotoAnalysisResult`
   - `func getMealFeedback(meal: MealLog, target: NutritionTarget) async throws -> String`
   - `func getDailySummary(summary: DailyNutritionSummary, target: NutritionTarget) async throws -> String`
   - `func getWeeklyReview(meals: [Date: [MealLog]], target: NutritionTarget) async throws -> NutritionWeeklyReview`
2. Implementation calls `APIClient.post("/v1/ai/nutrition/...")` endpoints
3. Timeout: 15s for photo analysis, 5s for meal feedback, 5s for daily summary, 30s for weekly review
4. Error handling: `NutritionError.photoAnalysisFailed`, `NutritionError.invalidResponse`
5. Response parsing with JSON extraction fallback (Claude sometimes wraps in markdown)

**Backend endpoints to be created (or already exist under AI routes):**
- `POST /v1/ai/nutrition/analyze-photo` — Accepts base64 image, returns food items with macros
- `POST /v1/ai/nutrition/meal-feedback` — Accepts meal data, returns coaching text
- `POST /v1/ai/nutrition/daily-summary` — Accepts day's nutrition, returns insights
- `POST /v1/ai/nutrition/weekly-review` — Accepts week data, returns structured review

**Acceptance criteria:**
- Client compiles and conforms to `Sendable`
- All calls go through the Tempo backend (no direct Anthropic API calls from iOS)
- Timeout handling works (throws error after timeout period)
- Response parsing handles both clean JSON and markdown-wrapped JSON
- Mock implementation exists for previews/testing

**Files created:**
- `Tempo/Tempo/Services/AI/ClaudeAPIClient.swift`

---

### N5.2 Create PhotoAnalysisService

**Time estimate:** 1 hour
**Prerequisites:** N5.1, N2.1
**What to build:**
`Tempo/Tempo/Services/Nutrition/PhotoAnalysisService.swift`:
1. Protocol: `PhotoAnalysisServiceProtocol`
   - `func analyzePhoto(_ imageData: Data, mealType: MealType) async throws -> [FoodSearchResult]`
2. Implementation:
   - Compress image to max 1MB JPEG (quality 0.7) before sending
   - Call `ClaudeAPIClient.analyzePhoto(imageData:mealType:)`
   - Parse response into `[FoodSearchResult]` with estimated macros
   - **RAG step:** For each identified food, search USDA database for the closest match to get verified macros. Use Claude's estimate only as fallback when USDA match confidence is low.
   - Return array of foods with their quantities and macros
3. Error handling:
   - `.noFoodDetected` — Claude says the image doesn't contain food
   - `.unclearPhoto` — Claude can't identify foods clearly
   - `.photoAnalysisFailed` — API error or timeout

**Acceptance criteria:**
- Images are compressed before sending (< 1MB)
- USDA RAG lookup improves accuracy over raw Claude estimates
- Service returns `[FoodSearchResult]` ready for the portion picker
- Errors are categorized correctly
- Mock implementation returns hardcoded results for testing

**Files created:**
- `Tempo/Tempo/Services/Nutrition/PhotoAnalysisService.swift`

---

### N5.3 Create PhotoAnalysisView

**Time estimate:** 1 hour
**Prerequisites:** N5.2, N4.2
**What to build:**
`Tempo/Tempo/Views/Nutrition/PhotoAnalysisView.swift` — Camera capture and AI analysis UI:
1. **Camera capture:** Use `UIImagePickerController` wrapped in `UIViewControllerRepresentable` (source: `.camera`). Also support photo library as fallback.
2. **Analysis state:** After capture, show the photo with a shimmer overlay and "Analyzing your meal..." text. Use `tempo.motion.shimmer` (1500ms linear sweep).
3. **Results:** Show identified foods in a list with estimated portions. Each item is editable:
   - Name (text field, pre-filled)
   - Serving size (stepper)
   - Macros (auto-calculated from serving)
4. **Edit flow:** User can remove misidentified items, adjust quantities, or add missing items (opens `FoodSearchView`)
5. **Confirm button:** Adds all items to the current meal
6. **Error states:**
   - "No food detected in photo. Try again with a clearer shot." (retry button)
   - "Couldn't identify all items. Review and adjust the list below."
   - Network error: "AI analysis unavailable. Add foods manually."

**Acceptance criteria:**
- Camera launches and captures photo
- Analysis shows shimmer while waiting (max 15 seconds)
- Results are editable before confirming
- Users can add/remove items from the results
- Confirming adds all items to the meal
- Camera permission denied shows settings redirect

**Files created:**
- `Tempo/Tempo/Views/Nutrition/PhotoAnalysisView.swift`

---

### N5.4 Wire Photo Analysis into MealLoggingView

**Time estimate:** 30 minutes
**Prerequisites:** N5.3, N4.4
**What to build:**
Connect the camera button in `MealLoggingView` to `PhotoAnalysisView`:
1. Camera button tap presents `PhotoAnalysisView` as full-screen cover
2. On analysis complete, confirmed foods are added to the current meal's items list
3. Running totals update immediately
4. Source is set to `.photo` for the meal

**Acceptance criteria:**
- Camera button in `MealLoggingView` opens `PhotoAnalysisView`
- Confirmed photo analysis results appear in the food items list
- Meal source is recorded as `.photo`
- Running totals are correct after adding photo-analyzed foods

**Files modified:**
- `Tempo/Tempo/Views/Nutrition/MealLoggingView.swift` (wire camera button)

---

## Phase N6: AI Coaching (3-4 hours)

**Prerequisites:** N5.1 (ClaudeAPIClient), Phase N3
**Docs to reference:** `docs/AI_INTELLIGENCE_ENGINE.md` Section 3 (prompt templates), Section 5 (cost analysis), `docs/UX_COPY_BIBLE.md` (drill-sergeant tone)

---

### N6.1 Create NutritionCoachPrompts

**Time estimate:** 1 hour
**Prerequisites:** N5.1
**What to build:**
`Tempo/Tempo/Services/AI/NutritionCoachPrompts.swift` — All prompt templates for nutrition coaching:
1. **Meal feedback prompt:** System prompt establishing drill-sergeant nutritionist persona. User prompt template with meal data (items, macros, time, meal type) + daily progress so far + target. Expected output: 1-3 sentences of feedback. Temperature: 0.5.
2. **Daily summary prompt:** System prompt for end-of-day analysis. User prompt with all meals, macro totals, target adherence. Expected output: 3-5 sentence summary with specific callouts. Temperature: 0.4.
3. **Weekly review prompt:** System prompt for weekly nutrition analyst. User prompt with 7 days of meal data, averages, adherence rates. Expected output: structured JSON with sections (overview, protein analysis, calorie analysis, meal timing, recommendations). Temperature: 0.4.
4. **Pre-training nutrition prompt:** System prompt for pre-workout nutrition advisor. User prompt with next workout type, recovery score, time until workout, last meal time/content. Expected output: 2-3 sentence meal suggestion. Temperature: 0.3.
5. **Recovery-aware coaching prompt:** System prompt that adjusts nutrition advice based on Whoop recovery data. User prompt with recovery score, HRV, sleep quality + current nutrition state. Expected output: targeted advice (e.g., "Yellow recovery — increase carbs by 20%, prioritize anti-inflammatory foods"). Temperature: 0.3.

All prompts follow the rules from `AI_INTELLIGENCE_ENGINE.md`:
- Reference only provided data (no hallucination)
- Never give medical advice
- Never suggest extreme caloric restriction (< 1500 kcal)
- Drill-sergeant tone: direct, specific, accountable

**Acceptance criteria:**
- All 5 prompt templates are defined as static string properties
- Each template has clear `{{placeholder}}` markers for data injection
- Temperature and max output tokens are specified per prompt
- A `buildPrompt(template:data:)` helper function performs placeholder substitution
- Prompts include `<bad_output_example>` sections where helpful

**Files created:**
- `Tempo/Tempo/Services/AI/NutritionCoachPrompts.swift`

---

### N6.2 Create NutritionCoachService

**Time estimate:** 1 hour
**Prerequisites:** N6.1, N5.1
**What to build:**
`Tempo/Tempo/Services/Nutrition/NutritionCoachService.swift`:
1. Protocol: `NutritionCoachServiceProtocol`
   - `func getMealFeedback(meal: MealLog, dailyProgress: DailyNutritionSummary, target: NutritionTarget) async throws -> String`
   - `func getDailySummary(summary: DailyNutritionSummary, target: NutritionTarget, recoveryScore: Double?) async throws -> String`
   - `func getPreTrainingAdvice(workoutType: WorkoutType, recoveryScore: Double?, lastMeal: MealLog?, target: NutritionTarget) async throws -> String`
2. Implementation:
   - Builds prompts using `NutritionCoachPrompts` templates
   - Calls `ClaudeAPIClient` for AI responses
   - Validates response length (20-100 words for meal feedback, 40-150 for daily summary)
   - Falls back to template-based responses when AI is unavailable:
     - Meal feedback: "Logged: {calories} kcal. {above/below} target by {delta}. Protein: {protein}g/{target}g."
     - Daily summary: "Today: {calories}/{target} kcal. {meals_logged}/{meals_planned} meals. Protein: {adherence}%."
3. Caching: Cache daily summary for 2 hours. Cache meal feedback for the meal's lifetime.
4. Rate limiting: Max 6 coaching calls per day per `AI_INTELLIGENCE_ENGINE.md` config.

**Acceptance criteria:**
- Meal feedback returns within 2 seconds (Haiku latency)
- Daily summary returns within 3 seconds
- Fallback templates work when AI is unavailable
- Response validation rejects empty or overly long responses
- Coaching respects daily rate limit

**Files created:**
- `Tempo/Tempo/Services/Nutrition/NutritionCoachService.swift`

---

### N6.3 Create Weekly Review + Recovery-Aware Coaching

**Time estimate:** 1 hour
**Prerequisites:** N6.2
**What to build:**
Add to `NutritionCoachService`:
1. `func getWeeklyReview(weekMeals: [Date: [MealLog]], target: NutritionTarget, weekRecovery: [DailyRecovery]) async throws -> NutritionWeeklyReview`
   - Calls Sonnet for deep analysis
   - Input: 7 days of meals + recovery data
   - Output: structured `NutritionWeeklyReview` (overview, protein analysis, calorie analysis, meal timing patterns, 3 recommendations)
   - Cached per-week (immutable once generated)
2. `func getRecoveryAwareAdvice(recovery: DailyRecovery, currentNutrition: DailyNutritionSummary, target: NutritionTarget) async throws -> String`
   - Recovery-aware nutrition adjustments
   - Green recovery: standard targets
   - Yellow recovery: +10% carbs, focus on anti-inflammatory foods
   - Red recovery: +20% carbs, +10% protein, prioritize sleep-supporting foods
   - Uses Haiku for real-time response

**DTOs to create in `NutritionDTOs.swift`:**
```swift
struct NutritionWeeklyReview: Codable, Sendable {
    let overview: String
    let proteinAnalysis: String
    let calorieAnalysis: String
    let mealTimingAnalysis: String
    let recommendations: [String] // 3 items
    let weekAverages: WeekAverages
    let comparedToLastWeek: WeekDelta?
}
```

**Acceptance criteria:**
- Weekly review produces structured analysis with specific day references
- Recovery-aware advice adjusts recommendations based on recovery zone
- Weekly review is cached (not regenerated on re-open)
- Fallback for weekly review: simple averages + template text

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/NutritionCoachService.swift` (add 2 methods)
- `Tempo/Tempo/Services/Nutrition/NutritionDTOs.swift` (add `NutritionWeeklyReview`)

---

### N6.4 Create Pre-Training Alerts + Meal Suggestions

**Time estimate:** 30 minutes
**Prerequisites:** N6.2
**What to build:**
Add to `NutritionCoachService`:
1. `func shouldSuggestPreTrainingMeal(nextWorkout: WorkoutPlan, lastMeal: MealLog?) -> Bool`
   - Returns `true` if workout is within 2 hours AND last meal was > 3 hours ago
2. `func getPreTrainingMealSuggestion(workoutType: WorkoutType, recoveryScore: Double?, timeUntilWorkout: TimeInterval) async throws -> String`
   - Quick suggestion: "Eat {X} 60-90 min before your {workout}. Target: {Y}g carbs, {Z}g protein."
   - Uses template (free) when workout is > 1 hour away, Haiku when < 1 hour

Wire into notification system:
3. In `NotificationService` (or local notification scheduler), add a check 90 minutes before scheduled workout. If `shouldSuggestPreTrainingMeal` returns true, schedule a local notification with the suggestion.

**Acceptance criteria:**
- Pre-training check correctly identifies when a meal is needed
- Suggestion is specific to workout type (more carbs for legs/cardio, more protein for upper body)
- Notification fires 90 minutes before workout if no recent meal
- Template fallback works without AI

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/NutritionCoachService.swift` (add 2 methods)
- `Tempo/Tempo/Services/Notifications/NotificationService.swift` (add pre-training meal notification trigger)

---

### N6.5 Add Coaching Cards to DailyNutritionSummaryView

**Time estimate:** 30 minutes
**Prerequisites:** N6.2, N4.5
**What to build:**
Add AI coaching cards to `DailyNutritionSummaryView`:
1. **After each meal logged:** Show a coaching card below the meal in the timeline with the AI feedback (or template feedback). Card uses `tempo.color.surface.card` background with a small brain icon (`brain.head.profile` SF Symbol).
2. **End-of-day summary card:** Appears after 8 PM (or after all planned meals are logged). Shows the daily coaching summary. Drill-sergeant tone.
3. **Recovery-aware banner:** If recovery data is available and recovery is yellow/red, show a banner at the top: "Yellow recovery. Prioritize carbs and anti-inflammatory foods today."
4. Cards animate in with `tempo.motion.medium` (300ms spring)
5. Cards are dismissible (swipe or X button)

**Acceptance criteria:**
- Coaching cards appear with drill-sergeant feedback
- Cards are contextual (reference specific foods/macros from the meal)
- Recovery-aware banner shows when applicable
- Cards can be dismissed
- Skeleton/shimmer shows while AI response is loading

**Files modified:**
- `Tempo/Tempo/Views/Nutrition/DailyNutritionSummaryView.swift` (add coaching cards)

---

## Phase N7: Gamification Integration (2 hours)

**Prerequisites:** Phase N3 (meal logging triggers XP events), Phase 14 of main build plan (Arena system)
**Docs to reference:** `docs/MODULE_ARENA.md` Section 2.1 (XP Sources — Nutrition XP table)

---

### N7.1 Add Nutrition XP Actions to Arena System

**Time estimate:** 1 hour
**Prerequisites:** N3.2, main build Phase 14 (Arena)
**Docs:** `docs/MODULE_ARENA.md` Section 2.1 — Nutrition XP table
**What to build:**
Wire meal logging events into the existing XP engine (`XPEngineProtocol`):
1. **After each meal logged**, award XP based on meal type and time:
   - Log breakfast (before 11:00): 15 XP
   - Log lunch (before 15:00): 15 XP
   - Log dinner (before 22:00): 15 XP
   - Log snack: 5 XP (max 3 snacks/day = 15 XP)
2. **End-of-day macro check** (run at 23:59 or when all meals logged):
   - Hit protein target (within 10%): +30 XP
   - Hit calorie target (within 10%): +20 XP
   - Hit ALL macro targets (protein + carbs + fat within 10%): +40 XP (replaces individual macro bonuses)
3. **Daily cap enforcement:** Max nutrition XP per day = 100 XP (15+15+15+15+40)

Implementation:
- Add `NutritionXPTrigger` cases to the XP event pipeline
- Create `XPEvent` entries with `source = .nutrition` for each trigger
- Call `xpEngine.awardXP(source:amount:reason:)` from `MealLoggingService` after successful meal log
- End-of-day check runs via existing daily scoring job or local notification trigger

**Acceptance criteria:**
- Logging breakfast before 11 AM awards 15 XP
- Logging 4th+ snack awards 0 XP (daily cap)
- Hitting all macro targets awards exactly 40 XP (not 40 + 30 + 20)
- XP events appear in Arena feed
- XP float animation triggers on the Dashboard after logging

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift` (add XP trigger after meal log)
- `Tempo/Tempo/Services/Engines/XPEngine.swift` (add nutrition XP cases if not already present)
- `Tempo/Tempo/Models/Enums/ArenaEnums.swift` (add `XPSource.nutrition` cases if not present)

---

### N7.2 Add Nutrition Achievements

**Time estimate:** 30 minutes
**Prerequisites:** N7.1
**Docs:** `docs/MODULE_ARENA.md` Section 21 (Achievement System — 108 achievements)
**What to build:**
Add nutrition-related achievements to the achievements system:
1. **First Bite** (common) — Log your first meal
2. **Meal Prep Master** (uncommon) — Log all planned meals for 7 consecutive days
3. **Protein Machine** (uncommon) — Hit protein target 14 days in a row
4. **Macro Architect** (rare) — Hit all macro targets for 30 consecutive days
5. **Fuel Perfectionist** (epic) — Perfect nutrition score (all macros within 5%) for 7 consecutive days
6. **Photo Logger** (common) — Log 10 meals using photo analysis
7. **Barcode Scanner** (common) — Scan 25 different products

Add achievement definitions to `Achievements.json` (or wherever achievements are defined) and wire completion checks into the existing achievement engine.

**Acceptance criteria:**
- All 7 achievements are defined with correct rarity, icon, and description
- Achievement checks run after meal logging events
- Unlocked achievements trigger the celebration animation (per `MODULE_ARENA.md` Section 11)
- Achievements persist in SwiftData

**Files modified:**
- `Tempo/Tempo/Resources/Achievements.json` (or equivalent — add nutrition achievements)
- `Tempo/Tempo/Services/Engines/AchievementEngine.swift` (add nutrition achievement checks)

---

### N7.3 Wire Fuel Score into Daily Tempo Score Calculation

**Time estimate:** 30 minutes
**Prerequisites:** N3.3, N4.7
**Docs:** `docs/MODULE_DASHBOARD.md` Section 2.3 (Daily Score Calculation)
**What to build:**
Update the scoring engine to use native nutrition data for the Fuel component of the daily score:
1. **Fuel sub-score formula** (from `MODULE_DASHBOARD.md`):
   - `base = min(100, (calories_consumed / calories_target) * 100)`
   - `penalty = missed_meals * 10` (missed = planned meals not logged by their deadline)
   - `final = max(0, base - penalty)`
2. Replace NutriTrack data source with `MealLoggingService.todaySummary()` for fuel score input
3. Handle edge cases:
   - No target set: fuel score is 0, weight redistributes to other components
   - No meals logged: fuel score is 0 (do NOT redistribute — user has a target but didn't log)
   - Overeating: caps at 100 (per spec)

**Acceptance criteria:**
- Daily score uses native nutrition data
- Fuel sub-score matches the formula in `MODULE_DASHBOARD.md` exactly
- Missing NutritionTarget causes weight redistribution (not zero score for the whole day)
- Score updates in real-time when meals are logged

**Files modified:**
- `Tempo/Tempo/Services/Engines/ScoringEngine.swift` (update fuel component data source)
- `Tempo/Tempo/ViewModels/DashboardViewModel.swift` (ensure score refresh triggers on meal events)

---

## Phase N7.5: Meal-Plan Intake Wizard

**Prerequisites:** Phase N4 (Plan tab exists), Phase 7 (pantry service available), MealPlanGeneratorService landed
**Docs to reference:** `docs/UX_COPY_BIBLE.md` §17, `docs/STATE_MACHINES.md` MealPlanIntakeWizard, `docs/AI_INTELLIGENCE_ENGINE.md` (prompt structure)

**Goal:** Insert a multi-step intake wizard between the "Generate New Plan" tap in the Plan tab and the existing `MealPlanGeneratorService.generateWeeklyPlan`. Pre-populates from `DietaryProfile` (which mirrors HealthKit weight/height via `HealthKitService`), pantry, and Whoop. Only surfaces fields whose values are session-scoped or genuinely unknown.

**Scope:**
- 8 step views with forward/back navigation and conditional skip predicates.
- Coordinator state machine (`WizardCoordinator`) owns visibility computation and intake draft.
- New `MealPlanIntake` value type forwarded into the generator (and thence into the Sonnet prompt as a `<weekly_intake>` block).
- Wizard answers do NOT mutate `DietaryProfile`. Draft is discarded on dismiss.

**Files added:**
- `Tempo/Tempo/Models/Nutrition/MealPlanIntake.swift`
- `Tempo/Tempo/Models/Nutrition/WizardLaunchSnapshot.swift`
- `Tempo/Tempo/Views/Nutrition/Wizard/WizardCoordinator.swift`
- `Tempo/Tempo/Views/Nutrition/Wizard/MealPlanIntakeWizardView.swift`
- `Tempo/Tempo/Views/Nutrition/Wizard/Shared/WizardStepScaffold.swift`
- `Tempo/Tempo/Views/Nutrition/Wizard/Steps/{CookingCapacity,LeftoverTolerance,EatingWindow,PantryGap,GroceryIntent,RecoveryOverride,TemporaryExclusions,Review}StepView.swift`
- `Tempo/TempoTests/Services/MealPlanPromptsTests.swift`

**Files modified:**
- `Tempo/Tempo/Services/Nutrition/MealPlanPrompts.swift` (add `weeklyIntakeBlock` + intake param on `weeklyPlanPrompt`)
- `Tempo/Tempo/Services/Nutrition/MealPlanGeneratorService.swift` (add `intake:` param on `generateWeeklyPlan`)
- `Tempo/Tempo/ViewModels/NutritionTabViewModel.swift` (extend `generatePlan` signature, add `buildWizardSnapshot`)
- `Tempo/Tempo/Views/Nutrition/NutritionWeeklyPlanView.swift` (wire button → wizard → generator)

**Acceptance:**
- Tap "Generate New Plan" → wizard sheet presents.
- Pre-population: pantry/Whoop steps only fire when their predicates evaluate true (empty/stale pantry, Whoop recovery available).
- Final step → `viewModel.generatePlan(modelContext:, whoop:, intake:)`.
- Pre-existing flow without wizard (e.g. auto-generate from DietaryProfile setup callback in `NutritionTabView`) is unaffected — `intake` defaults to `nil`.

---

## Phase N8: Migration & Polish (3-4 hours)

**Prerequisites:** All previous phases
**Docs to reference:** `docs/ONBOARDING_AND_NOTIFICATIONS.md`, `docs/INTEGRATION_SPECS.md` Section 3 (NutriTrack — for import)

---

### N8.1 Update Onboarding Flow

**Time estimate:** 1 hour
**Prerequisites:** N4.6 (NutritionTargetSetupView)
**Docs:** `docs/ONBOARDING_AND_NOTIFICATIONS.md` (onboarding step sequence)
**What to build:**
Update the onboarding flow to replace "Connect NutriTrack" with native nutrition target setup:
1. **Replace** the `NutriTrackConnectView` onboarding step with `NutritionTargetSetupView`
2. **Position** after profile setup (weight/height/age are needed for BMR calculation)
3. **Copy:** "Set your daily nutrition targets. We'll help you track every meal." Drill-sergeant variant: "Food is fuel. Set your targets. No guessing."
4. **Skip option:** "Skip for now" — user can set targets later in Settings
5. **If skipping:** Dashboard fuel quadrant shows "Set up nutrition targets" prompt instead of data

**Acceptance criteria:**
- Onboarding flow includes nutrition target setup step
- Step appears after profile setup (so BMR can be calculated)
- "Calculate from body stats" works with the just-entered profile data
- Skipping works — app functions without nutrition targets
- NutriTrack connect is removed from onboarding

**Files modified:**
- `Tempo/Tempo/Views/Onboarding/OnboardingContainerView.swift` (replace NutriTrack step)
- `Tempo/Tempo/ViewModels/OnboardingViewModel.swift` (update step sequence)

---

### N8.2 Keep NutriTrack as Optional Import in Settings

**Time estimate:** 1 hour
**Prerequisites:** N3.2
**What to build:**
`Tempo/Tempo/Views/Settings/NutriTrackImportView.swift` — Optional import for existing NutriTrack users:
1. **Settings > Integrations > Import from NutriTrack**
2. Connect flow: enter NutriTrack server URL + PIN (reuse existing connection logic)
3. Once connected: fetch last 90 days of meal data via NutriTrack export API
4. **Import process:**
   - For each NutriTrack meal, create a `MealLog` with `source = .imported`
   - Map NutriTrack food items to `MealFoodItem` entries
   - Skip meals that already exist (match by date + meal type)
   - Show progress: "Importing... 45/90 days"
5. **Post-import:** Disconnect NutriTrack, show summary ("Imported 267 meals from 90 days")
6. **One-time operation:** After import, all data is native. NutriTrack is no longer needed.

**Acceptance criteria:**
- Import connects to NutriTrack via existing backend proxy
- 90 days of history is imported without duplicates
- Imported meals have `source = .imported` for attribution
- Progress indicator shows during import
- NutriTrack is disconnected after successful import
- Import is accessible from Settings but NOT required

**Files created:**
- `Tempo/Tempo/Views/Settings/NutriTrackImportView.swift`

---

### N8.3 Add HealthKit Nutrition Permissions to Permission Request

**Time estimate:** 30 minutes
**Prerequisites:** N3.4
**Docs:** `docs/INTEGRATION_SPECS.md` Section 2 (HealthKit)
**What to build:**
Update the HealthKit authorization request to include nutrition write types:
1. Add to `HealthKitService.requestAuthorization()`:
   - Write: `HKQuantityType(.dietaryEnergyConsumed)`, `HKQuantityType(.dietaryProtein)`, `HKQuantityType(.dietaryCarbohydrates)`, `HKQuantityType(.dietaryFatTotal)`
   - Read: Same nutrition types (for displaying Apple Health nutrition data)
2. Update the HealthKit permission view to explain nutrition writes: "Tempo writes your meal data to Apple Health so other apps can access your nutrition info."
3. Handle partial authorization gracefully (user may deny nutrition writes but allow other HealthKit data)

**Acceptance criteria:**
- HealthKit authorization includes nutrition types
- Nutrition writes work after authorization
- Denied nutrition authorization does not break other HealthKit features
- Permission explanation is clear and non-alarming

**Files modified:**
- `Tempo/Tempo/Services/Health/HealthKitService.swift` (add nutrition types to auth request)
- `Tempo/Tempo/Views/Onboarding/HealthKitPermissionView.swift` (update explanation text)

---

### N8.4 Add Nutrition-Related Notifications

**Time estimate:** 1 hour
**Prerequisites:** N6.4, Phase 12 of main build plan (notification system)
**What to build:**
Add nutrition notifications to the existing notification scheduling engine:
1. **Meal reminders:** Configurable reminders at meal times (default: breakfast 8:00, lunch 12:30, dinner 18:30). Only fire if the meal hasn't been logged yet.
   - Copy: "Breakfast time. Log it." / "Lunch window closing. Did you eat?" / "Dinner. Log it before you forget."
2. **Daily nutrition summary:** Fire at 21:00 if not all meals are logged.
   - Copy: "{meals_logged}/{meals_planned} meals logged. {remaining_calories} kcal remaining. Don't let today go untracked."
3. **Streak protection:** Fire at 22:00 if meal logging streak is at risk (no meals logged today and streak >= 3).
   - Copy: "{streak} day streak on the line. Log one meal before midnight."
4. **Pre-training meal:** (Already handled in N6.4)
5. All notifications use the existing escalation tier system from `docs/ONBOARDING_AND_NOTIFICATIONS.md`
6. Notifications are configurable in Settings (meal reminders can be toggled per meal type)

**Acceptance criteria:**
- Meal reminders fire at configured times
- Reminders don't fire if the meal is already logged
- Daily summary notification includes accurate data
- Streak protection fires only when streak is actually at risk
- All notification copy uses drill-sergeant tone
- Notifications are toggleable in Settings

**Files modified:**
- `Tempo/Tempo/Services/Notifications/NotificationService.swift` (add nutrition notification scheduling)
- `Tempo/Tempo/Views/Shared/NotificationSettingsView.swift` (add meal reminder toggles)

---

### N8.5 End-to-End Testing

**Time estimate:** 1 hour
**Prerequisites:** All previous phases
**What to verify:**
Complete flow testing on simulator and device:
1. **Fresh install flow:** Launch app -> onboarding -> set nutrition targets -> log first meal -> verify Dashboard fuel quadrant updates -> verify XP awarded
2. **Daily logging flow:** Log breakfast (manual search) -> log lunch (barcode scan) -> log dinner (photo analysis) -> verify daily summary -> verify coaching feedback -> verify daily score
3. **Edge cases:**
   - No nutrition targets set (fuel quadrant shows setup prompt)
   - No meals logged (fuel score = 0, streak not affected)
   - 5+ snacks logged (XP cap at 3 snacks)
   - All macros hit perfectly (40 XP bonus, not 90)
   - Photo analysis with unrecognizable food (error state)
   - Barcode not in database (fallback to search)
   - HealthKit permission denied (meals still log, no HealthKit sync)
   - Offline mode (meals save locally, AI features show fallback)
4. **Performance:** Meal logging completes in < 500ms. Food search returns in < 1s (local) / < 3s (USDA). Photo analysis completes in < 15s.
5. **Data integrity:** Verify meals persist across app restart. Verify daily totals are correct after multiple meals. Verify cascade delete works.

**Acceptance criteria:**
- All flows complete without crashes
- UI matches design system tokens (colors, fonts, spacing)
- Haptic feedback fires on meal logged (`.success`)
- All error states show appropriate messages
- Performance targets met

**Files:** No new files. Testing only.

---

## Dependency Graph

```
N1 ─────────────────┬──────────────┬──────────────┐
(Data Models)        │              │              │
                     ▼              ▼              │
                    N2             N3              │
                (Food Search)  (Meal Logging)      │
                     │              │              │
                     ├──────┬───────┤              │
                     ▼      ▼       ▼              │
                    N4.2   N4.3   N4.1             │
                    N4.4 (depends on N4.1+N4.2+N4.3)│
                    N4.5 (depends on N4.1)          │
                    N4.6 (depends on N4.1)          │
                    N4.7 (depends on N4.1+N4.5)     │
                                    │              │
            ┌───────────────────────┤              │
            ▼                       ▼              │
           N5                      N6              │
     (Photo Analysis)         (AI Coaching)         │
            │                       │              │
            └───────┬───────────────┘              │
                    ▼                              │
                   N7 ◄────────────────────────────┘
            (Gamification)
                    │
                    ▼
                   N8
            (Migration & Polish)
```

**Parallelization opportunities:**
- N2 and N3 can run in parallel (both depend only on N1)
- N4.2, N4.3, N4.5, N4.6 can run in parallel (all depend on N4.1 but not each other)
- N5 and N6 can partially overlap (N6 depends on N5.1 but N5.2-N5.4 are independent of N6)
- N7.1, N7.2, N7.3 can run in parallel

---

## Cost Analysis

### External API Costs

| API | Cost | Rate Limit | Notes |
|-----|------|------------|-------|
| USDA FoodData Central | **Free** | 1,000 requests/hour per API key | Demo key has lower limits. Register at https://fdc.nal.usda.gov/api-key-signup.html |
| OpenFoodFacts | **Free** | 100 req/min (product GET), 10 req/min (search) | Must include `User-Agent` header. Open source database. |
| Claude Haiku (meal feedback) | ~$0.003/call | Per `AI_INTELLIGENCE_ENGINE.md` | ~1,200 input + 300 output tokens |
| Claude Haiku (daily summary) | ~$0.004/call | Per `AI_INTELLIGENCE_ENGINE.md` | ~1,500 input + 400 output tokens |
| Claude Sonnet (photo analysis) | ~$0.014/call | Per `AI_INTELLIGENCE_ENGINE.md` | ~2,000 input + 800 output tokens (image encoded as base64) |
| Claude Sonnet (weekly review) | ~$0.011/call | Per `AI_INTELLIGENCE_ENGINE.md` | ~3,000 input + 1,500 output tokens |

### Per-User Monthly AI Cost (Nutrition Module Only)

| Feature | Model | Frequency | Cost/Call | Monthly Cost |
|---------|-------|-----------|-----------|-------------|
| Meal feedback | Haiku | 3 meals/day x 25 days | $0.003 | $0.23 |
| Daily summary | Haiku | 25 days/month | $0.004 | $0.10 |
| Photo analysis | Sonnet | 5 photos/month (avg) | $0.014 | $0.07 |
| Weekly review | Sonnet | 4/month | $0.011 | $0.04 |
| Pre-training advice | Haiku | 12/month | $0.002 | $0.02 |
| Recovery-aware coaching | Haiku | 10/month | $0.003 | $0.03 |
| **TOTAL** | | | | **$0.49/user/month** |

### Margin Analysis

| Component | Value |
|-----------|-------|
| Subscription price | $4.99/month |
| Apple cut (30%) | -$1.50 |
| Existing AI costs (from `AI_INTELLIGENCE_ENGINE.md`) | -$1.05 (avg user) |
| **New nutrition AI costs** | **-$0.49** |
| Hosting (allocated) | -$0.30 |
| **Net margin per user** | **$1.65/user/month** |

This is tighter than the pre-nutrition margin ($2.15) but still viable. The nutrition module adds significant user value (daily engagement) that should improve retention, offsetting the cost increase. If margins need improvement: reduce meal feedback frequency (every other meal instead of every meal) to save $0.11/user/month.

---

## New Third-Party Dependencies

**iOS:** NONE. VisionKit (barcode scanning) is a system framework. USDA and OpenFoodFacts are REST APIs called via URLSession. Claude AI is proxied through the Tempo backend.

This maintains the "only 3 third-party iOS dependencies" rule from `docs/DEPENDENCIES.md` (PostHog, Crashlytics, Lottie).

---

## Total Estimated Time

| Phase | Hours (est.) |
|-------|-------------|
| N1: Data Models & Schema | 1.5 (mostly verification) |
| N2: Food Search Service | 3.5 |
| N3: Meal Logging Service | 3.0 |
| N4: Nutrition UI — Core | 8.5 |
| N5: Photo Analysis | 4.0 |
| N6: AI Coaching | 4.0 |
| N7: Gamification Integration | 2.0 |
| N8: Migration & Polish | 4.5 |
| **TOTAL** | **~31 hours** |

With parallelization (N2/N3 parallel, parts of N4 parallel, N5/N6 partial overlap): **~22-25 effective hours**.

---

## Files Created (Checklist)

| # | File Path | Phase |
|---|-----------|-------|
| 1 | `Tempo/Tempo/Resources/CommonFoods.json` | N2.5 |
| 2 | `Tempo/Tempo/Services/Nutrition/CommonFoodsLoader.swift` | N2.5 |
| 3 | `Tempo/Tempo/ViewModels/NutritionViewModel.swift` | N4.1 |
| 4 | `Tempo/Tempo/Views/Nutrition/FoodSearchView.swift` | N4.2 |
| 5 | `Tempo/Tempo/Views/Nutrition/BarcodeScannerView.swift` | N4.3 |
| 6 | `Tempo/Tempo/Views/Nutrition/DailyNutritionSummaryView.swift` | N4.5 |
| 7 | `Tempo/Tempo/Views/Nutrition/NutritionTargetSetupView.swift` | N4.6 |
| 8 | `Tempo/Tempo/Services/AI/ClaudeAPIClient.swift` | N5.1 |
| 9 | `Tempo/Tempo/Services/Nutrition/PhotoAnalysisService.swift` | N5.2 |
| 10 | `Tempo/Tempo/Views/Nutrition/PhotoAnalysisView.swift` | N5.3 |
| 11 | `Tempo/Tempo/Services/AI/NutritionCoachPrompts.swift` | N6.1 |
| 12 | `Tempo/Tempo/Services/Nutrition/NutritionCoachService.swift` | N6.2 |
| 13 | `Tempo/Tempo/Views/Settings/NutriTrackImportView.swift` | N8.2 |

## Files Modified (Checklist)

| # | File Path | Phase | What Changes |
|---|-----------|-------|-------------|
| 1 | `Tempo/Tempo/Models/Nutrition/NutritionEnums.swift` | N1.1 | Add `PortionUnit` enum |
| 2 | `Tempo/Tempo/Services/Nutrition/MealLoggingService.swift` | N1.2, N3.1, N3.2, N3.3, N3.4, N7.1 | Remove duplicate models, add methods, wire XP |
| 3 | `Tempo/Tempo/Models/Nutrition/CachedFood.swift` | N1.4 | Add `useCount` field |
| 4 | `Tempo/Tempo/Services/Nutrition/FoodSearchService.swift` | N1.4, N2.1 | Remove duplicate `CachedFood`, add `searchAll` |
| 5 | `Tempo/Tempo/Services/Nutrition/NutritionDTOs.swift` | N2.1, N3.3, N6.3 | Remove duplicate enums, add DTOs |
| 6 | `Tempo/Tempo/App/ServiceContainer.swift` | N3.5 | Add `foodSearch`, `mealLogging` services |
| 7 | `Tempo/Tempo/TempoApp.swift` | N3.5 | Instantiate nutrition services, run seeder |
| 8 | `Tempo/Tempo/Views/Nutrition/MealLoggingView.swift` | N4.4, N5.4 | Connect to real services, wire photo/barcode |
| 9 | `Tempo/Tempo/ViewModels/DashboardViewModel.swift` | N4.7, N7.3 | Use native nutrition data for fuel quadrant |
| 10 | `Tempo/Tempo/Views/Dashboard/DashboardView.swift` | N4.7 | Update fuel quadrant navigation |
| 11 | `Tempo/Tempo/Views/Dashboard/FuelQuadrantDetailView.swift` | N4.7 | Replace with native data or redirect |
| 12 | `Tempo/Tempo/Services/Engines/XPEngine.swift` | N7.1 | Add nutrition XP cases |
| 13 | `Tempo/Tempo/Models/Enums/ArenaEnums.swift` | N7.1 | Add `XPSource.nutrition` |
| 14 | `Tempo/Tempo/Resources/Achievements.json` | N7.2 | Add 7 nutrition achievements |
| 15 | `Tempo/Tempo/Services/Engines/AchievementEngine.swift` | N7.2 | Add nutrition achievement checks |
| 16 | `Tempo/Tempo/Services/Engines/ScoringEngine.swift` | N7.3 | Update fuel score data source |
| 17 | `Tempo/Tempo/Views/Onboarding/OnboardingContainerView.swift` | N8.1 | Replace NutriTrack step |
| 18 | `Tempo/Tempo/ViewModels/OnboardingViewModel.swift` | N8.1 | Update step sequence |
| 19 | `Tempo/Tempo/Services/Health/HealthKitService.swift` | N8.3 | Add nutrition types to auth |
| 20 | `Tempo/Tempo/Views/Onboarding/HealthKitPermissionView.swift` | N8.3 | Update permission text |
| 21 | `Tempo/Tempo/Services/Notifications/NotificationService.swift` | N6.4, N8.4 | Add meal notifications |
| 22 | `Tempo/Tempo/Views/Shared/NotificationSettingsView.swift` | N8.4 | Add meal reminder toggles |
| 23 | `Tempo/Tempo/Views/Nutrition/DailyNutritionSummaryView.swift` | N6.5 | Add coaching cards |
