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
    @State
    private var scanLineUp = false
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
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
            guard !reduceMotion else {
                return
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                scanLineUp = true
            }
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
            } else {
                Tide.fill
            }
            GeometryReader { proxy in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [mood.accent.opacity(0), mood.accent.opacity(0.55), mood.accent.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 36)
                    .offset(y: scanLineUp ? proxy.size.height - 36 : 0)
            }
        }
        .frame(width: 150, height: 190)
        .clipShape(shape)
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
                    .minimumScaleFactor(0.7)
                    .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: Tide.controlRadius)
                    .fill(Tide.fill)
                    .frame(width: 54, height: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Tide.snap, value: value)
    }

    // MARK: - Stages

    private var stagesCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            ForEach(ReceiptScanProgress.Stage.allCases, id: \.self) { stage in
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
            .frame(width: 24, height: 24)
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
