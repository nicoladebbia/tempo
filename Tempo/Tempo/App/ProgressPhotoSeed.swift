//
// ProgressPhotoSeed.swift
// Tempo
//
// The "body-progress" scenario's photos: three clearly marked sample pictures
// dated 8 weeks ago, 4 weeks ago and now, written into the progress-photo
// folder the way the app writes real ones. DEBUG only.
//

import Foundation
import UIKit

#if DEBUG
    enum ProgressPhotoSeed {
        /// Days ago for each sample picture, oldest first.
        static let daysAgo = [56, 28, 0]

        /// Writes the sample pictures. Does nothing when the folder already holds photos.
        @MainActor
        static func seed(now: Date = Date(), store: ProgressPhotoStore = ProgressPhotoStore()) {
            guard store.photos().isEmpty else {
                return
            }
            for (index, days) in daysAgo.enumerated() {
                let date = Calendar.current.date(byAdding: .day, value: -days, to: now)?
                    .addingTimeInterval(days == 0 ? -300 : 0) ?? now
                guard let data = ProgressPhotoStore.jpegData(from: image(index: index, daysAgo: days)) else {
                    continue
                }
                _ = try? store.add(jpegData: data, date: date)
            }
        }

        private static func image(index: Int, daysAgo: Int) -> UIImage {
            let size = CGSize(width: 900, height: 1200)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                let tints = [
                    UIColor(red: 0.20, green: 0.32, blue: 0.55, alpha: 1),
                    UIColor(red: 0.18, green: 0.46, blue: 0.50, alpha: 1),
                    UIColor(red: 0.42, green: 0.30, blue: 0.58, alpha: 1),
                ]
                tints[index % tints.count].setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let figure = UIBezierPath(ovalIn: CGRect(x: 300, y: 220, width: 300, height: 300))
                figure.append(UIBezierPath(roundedRect: CGRect(x: 230, y: 560, width: 440, height: 520), cornerRadius: 200))
                UIColor.white.withAlphaComponent(0.22).setFill()
                figure.fill()
                let text = "Sample photo\n" + (daysAgo == 0 ? "today" : "\(daysAgo) days ago")
                (text as NSString).draw(
                    in: CGRect(x: 60, y: 60, width: 780, height: 160),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                        .foregroundColor: UIColor.white,
                    ]
                )
            }
        }
    }
#endif
