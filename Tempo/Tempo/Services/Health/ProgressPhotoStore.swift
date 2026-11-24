//
// ProgressPhotoStore.swift
// Tempo
//
// Optional progress photos, kept only on this phone: JPEG files in the app's
// Documents folder. Nothing here touches the network, SwiftData or the backend,
// and nothing else reads this folder. The photo's date is part of its file
// name, so there is no index to lose or to corrupt.
//

import Foundation
import ImageIO
import UIKit

// MARK: - ProgressPhoto

struct ProgressPhoto: Identifiable, Equatable {
    /// The file name, without the folder.
    let id: String
    let date: Date
    let url: URL
}

// MARK: - ProgressPhotoStore

struct ProgressPhotoStore {
    /// Where the photos live. The default is `Documents/ProgressPhotos`.
    let folder: URL

    /// Longest side of a stored photo, in pixels. Phone cameras write 12 MP and
    /// more; a progress photo does not need it.
    static let maxStoredDimension: CGFloat = 2048

    init(folder: URL = ProgressPhotoStore.defaultFolder) {
        self.folder = folder
    }

    static var defaultFolder: URL {
        URL.documentsDirectory.appending(path: "ProgressPhotos", directoryHint: .isDirectory)
    }

    // MARK: File names

    /// "20261124-081530-3F2A9C1B.jpg": the local date and time, then a short token
    /// so two photos in the same second never share a name.
    static func fileName(for date: Date, token: String = UUID().uuidString.prefix(8).uppercased()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d%02d-%@.jpg",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, token
        )
    }

    /// The date a file name carries. Nil for any file that is not one of ours.
    static func date(fromFileName name: String) -> Date? {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, name.hasSuffix(".jpg"), parts[0].count == 8, parts[1].count == 6,
              let day = Int(parts[0]), let time = Int(parts[1])
        else {
            return nil
        }
        return Calendar.current.date(from: DateComponents(
            year: day / 10000, month: day / 100 % 100, day: day % 100,
            hour: time / 10000, minute: time / 100 % 100, second: time % 100
        ))
    }

    // MARK: Reading

    /// Every photo, newest first. Files that are not ours are ignored.
    func photos() -> [ProgressPhoto] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .compactMap { name -> ProgressPhoto? in
                guard let date = Self.date(fromFileName: name) else {
                    return nil
                }
                return ProgressPhoto(id: name, date: date, url: folder.appending(path: name))
            }
            .sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    // MARK: Writing

    /// Saves a photo and returns it. The folder is made on first use.
    @discardableResult
    func add(jpegData: Data, date: Date = Date()) throws -> ProgressPhoto {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = Self.fileName(for: date)
        let url = folder.appending(path: name)
        // Readable only while the phone is unlocked.
        try jpegData.write(to: url, options: [.atomic, .completeFileProtection])
        return ProgressPhoto(id: name, date: Self.date(fromFileName: name) ?? date, url: url)
    }

    /// Deletes one photo. Only a file in the folder, named like ours, can go.
    func delete(_ photo: ProgressPhoto) throws {
        guard Self.date(fromFileName: photo.id) != nil, photo.id == photo.url.lastPathComponent else {
            return
        }
        try FileManager.default.removeItem(at: folder.appending(path: photo.id))
    }

    // MARK: Images

    /// A photo, scaled so its longest side is at most `maxStoredDimension`, as JPEG.
    static func jpegData(from image: UIImage, quality: CGFloat = 0.85) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else {
            return nil
        }
        let scale = min(1, maxStoredDimension / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return scaled.jpegData(compressionQuality: quality)
    }

    /// A small copy of a stored photo for a grid, cheap to decode.
    func thumbnail(for photo: ProgressPhoto, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(photo.url as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }

    /// The photo at full stored size.
    func image(for photo: ProgressPhoto) -> UIImage? {
        UIImage(contentsOfFile: photo.url.path)
    }
}
