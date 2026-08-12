import AppKit
import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isHidden: Bool
    let fileSize: Int64?
    let modifiedDate: Date?
    let creationDate: Date?
    let contentType: UTType?

    var id: URL { url }

    var isApplicationBundle: Bool {
        contentType?.conforms(to: .applicationBundle) == true ||
            url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    var kindDescription: String {
        if isApplicationBundle { return "Application" }
        if isDirectory { return "Folder" }
        return contentType?.localizedDescription ?? url.pathExtension.uppercased()
    }

    var formattedSize: String {
        guard !isDirectory, let fileSize else { return "—" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    init(url: URL, resourceValues: URLResourceValues) {
        self.url = url.standardizedFileURL
        name = resourceValues.localizedName ?? url.lastPathComponent
        isDirectory = resourceValues.isDirectory ?? false
        isHidden = resourceValues.isHidden ?? false
        fileSize = resourceValues.fileSize.map(Int64.init)
        modifiedDate = resourceValues.contentModificationDate
        creationDate = resourceValues.creationDate
        contentType = resourceValues.contentType
    }
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

    var title: String {
        switch self {
        case .name: "Name"
        case .kind: "Kind"
        case .dateModified: "Date Modified"
        case .size: "Size"
        }
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
