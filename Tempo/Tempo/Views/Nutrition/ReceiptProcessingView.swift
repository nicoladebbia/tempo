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

    var body: some View {
        ScrollView {
            VStack(spacing: Tide.s4) {
                thumbnail
                summaryCard
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

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: Tide.s3) {
            summaryCell(title: "Store", value: progress.storeName)
            summaryCell(
                title: "Total",
                value: progress.totalAmount.map { String(format: "$%.2f", $0) }
            )
            summaryCell(title: "Items", value: progress.itemCandidateCount.map { "~\($0)" })
        }
        .tideCard(padding: Tide.s4)
    }

    private func summaryCell(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text(title).tideLabel(Tide.text3)
            if let value {
                Text(value)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: Tide.controlRadius)
                    .fill(Tide.fill)
                    .frame(width: Tide.s10 + Tide.s3, height: Tide.s4)
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
            TideLevelBar(progress: Double(finished) / Double(max(stages.count, 1)), color: mood.accent, height: Tide.bar)
                .animation(Tide.settle, value: finished)
                .accessibilityHidden(true)
            ForEach(stages, id: \.self) { stage in
                stageRow(stage)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("\(Int(context.date.timeIntervalSince(startedAt)))s")
                    .font(Tide.caption.monospacedDigit())
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .tideCard(padding: Tide.s4)
    }

    private func stageRow(_ stage: ReceiptScanProgress.Stage) -> some View {
        let state = progress.state(of: stage)
        return HStack(spacing: Tide.s3) {
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
            Spacer()
        }
        .animation(Tide.snap, value: state == .done)
        .accessibilityElement(children: .combine)
    }
}
