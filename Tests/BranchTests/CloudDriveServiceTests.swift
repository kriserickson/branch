import Foundation
import Testing
@testable import Branch

struct CloudDriveServiceTests {
    @Test func discoversAndNamesCloudDriveLocationsWithoutDuplicatingHomeLinks() throws {
        let manager = FileManager.default
        let home = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cloudStorage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let googleDrive = cloudStorage.appendingPathComponent("GoogleDrive-user@example.com", isDirectory: true)
        let oneDrive = cloudStorage.appendingPathComponent("OneDrive-Personal", isDirectory: true)
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try manager.createDirectory(at: googleDrive, withIntermediateDirectories: true)
        try manager.createDirectory(at: oneDrive, withIntermediateDirectories: true)
        try manager.createDirectory(at: iCloud, withIntermediateDirectories: true)
        try manager.createSymbolicLink(
            at: home.appendingPathComponent("GoogleDrive-user@example.com"),
            withDestinationURL: googleDrive
        )
        defer { try? manager.removeItem(at: home) }

        let locations = CloudDriveService().discover(in: home)

        #expect(locations.map(\.name) == [
            "iCloud Drive",
            "Google Drive — user@example.com",
            "OneDrive — Personal"
        ])
        #expect(locations[1].url == googleDrive.standardizedFileURL)
    }
}
