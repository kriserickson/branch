import Foundation

enum FileSystemError: LocalizedError {
    case notDirectory(URL)
    case nameConflict(String)
    case invalidName

    var errorDescription: String? {
        switch self {
        case .notDirectory(let url): "\(url.lastPathComponent) is not a folder."
        case .nameConflict(let name): "An item named “\(name)” already exists."
        case .invalidName: "Enter a valid file or folder name."
        }
    }
}

struct FileSystemService {
    private let manager = FileManager.default
    private static let keys: Set<URLResourceKey> = [
        .localizedNameKey, .isDirectoryKey, .isHiddenKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .contentTypeKey,
        .isReadableKey, .isVolumeKey
    ]

    func contents(of directory: URL, showHidden: Bool) throws -> [FileItem] {
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileSystemError.notDirectory(directory)
        }

        return try manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.keys),
            options: showHidden ? [] : [.skipsHiddenFiles]
        ).compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Self.keys) else { return nil }
            return FileItem(url: url, resourceValues: values)
        }
    }

    func search(in directory: URL, query: String, showHidden: Bool) throws -> [FileItem] {
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FileSystemError.notDirectory(directory)
        }

        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try contents(of: directory, showHidden: showHidden) }

        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(Self.keys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var matches: [FileItem] = []
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Self.keys) else { continue }
            let item = FileItem(url: url, resourceValues: values)
            if item.name.localizedCaseInsensitiveContains(query) {
                matches.append(item)
            }

            // Treat application bundles as files instead of searching through
            // their package contents, matching the rest of the explorer.
            if item.isApplicationBundle {
                enumerator.skipDescendants()
            }
        }
        return matches
    }

    func folders(in directory: URL, showHidden: Bool) -> [FileItem] {
        (try? contents(of: directory, showHidden: showHidden))?
            .filter { $0.isDirectory && !$0.isApplicationBundle }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } ?? []
    }

    func createFolder(named rawName: String, in directory: URL) throws -> URL {
        let name = try validated(name: rawName)
        let destination = directory.appendingPathComponent(name, isDirectory: true)
        guard !manager.fileExists(atPath: destination.path) else { throw FileSystemError.nameConflict(name) }
        try manager.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }

    func rename(_ source: URL, to rawName: String) throws -> URL {
        let name = try validated(name: rawName)
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if source.standardizedFileURL == destination.standardizedFileURL { return source }
        guard !manager.fileExists(atPath: destination.path) else { throw FileSystemError.nameConflict(name) }
        try manager.moveItem(at: source, to: destination)
        return destination
    }

    func copy(_ sources: [URL], to directory: URL) throws {
        for source in sources {
            let destination = availableDestination(for: source, in: directory, copySuffix: true)
            try manager.copyItem(at: source, to: destination)
        }
    }

    func move(_ sources: [URL], to directory: URL) throws {
        for source in sources where source.deletingLastPathComponent().standardizedFileURL != directory.standardizedFileURL {
            let proposed = directory.appendingPathComponent(source.lastPathComponent)
            guard !manager.fileExists(atPath: proposed.path) else { throw FileSystemError.nameConflict(source.lastPathComponent) }
            try manager.moveItem(at: source, to: proposed)
        }
    }

    func trash(_ urls: [URL]) throws {
        for url in urls {
            var result: NSURL?
            try manager.trashItem(at: url, resultingItemURL: &result)
        }
    }

    private func validated(name rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            throw FileSystemError.invalidName
        }
        return name
    }

    private func availableDestination(for source: URL, in directory: URL, copySuffix: Bool) -> URL {
        let first = directory.appendingPathComponent(source.lastPathComponent)
        guard manager.fileExists(atPath: first.path) else { return first }

        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let suffix = counter == 1 ? " copy" : " copy \(counter)"
            let filename = ext.isEmpty ? stem + suffix : stem + suffix + "." + ext
            let candidate = directory.appendingPathComponent(filename)
            if !manager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}
