//
// TideGallery.swift
// Tempo
//
// Every Tide component on one screen, in each mood. Debug only: launch with
// `-tideGallery <score>` (or `-tideGallery none`) to check the look and the shaders.
//

#if DEBUG
    import SwiftUI

    struct TideGallery: View {
        let score: Int?

        /// The score passed with `-tideGallery`, if the gallery was asked for.
        static var requested: Int?? {
            let args = ProcessInfo.processInfo.arguments
            guard let index = args.firstIndex(of: "-tideGallery") else {
                return nil
            }
            return .some(args.indices.contains(index + 1) ? Int(args[index + 1]) : nil)
        }

        private var mood: TideMood { TideMood(score: score) }

        var body: some View {
            ZStack {
                TideBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Tide.s5) {
                        Text(mood.word).font(Tide.largeTitle).foregroundStyle(Tide.text)
                        TideDial(score: score, caption: "Day score")
                            .frame(maxWidth: .infinity)
                        TideSectionLabel(title: "Fuel", trailing: "56%")
                        VStack(alignment: .leading, spacing: Tide.s3) {
                            TideNumber("1,747", unit: "kcal", size: 44)
                            TideLevelBar(progress: 0.56, color: mood.accent)
                            Text("Secondary text").font(Tide.body).foregroundStyle(Tide.text2)
                            Text("Tertiary text").font(Tide.caption).foregroundStyle(Tide.text3)
                            TideLevelBar(progress: 0.83, color: Tide.protein)
                        }
                        .tideCard()
                        HStack(spacing: Tide.s2) {
                            TideChip(title: "Push day", systemImage: "dumbbell.fill") {}
                            TideChip(title: "57 days", systemImage: "flame.fill") {}
                        }
                        Button("Start workout") {}.buttonStyle(.tidePrimary)
                        Button("Not now") {}.buttonStyle(.tideGlass)
                    }
                    .padding(Tide.edge)
                }
            }
            .environment(\.tideMood, mood)
            .preferredColorScheme(.dark)
        }
    }
#endif
