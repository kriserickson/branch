import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Branch

struct ImageMetadataServiceTests {
    @Test func readsImageResolutionAndEXIFWithoutUsingFileDates() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(CGContext(
            data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 160,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2020:06:15 10:30:00",
                kCGImagePropertyExifOffsetTimeOriginal: "+02:00"
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Example", kCGImagePropertyTIFFModel: "Camera"]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        let metadata = try #require(ImageMetadataService().metadata(at: url))
        #expect(metadata.formattedResolution == "40 × 30")
        #expect(metadata.pixelCount == 1200)
        #expect(metadata.cameraModel == "Example Camera")
        #expect(metadata.bitDepth == 24)
        #expect(metadata.dateTaken == ISO8601DateFormatter().date(from: "2020-06-15T08:30:00Z"))
    }

    @Test func invalidOrAbsentEXIFDoesNotBecomeTheFileCreationDate() {
        #expect(ImageMetadataService.dateTaken(nil, offset: nil) == nil)
        #expect(ImageMetadataService.dateTaken("invalid", offset: nil) == nil)
        #expect(ImageMetadataService.dateTaken("2020:06:15 10:30:00", offset: nil) != nil)
    }
}
