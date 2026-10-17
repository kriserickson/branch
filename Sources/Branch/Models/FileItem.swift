import AppKit
import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isHidden: Bool
    let fileSize: Int64?
    let modifiedDate: Date?
    let creationDate: Date?
    let accessedDate: Date?
    let contentType: UTType?
    var folderSize: FolderSize = .pending
    var imageMetadata: ImageMetadata?

    var id: URL { url }

    var isApplicationBundle: Bool {
        contentType?.conforms(to: .applicationBundle) == true ||
            url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    var kindDescription: String {
        if isApplicationBundle { return "Application" }
        if isSymbolicLink { return contentType?.localizedDescription ?? "Symbolic Link" }
        if isDirectory { return "Folder" }
        return contentType?.localizedDescription ?? url.pathExtension.uppercased()
    }

    var formattedSize: String {
        if isDirectory && !isSymbolicLink {
            switch folderSize {
            case .pending: return "Calculating…"
            case .unavailable: return "Unavailable"
            case .complete(let bytes): return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
        }
        guard let fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var sizeForSorting: Int64? {
        if isDirectory && !isSymbolicLink {
            if case .complete(let bytes) = folderSize { return bytes }
            return nil
        }
        return fileSize
    }

    func text(for column: FileSort) -> String {
        switch column {
        case .name: name
        case .kind: kindDescription
        case .dateModified: modifiedDate?.formatted(date: .abbreviated, time: .shortened) ?? "—"
        case .size: formattedSize
        case .dateCreated: creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "—"
        case .dateAccessed: accessedDate?.formatted(date: .abbreviated, time: .shortened) ?? "—"
        case .fileExtension: url.pathExtension.isEmpty ? "—" : url.pathExtension
        case .folderPath: url.deletingLastPathComponent().path
        case .resolution: imageMetadata?.formattedResolution ?? "—"
        case .dateTaken: imageMetadata?.dateTaken?.formatted(date: .abbreviated, time: .shortened) ?? "—"
        case .cameraModel: imageMetadata?.cameraModel ?? "—"
        case .bitDepth: imageMetadata?.bitDepth.map { "\($0) bit" } ?? "—"
        }
    }

    init(url: URL, resourceValues: URLResourceValues) {
        self.url = url.standardizedFileURL
        name = resourceValues.localizedName ?? url.lastPathComponent
        isSymbolicLink = resourceValues.isSymbolicLink ?? false
        if isSymbolicLink {
            let destination = url.resolvingSymlinksInPath()
            isDirectory = (try? destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        } else {
            isDirectory = resourceValues.isDirectory ?? false
        }
        isHidden = resourceValues.isHidden ?? false
        fileSize = resourceValues.fileSize.map(Int64.init)
        modifiedDate = resourceValues.contentModificationDate
        creationDate = resourceValues.creationDate
        accessedDate = resourceValues.contentAccessDate
        contentType = resourceValues.contentType
    }
}

enum FolderSize: Hashable, Sendable {
    case pending
    case complete(Int64)
    case unavailable
}

enum ExplorerViewMode: String, CaseIterable, Sendable {
    case list
    case icons

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .icons: "square.grid.2x2"
        }
    }

    var title: String { rawValue.capitalized }
}

enum FileSort: String, CaseIterable, Sendable {
    case name
    case kind
    case dateModified
    case size
    case dateCreated
    case dateAccessed
    case fileExtension
    case folderPath
    case resolution
    case dateTaken
    case cameraModel
    case bitDepth

    static let defaultColumns: [FileSort] = [.name, .dateModified, .kind, .size]

    var width: CGFloat {
        switch self {
        case .name: 220
        case .dateModified, .dateCreated, .dateAccessed, .dateTaken: 175
        case .kind: 140
        case .size: 105
        case .fileExtension, .bitDepth: 95
        case .resolution: 135
        case .cameraModel: 170
        case .folderPath: 260
        }
    }

    var needsImageMetadata: Bool {
        [.resolution, .dateTaken, .cameraModel, .bitDepth].contains(self)
    }

    var title: String {
        switch self {
        case .name: "Name"
        case .kind: "Kind"
        case .dateModified: "Date Modified"
        case .size: "Size"
        case .dateCreated: "Date Created"
        case .dateAccessed: "Date Accessed"
        case .fileExtension: "Extension"
        case .folderPath: "Folder Path"
        case .resolution: "Resolution"
        case .dateTaken: "Date Taken"
        case .cameraModel: "Camera Model"
        case .bitDepth: "Bit Depth"
        }
    }

    func precedes(_ lhs: FileItem, _ rhs: FileItem, ascending: Bool) -> Bool {
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        func compare<T: Comparable>(_ left: T?, _ right: T?) -> ComparisonResult {
            switch (left, right) {
            case (nil, nil): .orderedSame
            case (nil, _): ascending ? .orderedDescending : .orderedAscending
            case (_, nil): ascending ? .orderedAscending : .orderedDescending
            case (.some(let left), .some(let right)):
                left == right ? .orderedSame : (left < right ? .orderedAscending : .orderedDescending)
            }
        }
        let comparison: ComparisonResult = switch self {
        case .name: lhs.name.localizedStandardCompare(rhs.name)
        case .kind: lhs.kindDescription.localizedStandardCompare(rhs.kindDescription)
        case .dateModified: compare(lhs.modifiedDate, rhs.modifiedDate)
        case .size: compare(lhs.sizeForSorting, rhs.sizeForSorting)
        case .dateCreated: compare(lhs.creationDate, rhs.creationDate)
        case .dateAccessed: compare(lhs.accessedDate, rhs.accessedDate)
        case .fileExtension: lhs.url.pathExtension.localizedStandardCompare(rhs.url.pathExtension)
        case .folderPath: lhs.url.deletingLastPathComponent().path.localizedStandardCompare(rhs.url.deletingLastPathComponent().path)
        case .resolution: compare(lhs.imageMetadata?.pixelCount, rhs.imageMetadata?.pixelCount)
        case .dateTaken: compare(lhs.imageMetadata?.dateTaken, rhs.imageMetadata?.dateTaken)
        case .cameraModel: compare(lhs.imageMetadata?.cameraModel, rhs.imageMetadata?.cameraModel)
        case .bitDepth: compare(lhs.imageMetadata?.bitDepth, rhs.imageMetadata?.bitDepth)
        }
        let resolved = comparison == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : comparison
        return ascending ? resolved == .orderedAscending : resolved == .orderedDescending
    }
}

struct ExplorerTab: Identifiable, Sendable {
    let id: UUID
    var history: [URL]
    var historyIndex: Int
    var selectedURLs: Set<URL>
    var selectionAnchorURL: URL?
    var viewMode: ExplorerViewMode
    var sort: FileSort
    var sortAscending: Bool
    var searchText: String

    init(url: URL) {
        id = UUID()
        history = [url.standardizedFileURL]
        historyIndex = 0
        selectedURLs = []
        selectionAnchorURL = nil
        viewMode = .list
        sort = .name
        sortAscending = true
        searchText = ""
    }

    var currentURL: URL { history[historyIndex] }
    var title: String {
        currentURL.path == "/" ? "Macintosh HD" : currentURL.lastPathComponent
    }
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex + 1 < history.count }
}
