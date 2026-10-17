import Foundation
import ImageIO

struct ImageMetadata: Hashable, Sendable {
    let width: Int?
    let height: Int?
    let dateTaken: Date?
    let cameraModel: String?
    let bitDepth: Int?

    var pixelCount: Int64? {
        guard let width, let height else { return nil }
        return Int64(width) * Int64(height)
    }

    var formattedResolution: String? {
        guard let width, let height else { return nil }
        return "\(width) × \(height)"
    }
}

struct ImageMetadataService: Sendable {
    func metadata(at url: URL) -> ImageMetadata? {
        // Read the image header and EXIF dictionaries without decoding a bitmap.
        // Do not trigger an iCloud download just to populate optional columns.
        if let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
           values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded {
            return nil
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] else {
            return nil
        }
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        if let orientation = properties[kCGImagePropertyOrientation] as? NSNumber,
           (5...8).contains(orientation.intValue) {
            swap(&width, &height)
        }
        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let camera: String?
        if let make, !make.isEmpty, let model, !model.isEmpty {
            camera = model.localizedCaseInsensitiveContains(make) ? model : "\(make) \(model)"
        } else {
            camera = [make, model].compactMap { $0 }.first { !$0.isEmpty }
        }
        let depth = (properties[kCGImagePropertyDepth] as? NSNumber)?.intValue
        let colorModel = properties[kCGImagePropertyColorModel] as? String
        let components: Int?
        if colorModel == kCGImagePropertyColorModelRGB as String {
            components = 3
        } else if colorModel == kCGImagePropertyColorModelCMYK as String {
            components = 4
        } else if colorModel == kCGImagePropertyColorModelGray as String {
            components = 1
        } else if colorModel == kCGImagePropertyColorModelLab as String {
            components = 3
        } else {
            components = nil
        }
        let alpha = (properties[kCGImagePropertyHasAlpha] as? Bool) == true ? 1 : 0
        let bitDepth = depth.flatMap { depth in components.map { depth * ($0 + alpha) } }
        return ImageMetadata(
            width: width, height: height,
            dateTaken: Self.dateTaken(
                exif[kCGImagePropertyExifDateTimeOriginal] as? String,
                offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
            ),
            cameraModel: camera, bitDepth: bitDepth
        )
    }

    static func dateTaken(_ timestamp: String?, offset: String?) -> Date? {
        guard let timestamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        // Older EXIF has no time zone; display that local camera time as written.
        formatter.timeZone = .current
        if let offset, !offset.isEmpty {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            return formatter.date(from: timestamp + offset)
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: timestamp)
    }
}
