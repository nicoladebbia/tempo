//
// ReceiptProcessingView.swift
// Tempo
//
// Shown while a receipt is being read: thumbnail of the capture, the store
// and total the moment the on-device pre-parse has them, and a staged
// checklist that mirrors what the pipeline is really doing.
//

import SwiftUI

struct ReceiptProcessingView: View {
    let images: [UIImage]
    let progress: ReceiptScanProgress

    @State
    private var startedAt = Date()
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        ScrollView {
            VStack(spacing: Tide.s4) {
                heroCard
                stagesCard
                Text("Matching and price checks keep running while you review.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s4)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            startedAt = Date()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
        return ZStack {
            if let image = images.first {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Tide.Kitchen.receiptThumbWidth, height: Tide.Kitchen.receiptThumbHeight)
                    .clipShape(shape)
            } else {
                shape.fill(Tide.fill)
                    .frame(width: Tide.Kitchen.receiptThumbWidth, height: Tide.Kitchen.receiptThumbHeight)
            }
            // The same lit corners and sweeping band as the camera: the page is being read.
            KitchenFrame(width: Tide.Kitchen.receiptThumbWidth, height: Tide.Kitchen.receiptThumbHeight, looking: true)
        }
        .overlay(shape.strokeBorder(Tide.hairline, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if images.count > 1 {
                Text("\(images.count) pages")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text)
                    .padding(.horizontal, Tide.s2)
                    .padding(.vertical, Tide.s1)
                    .glassEffect(.regular.tint(Tide.Kitchen.cameraTint), in: .capsule)
                    .padding(Tide.s2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Photo of your receipt")
    }

    // MARK: - Hero: the picture and what has been read so far

    /// The page being read, with the store, the total and the item count
    /// filling in beside it as the on-device parse finds them. They stack
    /// under the picture at the accessibility text sizes.
    private var heroCard: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Tide.s4))
            : AnyLayout(HStackLayout(spacing: Tide.s5))
        return layout {
            thumbnail
            VStack(alignment: .leading, spacing: Tide.s4) {
                summaryCell(title: "Store", value: progress.storeName)
                summaryCell(
                    title: "Total",
                    value: progress.totalAmount.map { String(format: "$%.2f", $0) },
                    large: true
                )
                summaryCell(title: "Items", value: progress.itemCandidateCount.map { "~\($0)" })
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .tideCard(padding: Tide.s4)
    }

    private func summaryCell(title: String, value: String?, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(title).tideLabel(Tide.text3)
            if let value {
                Group {
                    if large {
                        TideNumber(value, size: Tide.numeralM, relativeTo: .title)
                    } else {
                        Text(value)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .contentTransition(.numericText())
                .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: Tide.controlRadius)
                    .fill(Tide.fill)
                    .frame(width: Tide.s10 + Tide.s3, height: large ? Tide.s6 : Tide.s4)
                    .shimmer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Tide.snap, value: value)
    }

    // MARK: - Stages

    private var stagesCard: some View {
        let stages = ReceiptScanProgress.Stage.allCases
        let finished = stages.filter { progress.state(of: $0) == .done }.count
        return VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reading").tideLabel()
                Spacer(minLength: Tide.s2)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(Int(context.date.timeIntervalSince(startedAt)))s")
                        .font(Tide.caption.monospacedDigit())
                        .foregroundStyle(Tide.text3)
                }
            }
            TideLevelBar(progress: Double(finished) / Double(max(stages.count, 1)), color: mood.accent, height: Tide.bar)
                .animation(Tide.settle, value: finished)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(stages, id: \.self) { stage in
                    stageRow(stage, isLast: stage == stages.last)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4)
    }

    /// One step of the read, joined to the next by a line that turns green
    /// once the step is done.
    private func stageRow(_ stage: ReceiptScanProgress.Stage, isLast: Bool) -> some View {
        let state = progress.state(of: stage)
        return HStack(alignment: .top, spacing: Tide.s3) {
            VStack(spacing: Tide.s1) {
                ZStack {
                    switch state {
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Tide.Kitchen.good)
                    case .active:
                        ProgressView()
                    case .upcoming:
                        Image(systemName: "circle")
                            .foregroundStyle(Tide.text3)
                    }
                }
                .frame(width: Tide.icon, height: Tide.icon)
                if !isLast {
                    Capsule()
                        .fill(state == .done ? Tide.Kitchen.good.opacity(0.6) : Tide.hairline)
                        .frame(width: Tide.hair)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(stage.title)
                    .font(state == .active ? Tide.bodyStrong : Tide.body)
                    .foregroundStyle(state == .upcoming ? Tide.text3 : Tide.text)
                if state == .active {
                    Text(stage.detail)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
            .padding(.bottom, isLast ? 0 : Tide.s3)
            Spacer(minLength: 0)
        }
        .animation(Tide.snap, value: state == .done)
        .accessibilityElement(children: .combine)
    }
}
