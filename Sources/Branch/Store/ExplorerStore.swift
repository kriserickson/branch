import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ExplorerStore {
    private(set) var tabs: [ExplorerTab]
    var selectedTabID: UUID
    var items: [FileItem] = []
    var expandedFolders: Set<URL> = []
    var showHiddenFiles = false
    var showsInspector = true
    var isLoading = false
    var errorMessage: String?
    var renameTarget: URL?
    var renameText = ""
    var showsRenamePrompt = false
    var newFolderText = "Untitled Folder"
    var showsNewFolderPrompt = false
    var showsDeleteConfirmation = false
    var showsToolSettings = false
    private(set) var enabledDirectoryToolIDs: Set<DirectoryToolID>
    var preferredMergeToolID: MergeToolID?

    private let fileSystem = FileSystemService()
    private let externalTools = ExternalToolService()
    private var clipboardURLs: [URL] = []
    private var clipboardIsCut = false
    private var loadTask: Task<Void, Never>?
    private let favoritesDefaultsKey = "Branch.favoriteFolderPaths"
    private let directoryToolsDefaultsKey = "Branch.enabledDirectoryTools"
    private let mergeToolDefaultsKey = "Branch.preferredMergeTool"

    let rootURL = URL(fileURLWithPath: "/", isDirectory: true).standardizedFileURL
    let homeURL: URL
    private(set) var favoriteURLs: [URL]
    private(set) var installedDirectoryTools: [InstalledTool<DirectoryToolID>]
    private(set) var installedMergeTools: [InstalledTool<MergeToolID>]

    init(startingAt url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let detectedDirectoryTools = Self.detectInstalledDirectoryTools()
        let detectedMergeTools = Self.detectInstalledMergeTools()
        let resolvedHomeURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let defaultFavorites = [
            resolvedHomeURL,
            resolvedHomeURL.appendingPathComponent("Desktop", isDirectory: true),
            resolvedHomeURL.appendingPathComponent("Documents", isDirectory: true),
            resolvedHomeURL.appendingPathComponent("Downloads", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        ]
        let resolvedFavorites: [URL]
        if let savedPaths = UserDefaults.standard.array(forKey: favoritesDefaultsKey) as? [String] {
            resolvedFavorites = savedPaths
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        } else {
            resolvedFavorites = defaultFavorites.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        let savedDirectoryToolIDs = UserDefaults.standard.stringArray(forKey: directoryToolsDefaultsKey)?
            .compactMap(DirectoryToolID.init(rawValue:))
        let resolvedEnabledDirectoryToolIDs = Set(savedDirectoryToolIDs ?? detectedDirectoryTools.map(\.id))
        let resolvedMergeToolID: MergeToolID?
        if let savedMergeTool = UserDefaults.standard.string(forKey: mergeToolDefaultsKey) {
            resolvedMergeToolID = MergeToolID(rawValue: savedMergeTool)
        } else {
            resolvedMergeToolID = detectedMergeTools.first?.id
        }
        let tab = ExplorerTab(url: url)
        installedDirectoryTools = detectedDirectoryTools
        installedMergeTools = detectedMergeTools
        enabledDirectoryToolIDs = resolvedEnabledDirectoryToolIDs
        preferredMergeToolID = resolvedMergeToolID
        homeURL = resolvedHomeURL
        favoriteURLs = resolvedFavorites
        tabs = [tab]
        selectedTabID = tab.id
        syncTree(to: url)
        reload()
    }

    var selectedTab: ExplorerTab {
        get { tabs.first(where: { $0.id == selectedTabID }) ?? tabs[0] }
        set {
            guard let index = tabs.firstIndex(where: { $0.id == newValue.id }) else { return }
            tabs[index] = newValue
        }
    }

    var currentURL: URL { selectedTab.currentURL }
    var selectedItems: [FileItem] { items.filter { selectedTab.selectedURLs.contains($0.url) } }
    var canPaste: Bool { !clipboardURLs.isEmpty }

    var displayedItems: [FileItem] {
        let query = selectedTab.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return filtered.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            let comparison: ComparisonResult
            switch selectedTab.sort {
            case .name:
                comparison = lhs.name.localizedStandardCompare(rhs.name)
            case .kind:
                comparison = lhs.kindDescription.localizedStandardCompare(rhs.kindDescription)
            case .dateModified:
                comparison = (lhs.modifiedDate ?? .distantPast).compare(rhs.modifiedDate ?? .distantPast)
            case .size:
                let leftSize = lhs.fileSize ?? 0
                let rightSize = rhs.fileSize ?? 0
                comparison = leftSize == rightSize ? .orderedSame : (leftSize < rightSize ? .orderedAscending : .orderedDescending)
            }
            let resolved = comparison == .orderedSame ? lhs.name.localizedStandardCompare(rhs.name) : comparison
            return selectedTab.sortAscending ? resolved == .orderedAscending : resolved == .orderedDescending
        }
    }

    func tabBinding(_ id: UUID) -> BindingProxy<ExplorerTab>? {
        guard tabs.contains(where: { $0.id == id }) else { return nil }
        return BindingProxy(
            get: { [weak self] in self?.tabs.first(where: { $0.id == id }) ?? ExplorerTab(url: URL(fileURLWithPath: "/")) },
            set: { [weak self] tab in
                guard let self, let index = self.tabs.firstIndex(where: { $0.id == id }) else { return }
                self.tabs[index] = tab
            }
        )
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        syncTree(to: currentURL)
        reload()
    }

    func newTab(at url: URL? = nil) {
        let tab = ExplorerTab(url: url ?? currentURL)
        tabs.append(tab)
        selectTab(tab.id)
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
            syncTree(to: currentURL)
            reload()
        }
    }

    func navigate(to url: URL, addToHistory: Bool = true) {
        let destination = url.standardizedFileURL
        var tab = selectedTab
        if addToHistory {
            guard destination != tab.currentURL else { return }
            tab.history = Array(tab.history.prefix(tab.historyIndex + 1))
            tab.history.append(destination)
            tab.historyIndex = tab.history.count - 1
        }
        tab.selectedURLs = []
        tab.selectionAnchorURL = nil
        tab.searchText = ""
        selectedTab = tab
        syncTree(to: destination)
        reload()
    }

    func goBack() {
        var tab = selectedTab
        guard tab.canGoBack else { return }
        tab.historyIndex -= 1
        tab.selectedURLs = []
        tab.selectionAnchorURL = nil
        selectedTab = tab
        syncTree(to: currentURL)
        reload()
    }

    func goForward() {
        var tab = selectedTab
        guard tab.canGoForward else { return }
        tab.historyIndex += 1
        tab.selectedURLs = []
        tab.selectionAnchorURL = nil
        selectedTab = tab
        syncTree(to: currentURL)
        reload()
    }

    func goUp() {
        guard currentURL.path != "/" else { return }
        navigate(to: currentURL.deletingLastPathComponent())
    }

    func open(_ item: FileItem) {
        if item.isApplicationBundle { NSWorkspace.shared.openApplication(at: item.url, configuration: .init()) }
        else if item.isDirectory { navigate(to: item.url) }
        else { NSWorkspace.shared.open(item.url) }
    }

    func openInNewTab(_ item: FileItem) {
        guard item.isDirectory, !item.isApplicationBundle else { return }
        newTab(at: item.url)
    }

    func openPackageContents(_ item: FileItem) {
        guard item.isApplicationBundle else { return }
        navigate(to: item.url)
    }

    func isCurrentOrAncestor(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        let current = currentURL.standardizedFileURL.path
        if candidate == "/" { return true }
        return current == candidate || current.hasPrefix(candidate + "/")
    }

    func reload() {
        loadTask?.cancel()
        let directory = currentURL
        let hidden = showHiddenFiles
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    try FileSystemService().contents(of: directory, showHidden: hidden)
                }.value
                guard !Task.isCancelled, self.currentURL == directory else { return }
                self.items = loaded
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                self.items = []
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        reload()
    }

    func setSelection(_ urls: Set<URL>) {
        var tab = selectedTab
        tab.selectedURLs = urls
        if urls.isEmpty { tab.selectionAnchorURL = nil }
        else if urls.count == 1 { tab.selectionAnchorURL = urls.first }
        selectedTab = tab
    }

    func select(_ item: FileItem, modifiers: NSEvent.ModifierFlags) {
        var tab = selectedTab
        let result = SelectionResolver.resolve(
            clickedURL: item.url,
            orderedURLs: displayedItems.map(\.url),
            selectedURLs: tab.selectedURLs,
            anchorURL: tab.selectionAnchorURL,
            modifiers: modifiers
        )
        tab.selectedURLs = result.selectedURLs
        tab.selectionAnchorURL = result.anchorURL
        selectedTab = tab
    }

    func ensureSelectedForContextMenu(_ item: FileItem) {
        guard !selectedTab.selectedURLs.contains(item.url) else { return }
        var tab = selectedTab
        tab.selectedURLs = [item.url]
        tab.selectionAnchorURL = item.url
        selectedTab = tab
    }

    func setViewMode(_ mode: ExplorerViewMode) {
        var tab = selectedTab
        tab.viewMode = mode
        selectedTab = tab
    }

    func setSearchText(_ text: String) {
        var tab = selectedTab
        tab.searchText = text
        selectedTab = tab
    }

    func setSort(_ sort: FileSort) {
        var tab = selectedTab
        if tab.sort == sort { tab.sortAscending.toggle() }
        else { tab.sort = sort; tab.sortAscending = true }
        selectedTab = tab
    }

    func folders(in url: URL) -> [FileItem] {
        fileSystem.folders(in: url, showHidden: showHiddenFiles)
    }

    func isFavorite(_ url: URL) -> Bool {
        favoriteURLs.contains(url.standardizedFileURL)
    }

    func addFavorite(_ url: URL) {
        let folder = url.standardizedFileURL
        guard !isFavorite(folder) else { return }
        favoriteURLs.append(folder)
        saveFavorites()
    }

    func removeFavorite(_ url: URL) {
        let folder = url.standardizedFileURL
        favoriteURLs.removeAll { $0.standardizedFileURL == folder }
        saveFavorites()
    }

    func beginRename(_ url: URL) {
        renameTarget = url
        renameText = url.lastPathComponent
        showsRenamePrompt = true
    }

    func commitRename() {
        guard let target = renameTarget else { return }
        perform { try fileSystem.rename(target, to: renameText) }
        renameTarget = nil
    }

    func createFolder() {
        perform { try fileSystem.createFolder(named: newFolderText, in: currentURL) }
        newFolderText = "Untitled Folder"
    }

    func copySelection(cut: Bool = false) {
        clipboardURLs = selectedTab.selectedURLs.sorted { $0.path < $1.path }
        clipboardIsCut = cut
    }

    func paste() {
        let sources = clipboardURLs
        let isCut = clipboardIsCut
        perform {
            if isCut { try fileSystem.move(sources, to: currentURL) }
            else { try fileSystem.copy(sources, to: currentURL) }
        }
        if isCut { clipboardURLs = []; clipboardIsCut = false }
    }

    func duplicateSelection() {
        let urls = selectedTab.selectedURLs.sorted { $0.path < $1.path }
        perform { try fileSystem.copy(urls, to: currentURL) }
    }

    func trashSelection() {
        let urls = selectedTab.selectedURLs.sorted { $0.path < $1.path }
        perform { try fileSystem.trash(urls) }
    }

    func importURLs(_ urls: [URL], to destination: URL) -> Bool {
        perform { try fileSystem.copy(urls, to: destination) }
        return true
    }

    func revealSelection() {
        guard let url = selectedTab.selectedURLs.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func setDirectoryTool(_ id: DirectoryToolID, enabled: Bool) {
        if enabled { enabledDirectoryToolIDs.insert(id) }
        else { enabledDirectoryToolIDs.remove(id) }
        UserDefaults.standard.set(enabledDirectoryToolIDs.map(\.rawValue).sorted(), forKey: directoryToolsDefaultsKey)
    }

    func setPreferredMergeTool(_ id: MergeToolID?) {
        preferredMergeToolID = id
        if let id { UserDefaults.standard.set(id.rawValue, forKey: mergeToolDefaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: mergeToolDefaultsKey) }
    }

    func openCurrentDirectory(with id: DirectoryToolID) {
        guard enabledDirectoryToolIDs.contains(id),
              let tool = installedDirectoryTools.first(where: { $0.id == id }) else { return }
        do { try externalTools.openDirectory(currentURL, with: tool) }
        catch { errorMessage = error.localizedDescription }
    }

    var mergeableSelection: [URL]? {
        let selection = selectedItems
        guard selection.count == 2, selection.allSatisfy({ !$0.isDirectory }) else { return nil }
        return selection.map(\.url).sorted { $0.path < $1.path }
    }

    var preferredInstalledMergeTool: InstalledTool<MergeToolID>? {
        guard let preferredMergeToolID else { return nil }
        return installedMergeTools.first(where: { $0.id == preferredMergeToolID })
    }

    func compareSelectedFiles() {
        guard let urls = mergeableSelection,
              let tool = preferredInstalledMergeTool else { return }
        do { try externalTools.compare(urls, with: tool) }
        catch { errorMessage = error.localizedDescription }
    }

    private func perform<T>(_ operation: () throws -> T) {
        do {
            _ = try operation()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncTree(to url: URL) {
        let components = url.standardizedFileURL.pathComponents
        guard !components.isEmpty else { return }
        var path = URL(fileURLWithPath: "/", isDirectory: true)
        // Reveal the destination by expanding its ancestors only. Expansion of
        // the destination itself is controlled explicitly by its disclosure
        // caret or a double-click in the tree.
        if components.count > 1 {
            expandedFolders.insert(path)
        }
        for component in components.dropFirst().dropLast() {
            path.appendPathComponent(component, isDirectory: true)
            expandedFolders.insert(path.standardizedFileURL)
        }
    }

    private func saveFavorites() {
        UserDefaults.standard.set(favoriteURLs.map(\.path), forKey: favoritesDefaultsKey)
    }

    private static func detectInstalledDirectoryTools() -> [InstalledTool<DirectoryToolID>] {
        DirectoryToolID.allCases.compactMap { id in
            guard let path = id.applicationPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
            return InstalledTool(id: id, applicationURL: URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    private static func detectInstalledMergeTools() -> [InstalledTool<MergeToolID>] {
        MergeToolID.allCases.compactMap { id in
            guard let path = id.applicationPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return nil }
            return InstalledTool(id: id, applicationURL: URL(fileURLWithPath: path, isDirectory: true))
        }
    }
}

/// A tiny closure-based proxy used internally where a full SwiftUI binding is unnecessary.
struct BindingProxy<Value> {
    let get: () -> Value
    let set: (Value) -> Void
}
