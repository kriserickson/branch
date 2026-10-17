import AppKit
import Foundation
import Testing
@testable import Branch

struct ExplorerBehaviorTests {
    @Test func deleteShortcutsLeaveTextEditingAndDialogsAlone() {
        for keyCode: UInt16 in [51, 117] {
            for modifiers: NSEvent.ModifierFlags in [[], .command, [.function, .capsLock]] {
                #expect(FileKeyboardShortcut.shouldTrash(keyCode: keyCode, modifiers: modifiers, isEditingText: false, isPresentingDialog: false, hasSelection: true))
            }
            #expect(!FileKeyboardShortcut.shouldTrash(keyCode: keyCode, modifiers: [], isEditingText: true, isPresentingDialog: false, hasSelection: true))
            #expect(!FileKeyboardShortcut.shouldTrash(keyCode: keyCode, modifiers: [], isEditingText: false, isPresentingDialog: true, hasSelection: true))
            #expect(!FileKeyboardShortcut.shouldTrash(keyCode: keyCode, modifiers: [], isEditingText: false, isPresentingDialog: false, hasSelection: false))
        }
        #expect(!FileKeyboardShortcut.shouldTrash(keyCode: 0, modifiers: [], isEditingText: false, isPresentingDialog: false, hasSelection: true))
    }

    @MainActor @Test func trashConfirmationKeepsItsOriginalTargetsAndColumnsPersist() throws {
        let suiteName = "BranchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ExplorerStore(startingAt: root, defaults: defaults)
        let target = URL(fileURLWithPath: "/original-folder")
        store.setSelection([target])
        store.requestTrash()
        store.setSelection([])
        #expect(store.pendingTrashURLs == [target])
        #expect(store.showsDeleteConfirmation)
        store.cancelTrash()
        #expect(store.pendingTrashURLs.isEmpty)

        store.setColumn(.resolution, visible: true)
        store.setColumn(.dateTaken, visible: true)
        store.setColumn(.kind, visible: false)
        store.setColumn(.name, visible: false)
        let restored = ExplorerStore(startingAt: root, defaults: defaults)
        #expect(restored.visibleColumns == [.name, .dateModified, .size, .resolution, .dateTaken])
        restored.setSort(.dateTaken)
        #expect(restored.selectedTab.sort == .dateTaken)
        #expect(restored.selectedTab.sortAscending)
        restored.setSort(.dateTaken)
        #expect(!restored.selectedTab.sortAscending)
    }

    @Test func sizeAndMetadataSortingUseTheirValuesAndKeepMissingValuesLast() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        func item(_ name: String, directory: Bool = false) throws -> FileItem {
            let url = root.appendingPathComponent(name, isDirectory: directory)
            if directory { try manager.createDirectory(at: url, withIntermediateDirectories: false) }
            else { try Data().write(to: url) }
            return FileItem(url: url, resourceValues: try url.resourceValues(forKeys: [.isDirectoryKey, .localizedNameKey]))
        }
        var small = try item("Z small", directory: true)
        small.folderSize = .complete(100)
        var large = try item("A large", directory: true)
        large.folderSize = .complete(900)
        let pending = try item("Pending", directory: true)
        #expect([pending, large, small].sorted { FileSort.size.precedes($0, $1, ascending: true) }.map(\.name) == [small.name, large.name, pending.name])
        #expect([pending, small, large].sorted { FileSort.size.precedes($0, $1, ascending: false) }.map(\.name) == [large.name, small.name, pending.name])

        var photo = try item("photo.jpg")
        photo.imageMetadata = ImageMetadata(width: 4000, height: 3000, dateTaken: Date(timeIntervalSince1970: 100), cameraModel: "Camera", bitDepth: 24)
        let unknown = try item("unknown.jpg")
        #expect(FileSort.resolution.precedes(photo, unknown, ascending: true))
        #expect(FileSort.resolution.precedes(photo, unknown, ascending: false))
        #expect(FileSort.dateTaken.precedes(photo, unknown, ascending: false))
        #expect(FileSort.size.precedes(small, photo, ascending: false))
    }

    @MainActor @Test func folderSizesArriveInTheBackgroundAndNavigationDiscardsOldResults() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = root.appendingPathComponent("First", isDirectory: true)
        let next = root.appendingPathComponent("Next", isDirectory: true)
        try manager.createDirectory(at: first.appendingPathComponent("Old"), withIntermediateDirectories: true)
        try manager.createDirectory(at: next.appendingPathComponent("New"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 123).write(to: next.appendingPathComponent("New/data"))
        defer { try? manager.removeItem(at: root) }
        let suiteName = "BranchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ExplorerStore(startingAt: first, defaults: defaults)
        store.navigate(to: next)
        for _ in 0..<500 {
            if !store.isLoading && !store.isCalculatingFolderSizes { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.errorMessage == nil)
        #expect(store.items.map(\.name) == ["New"])
        #expect(store.items.first?.folderSize == .complete(123))
        #expect(!store.isCalculatingFolderSizes)
    }
}
