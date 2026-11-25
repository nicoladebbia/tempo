//
// BodyProgressView.swift
// Tempo
//
// Body progress: weight, body fat and lean mass over time, from Health, in one
// place, with optional progress photos. The numbers are Health's readings kept
// as one snapshot a day; the photos are files on this phone and nowhere else.
//

import PhotosUI
import SwiftData
import SwiftUI

// MARK: - BodyProgressLinkCard

/// The way in from the Body page: where Body progress stands, in one line.
struct BodyProgressLinkCard: View {
    @Query(bodyProgressSnapshots())
    private var snapshots: [BodyComposition]
    @Query
    private var settings: [UserSettings]
    @Environment(\.dynamicTypeSize)
    private var typeSize

    private var summary: String {
        let unit = settings.first?.weightUnit ?? .kg
        let measurements = BodyProgress.measurements(from: snapshots.map(BodySnapshot.init))
        let weight = BodyProgress.series(.weight, from: measurements, days: nil, now: Date()).last
        let fat = BodyProgress.series(.bodyFat, from: measurements, days: nil, now: Date()).last
        switch (weight, fat) {
        case let (weight?, fat?):
            return "\(BodyProgress.displayNumber(weight.value, metric: .weight, unit: unit)) \(unit.abbreviation) · "
                + "\(BodyProgress.displayNumber(fat.value, metric: .bodyFat, unit: unit))% body fat"
        case let (weight?, nil):
            return "\(BodyProgress.displayNumber(weight.value, metric: .weight, unit: unit)) \(unit.abbreviation)"
        default:
            return "Weight, body fat, lean mass and progress photos"
        }
    }

