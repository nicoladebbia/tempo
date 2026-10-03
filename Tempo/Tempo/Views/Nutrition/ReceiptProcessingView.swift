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

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                thumbnail
                summaryCard
                stagesCard
                Text("Matching and price checks keep running while you review.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
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
        let shape = RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
        return ZStack {
            if let image = images.first {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.tempoBgSecondary
            }
            GeometryReader { proxy in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.tempoSignal.opacity(0), Color.tempoSignal.opacity(0.55), Color.tempoSignal.opacity(0)],
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
        .overlay(shape.strokeBorder(Color.tempoBorder, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if images.count > 1 {
                Text("\(images.count) pages")
                    .font(.tempoCaption2.weight(.semibold))
                    .foregroundStyle(Color.tempoBone)
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(TempoSpacing.sm)
            }
        }
        .accessibilityLabel("Photo of your receipt")
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(spacing: TempoSpacing.md) {
            summaryCell(title: "STORE", value: progress.storeName)
            summaryCell(
                title: "TOTAL",
                value: progress.totalAmount.map { String(format: "$%.2f", $0) }
            )
            summaryCell(title: "ITEMS", value: progress.itemCandidateCount.map { "~\($0)" })
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func summaryCell(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.tempoModuleTag)
                .foregroundStyle(Color.tempoTextTertiary)
            if let value {
                Text(value)
                    .font(.tempoBody.weight(.semibold))
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: TempoRadius.sm)
                    .fill(Color.tempoBgSecondary)
                    .frame(width: 54, height: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: TempoAnimation.smallDuration), value: value)
    }

    // MARK: - Stages

    private var stagesCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            ForEach(ReceiptScanProgress.Stage.allCases, id: \.self) { stage in
                stageRow(stage)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("\(Int(context.date.timeIntervalSince(startedAt)))s")
                    .font(.tempoCaption2.monospacedDigit())
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func stageRow(_ stage: ReceiptScanProgress.Stage) -> some View {
        let state = progress.state(of: stage)
        return HStack(spacing: TempoSpacing.md) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.tempoSuccess)
                case .active:
                    ProgressView()
                case .upcoming:
                    Image(systemName: "circle")
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title)
                    .font(.tempoBody.weight(state == .active ? .semibold : .regular))
                    .foregroundStyle(state == .upcoming ? Color.tempoTextTertiary : Color.tempoTextPrimary)
                if state == .active {
                    Text(stage.detail)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            Spacer()
        }
        .animation(.easeOut(duration: TempoAnimation.smallDuration), value: state == .done)
        .accessibilityElement(children: .combine)
    }
}
