import Foundation
import Testing
@testable import Branch

struct FileSystemServiceTests {
    @Test func folderSizesIncludeNestedHiddenAndPackageContentsWithoutFollowingLinks() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let package = folder.appendingPathComponent("Nested/Example.app", isDirectory: true)
        try manager.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        try Data(repeating: 1, count: 7).write(to: folder.appendingPathComponent("one.txt"))
        try Data(repeating: 2, count: 11).write(to: folder.appendingPathComponent(".hidden"))
        try Data(repeating: 3, count: 13).write(to: package.appendingPathComponent("data"))
        let external = root.appendingPathComponent("outside.txt")
        try Data(repeating: 4, count: 100).write(to: external)
        try manager.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: external)
        try manager.createSymbolicLink(at: folder.appendingPathComponent("cycle"), withDestinationURL: folder)

        let bytes = try FileSystemService().folderSize(at: folder)
        #expect(bytes == 31)
        let empty = root.appendingPathComponent("Empty", isDirectory: true)
        try manager.createDirectory(at: empty, withIntermediateDirectories: false)
        #expect(try FileSystemService().folderSize(at: empty) == 0)
    }

    @Test func folderSizingCooperatesWithCancellation() async throws {
        let task = Task.detached {
            while !Task.isCancelled { await Task.yield() }
            return try FileSystemService().folderSize(at: URL(fileURLWithPath: "/"))
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled folder sizing should stop")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func trashesNonemptyFolderOnceWhenDescendantsAreAlsoSelected() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("Branch-Trash-Test-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let file = folder.appendingPathComponent("keep.txt")
        try Data("test contents".utf8).write(to: file)

        let destinations = try FileSystemService().trash([file, folder, folder])
        let destination = try #require(destinations.first)
        // Restore our generated fixture immediately so the test leaves no Trash.
        defer { try? manager.moveItem(at: destination, to: folder) }
        #expect(destinations.count == 1)
        #expect(!manager.fileExists(atPath: folder.path))
        #expect(try String(contentsOf: destination.appendingPathComponent("keep.txt"), encoding: .utf8) == "test contents")
    }

    @Test func createsRenamesCopiesAndListsFolders() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let service = FileSystemService()
        let created = try service.createFolder(named: "First", in: root)
        #expect(manager.fileExists(atPath: created.path))

        let renamed = try service.rename(created, to: "Renamed")
        #expect(renamed.lastPathComponent == "Renamed")

        try service.copy([renamed], to: root)
        let folders = service.folders(in: root, showHidden: false)
        #expect(folders.map(\.name) == ["Renamed", "Renamed copy"])
    }

    @Test func rejectsUnsafeNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = FileSystemService()
        #expect(throws: FileSystemError.self) {
            try service.createFolder(named: "../bad", in: root)
        }
    }

    @Test func applicationBundlesAreLaunchableItemsNotTreeFolders() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let application = root.appendingPathComponent("Example.app", isDirectory: true)
        try manager.createDirectory(at: application, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let service = FileSystemService()
        let items = try service.contents(of: root, showHidden: false)
        let appItem = try #require(items.first)

        #expect(appItem.isDirectory)
        #expect(appItem.isApplicationBundle)
        #expect(appItem.kindDescription == "Application")
        #expect(service.folders(in: root, showHidden: false).isEmpty)
    }

    @Test func searchesRecursivelyAndCaseInsensitively() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let match = nested.appendingPathComponent("Needle.TXT")
        let nonMatch = nested.appendingPathComponent("unrelated.txt")
        try Data().write(to: match)
        try Data().write(to: nonMatch)

        let results = try FileSystemService().search(in: root, query: "needle", showHidden: false)

        #expect(results.map(\.name) == ["Needle.TXT"])
    }

    @Test func symbolicLinkToFolderIsNavigable() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = root.appendingPathComponent("CloudStorage/GoogleDrive-user@example.com", isDirectory: true)
        let link = root.appendingPathComponent("GoogleDrive-user@example.com")
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: link, withDestinationURL: destination)
        defer { try? manager.removeItem(at: root) }

        let item = try #require(FileSystemService().contents(of: root, showHidden: false).first {
            $0.url == link.standardizedFileURL
        })

        #expect(item.isSymbolicLink)
        #expect(item.isDirectory)
        #expect(item.kindDescription.localizedCaseInsensitiveContains("symbolic"))
        #expect(FileSystemService().folders(in: root, showHidden: false).contains(item))
    }
}