    var body: some View {
        NavigationLink {
            BodyProgressView()
        } label: {
            HStack(spacing: Tide.s4) {
                if !typeSize.isAccessibilitySize {
                    TideAreaIconTile(systemName: "figure.stand", tint: TideTone.sky)
                }
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text("Body progress")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                    Text(summary)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("body-progress-link")
    }
}

// MARK: - BodyProgressView

struct BodyProgressView: View {
    // MARK: Internal

    var body: some View {
        TideScrollPage {
            if activeGoals.hasActive(of: [.bodyWeight]) {
                GoalProgressChip(kinds: [.bodyWeight])
            }
            metricTiles
            trendSection
            photosSection
            if typeSize.isAccessibilitySize {
                addPhotoControl
            }
        }
        .accessibilityIdentifier("body-progress-page")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The one action on this page stays under the thumb.
            if !typeSize.isAccessibilitySize {
                addPhotoControl
                    .padding(.horizontal, Tide.edge)
                    .padding(.top, Tide.s3)
                    .padding(.bottom, Tide.s2)
                    .pinnedBarScrim()
            }
        }
        .navigationTitle("Body progress")
        .navigationBarTitleDisplayMode(.inline)
        .tideCovered(viewing != nil || comparing || showCamera)
        .sheet(item: $viewing) { photo in
            ProgressPhotoViewer(photo: photo, store: store, onDelete: delete)
        }
        .sheet(isPresented: $comparing) {
            ProgressPhotoCompare(photos: photos, store: store)
        }
        .fullScreenCover(isPresented: $showCamera) {
            ProgressPhotoCamera { image in
                showCamera = false
                if let image {
                    Task { await add(image) }
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            if let item {
                Task { await load(item) }
            }
        }
        .alert("Photo not saved", isPresented: Binding(get: { problem != nil }, set: {
            if !$0 {
                problem = nil
            }
        })) {
            Button("OK") { problem = nil }
        } message: {
            Text(problem ?? "")
        }
        .task {
            reloadPhotos()
            await BodyCompositionRefresh.refresh(from: services.healthKit, in: modelContext)
        }
    }

    // MARK: Private

    /// How far back the chart looks.
    private enum Range: CaseIterable, Hashable {
        case month
        case quarter
        case all

        var title: String {
            switch self {
            case .month: "30 days"
            case .quarter: "90 days"
            case .all: "All"
            }
        }

        var days: Int? {
            switch self {
            case .month: 30
            case .quarter: 90
            case .all: nil
            }
        }
    }

    @Query(bodyProgressSnapshots())
    private var snapshots: [BodyComposition]
    @Query
    private var settings: [UserSettings]
    @Query(filter: #Predicate<Goal> { $0.isActive == true })
    private var activeGoals: [Goal]
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @State
    private var metric: BodyMetric = .weight
    @State
    private var range: Range = .month
    @State
    private var photos: [ProgressPhoto] = []
    @State
    private var viewing: ProgressPhoto?
    @State
    private var comparing = false
    @State
    private var showCamera = false
    @State
    private var showLibrary = false
    @State
    private var libraryItem: PhotosPickerItem?
    @State
    private var problem: String?

    private let store = ProgressPhotoStore()

    private var unit: WeightUnit {
        settings.first?.weightUnit ?? .kg
    }

    private var measurements: [BodyMeasurement] {
        BodyProgress.measurements(from: snapshots.map(BodySnapshot.init))
    }

    private func series(_ metric: BodyMetric, days: Int?) -> [BodyProgress.Point] {
        BodyProgress.series(metric, from: measurements, days: days, now: Date())
    }

    // MARK: - Metric tiles

    // The three readings at a glance. Each is also the switch for the chart below.

    private var metricTiles: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
        return layout {
            ForEach(BodyMetric.allCases, id: \.self) { tileMetric in
                metricTile(tileMetric)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func metricTile(_ tileMetric: BodyMetric) -> some View {
        let latest = series(tileMetric, days: nil).last
        let selected = tileMetric == metric
        return Button {
            withAnimation(Tide.snap) { metric = tileMetric }
        } label: {
            VStack(alignment: .leading, spacing: Tide.s2) {
                Text(tileMetric.rawValue)
                    .tideLabel(selected ? Tide.text : Tide.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                TideNumber(
                    latest.map { BodyProgress.displayNumber($0.value, metric: tileMetric, unit: unit) } ?? "--",
                    unit: latest == nil ? nil : BodyProgress.unitLabel(metric: tileMetric, unit: unit),
                    size: Tide.numeralS + Tide.s1, relativeTo: .title3,
                    color: latest == nil ? Tide.text3 : Tide.text
                )
                Text(latest.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? "No readings")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                        .strokeBorder(Tide.text2, lineWidth: Tide.rule * 2)
                }
            }
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Shows the chart for \(tileMetric.rawValue.lowercased())")
        .accessibilityIdentifier("body-metric-\(tileMetric.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    // MARK: - Trend

    private var trendSection: some View {
        let points = series(metric, days: range.days)
        let trend = BodyProgress.trend(of: points)
        return VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "\(metric.rawValue) trend")

            TidePillPicker(options: Range.allCases, selection: $range, title: \.title, label: "Range")

            VStack(alignment: .leading, spacing: Tide.s3) {
                Text(headline(trend))
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detail(trend) {
                    Text(detail)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if points.count >= 2 {
                    let shown = points.map {
                        TempoLineChartData<BodyMetric>.DataPoint(
                            date: $0.date,
                            value: BodyProgress.displayValue($0.value, metric: metric, unit: unit)
                        )
                    }
                    TideLineChart(
                        data: [
                            TempoLineChartData(
                                id: metric, label: metric.rawValue, color: TideTone.sky, points: shown
                            ),
                        ],
                        height: Tide.chartHeight,
                        axisDesiredCount: 4,
                        yDomain: ChartScale.fitted(shown.map(\.value))
                    )
                } else {
                    RecoveryChartPlaceholder(message: placeholder(count: points.count))
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
        .accessibilityIdentifier("body-progress-trend")
    }

    private func headline(_ trend: BodyProgress.Trend?) -> String {
        guard let trend else {
            return "No \(metric.rawValue.lowercased()) readings yet"
        }
        guard let rate = trend.weeklyRate, let direction = BodyProgress.direction(of: trend) else {
            return "Not enough readings for a trend yet"
        }
        let amount = "\(BodyProgress.displayNumber(abs(rate), metric: metric, unit: unit)) \(rateUnit)"
        switch direction {
        case .steady: return "Holding steady"
        case .up: return "Up \(amount) a week"
        case .down: return "Down \(amount) a week"
        }
    }

    /// Body fat is a percentage, so its change is in points of it.
    private var rateUnit: String {
        metric == .bodyFat ? "points" : unit.abbreviation
    }

    private func detail(_ trend: BodyProgress.Trend?) -> String? {
        guard let trend else {
            return nil
        }
        let latest = trend.latest.date.formatted(.dateTime.day().month(.abbreviated))
        let readings = trend.pointCount == 1 ? "1 reading" : "\(trend.pointCount) readings"
        return "\(readings), latest on \(latest)"
    }

    private func placeholder(count: Int) -> String {
        count == 0
            ? "Weigh in on a scale that syncs to Apple Health and your readings show up here."
            : "One reading so far. A second one draws the line."
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            TideSectionLabel(title: "Progress photos", trailing: photos.isEmpty ? nil : "\(photos.count)")

            HStack(alignment: .top, spacing: Tide.s3) {
                Image(systemName: "lock.fill")
                    .font(Tide.body)
                    .foregroundStyle(TideTone.mint)
                    .accessibilityHidden(true)
                Text("Photos stay on this phone. Tempo never uploads them, and they are not in your iCloud backup.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("progress-photos-privacy")

            if photos.isEmpty {
                TideEmptyPanel(
                    systemImage: "camera",
                    title: "No photos yet",
                    message: "Add one now and compare it with later ones. The same light, pose and time of day work best."
                )
                .tideCard()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 160 : 100), spacing: Tide.s2)],
                    spacing: Tide.s3
                ) {
                    ForEach(photos) { photo in
                        photoCell(photo)
                    }
                }

                if photos.count >= 2 {
                    Button {
                        comparing = true
                    } label: {
                        Label("Compare two photos", systemImage: "square.split.2x1")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("progress-photos-compare")
                }
            }
        }
    }

    private func photoCell(_ photo: ProgressPhoto) -> some View {
        Button {
            viewing = photo
        } label: {
            VStack(spacing: Tide.s1) {
                ProgressPhotoThumbnail(photo: photo, store: store)
                // Two columns at large text: the year would not fit beside its neighbour.
                Text(typeSize.isAccessibilitySize
                    ? photo.date.formatted(.dateTime.day().month(.abbreviated))
                    : photo.date.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Progress photo, \(photo.date.formatted(date: .long, time: .omitted))")
        .accessibilityHint("Opens the photo")
    }

    // MARK: - Add

    @ViewBuilder
    private var addPhotoControl: some View {
        if ProgressPhotoCamera.isAvailable {
            Menu {
                Button("Take photo", systemImage: "camera") { showCamera = true }
                Button("Choose from library", systemImage: "photo.on.rectangle") { showLibrary = true }
            } label: {
                addPhotoLabel
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("progress-photo-add")
        } else {
            Button {
                showLibrary = true
            } label: {
                addPhotoLabel
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("progress-photo-add")
        }
    }

    private var addPhotoLabel: some View {
        Label("Add progress photo", systemImage: "camera.fill")
            .frame(maxWidth: .infinity)
    }

    // MARK: - Photo actions

    private func reloadPhotos() {
        photos = store.photos()
    }

    private func add(_ image: UIImage) async {
        await save { try await store.add(picture: image) }
    }

    private func load(_ item: PhotosPickerItem) async {
        defer { libraryItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            problem = "That picture could not be read."
            return
        }
        await save { try await store.add(pictureData: data) }
    }

    /// Runs a save and shows the right words if it fails.
    private func save(_ work: () async throws -> ProgressPhoto) async {
        do {
            _ = try await work()
            reloadPhotos()
        } catch ProgressPhotoStore.AddError.unreadable {
            problem = "That picture could not be read."
        } catch {
            problem = "Check that your phone has free space, then try again."
        }
    }

    private func delete(_ photo: ProgressPhoto) {
        do {
            try store.delete(photo)
        } catch {
            problem = "The photo could not be deleted."
        }
        reloadPhotos()
    }
}

// MARK: - Snapshots

/// Every stored day of body composition, oldest first: one row a day, so a year
/// is a few hundred rows.
private func bodyProgressSnapshots() -> FetchDescriptor<BodyComposition> {
    FetchDescriptor<BodyComposition>(sortBy: [SortDescriptor(\.date)])
}

extension BodySnapshot {
    init(_ row: BodyComposition) {
        self.init(
            date: row.date, measurementDate: row.measurementDate,
            weightKg: row.weightKg, bodyFatPercent: row.bodyFatPercent, leanMassKg: row.leanMassKg
        )
    }
}
