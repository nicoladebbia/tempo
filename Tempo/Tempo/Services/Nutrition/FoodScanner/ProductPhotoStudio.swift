//
// ProductPhotoStudio.swift
// Tempo
//
// Turns a quick phone photo of a product into a clean catalogue shot: the
// product is cut out on-device (Vision's subject lifting — the same as
// "Lift subject" in Photos), centred on a white square with a soft shadow,
// at 1024 × 1024. Free, instant, private: nothing leaves the phone. If no
// subject is found (blurry, cluttered), the original is centre-cropped instead.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

// MARK: - ProductPhotoStudio

enum ProductPhotoStudio {
    static let outputSide: CGFloat = 1024

    struct Output: Sendable {
        let jpegData: Data
        /// The subject was cut out (false = plain centre crop fallback).
        let isCutOut: Bool
    }

    /// Runs off the main thread; safe to call from a Task.
    static func render(_ imageData: Data) async -> Output? {
        await Task.detached(priority: .userInitiated) {
            guard let source = UIImage(data: imageData)?.normalizedOrientation(),
                  let cgImage = source.cgImage
            else {
                return nil
            }
            if let cutOut = liftSubject(cgImage), let composed = compose(cutOut) {
                return Output(jpegData: composed, isCutOut: true)
            }
            return centreCrop(source).map { Output(jpegData: $0, isCutOut: false) }
        }.value
    }

    /// The foreground subject(s) as a transparent-background CIImage, cropped to its bounds.
    static func liftSubject(_ cgImage: CGImage) -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                return nil
            }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            return CIImage(cvPixelBuffer: buffer)
        } catch {
            return nil
        }
    }

    /// Subject centred on white with ~10% margin and a soft drop shadow.
    static func compose(_ subject: CIImage) -> Data? {
        let side = outputSide
        let extent = subject.extent
        guard extent.width > 1, extent.height > 1 else {
            return nil
        }
        let scale = (side * 0.8) / max(extent.width, extent.height)
        let scaled = subject
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGPoint(x: (side - scaled.extent.width) / 2, y: (side - scaled.extent.height) / 2)
        let placed = scaled.transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))

        let shadow = placed
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.18),
            ])
            .applyingGaussianBlur(sigma: 14)
            .transformed(by: CGAffineTransform(translationX: 0, y: -12))

        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let white = CIImage(color: .white).cropped(to: canvas)
        let output = placed.composited(over: shadow.composited(over: white)).cropped(to: canvas)
        return jpeg(output, canvas: canvas)
    }

    static func centreCrop(_ image: UIImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else {
            return nil
        }
        let target = CGSize(width: outputSide, height: outputSide)
        let renderer = UIGraphicsImageRenderer(size: target)
        let scale = outputSide / side
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let result = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(
                x: (outputSide - drawSize.width) / 2,
                y: (outputSide - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            ))
        }
        return result.jpegData(compressionQuality: 0.85)
    }

    private static func jpeg(_ image: CIImage, canvas: CGRect) -> Data? {
        let context = CIContext()
        guard let cg = context.createCGImage(image, from: canvas) else {
            return nil
        }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.88)
    }
}

private extension UIImage {
    /// Camera photos carry EXIF rotation; Vision and CoreImage want it baked in.
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
