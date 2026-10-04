//
// LabelCrop.swift
// Tempo
//
// Crops a nutrition-label photo to the label itself for the "label card" shown
// after capture. Vision finds the biggest rectangle; when it finds nothing
// usable the crop falls back to a centred 4:3-ish window. The rectangle math
// is pure so it can be tested without an image.
//

import UIKit
import Vision

enum LabelCrop {
    /// A detected box smaller than this share of the photo is noise, not a label.
    static let minimumAreaShare: CGFloat = 0.12
    /// Breathing room kept around a detected label (share of its size).
    static let padding: CGFloat = 0.04
    /// Fallback window: centred, this share of the width, 4:3 landscape-ish
    /// (labels are usually wider than tall), clamped to the photo.
    static let fallbackWidthShare: CGFloat = 0.9
    static let fallbackAspect: CGFloat = 4.0 / 3.0

    /// Pixel rect (top-left origin) to crop. `normalizedBox` is Vision's
    /// bottom-left-origin 0...1 box, or nil when nothing was detected.
    static func cropRect(normalizedBox: CGRect?, imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }
        if let box = normalizedBox, box.width > 0, box.height > 0,
           box.width * box.height >= minimumAreaShare {
            let pixel = CGRect(
                x: box.minX * imageSize.width,
                y: (1 - box.maxY) * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
            let padded = pixel.insetBy(dx: -pixel.width * padding, dy: -pixel.height * padding)
            let clamped = padded.intersection(bounds)
            if !clamped.isNull, clamped.width > 0, clamped.height > 0 {
                return clamped
            }
        }
        return fallbackRect(imageSize: imageSize)
    }

    /// Centred crop used when no label rectangle is found.
    static func fallbackRect(imageSize: CGSize) -> CGRect {
        var width = imageSize.width * fallbackWidthShare
        var height = width / fallbackAspect
        if height > imageSize.height * fallbackWidthShare {
            height = imageSize.height * fallbackWidthShare
            width = min(imageSize.width, height * fallbackAspect)
        }
        return CGRect(
            x: (imageSize.width - width) / 2,
            y: (imageSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// The photo cropped to the label (or the fallback window). Never fails:
    /// returns the original if it can't be cropped.
    static func cropped(_ image: UIImage) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            let upright = normalized(image)
            guard let cgImage = upright.cgImage else {
                return image
            }
            let size = CGSize(width: cgImage.width, height: cgImage.height)
            let rect = cropRect(normalizedBox: detectLabelBox(in: cgImage), imageSize: size).integral
            guard let piece = cgImage.cropping(to: rect) else {
                return image
            }
            return UIImage(cgImage: piece, scale: 1, orientation: .up)
        }.value
    }

    private static func detectLabelBox(in cgImage: CGImage) -> CGRect? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 3
        request.minimumConfidence = 0.5
        request.minimumAspectRatio = 0.3
        request.minimumSize = 0.2
        request.quadratureTolerance = 30
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        guard (try? handler.perform([request])) != nil else {
            return nil
        }
        return request.results?
            .map(\.boundingBox)
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Bakes the camera orientation into the pixels so Vision and cropping agree.
    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
