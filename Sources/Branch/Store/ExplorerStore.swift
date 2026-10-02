import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

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
    private(set) var enabledDirectoryToolIDs: Set<String>
    var preferredMergeToolID: MergeToolID?

    private let fileSystem = FileSystemService()
    private let cloudDrives = CloudDriveService()
    private let externalTools = ExternalToolService()
    private var clipboardURLs: [URL] = []
    private var clipboardIsCut = false
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private let favoritesDefaultsKey = "Branch.favoriteFolderPaths"
    private let hiddenFilesDefaultsKey = "Branch.showHiddenFiles"
    private let directoryToolsDefaultsKey = "Branch.enabledDirectoryTools"
    private let customDirectoryToolsDefaultsKey = "Branch.customDirectoryTools"
    private let mergeToolDefaultsKey = "Branch.preferredMergeTool"

    let rootURL = URL(fileURLWithPath: "/", isDirectory: true).standardizedFileURL
    let homeURL: URL
    private(set) var favoriteURLs: [URL]
    private(set) var cloudDriveLocations: [CloudDriveLocation]
    private(set) var installedDirectoryTools: [InstalledDirectoryTool]
    private(set) var installedMergeTools: [InstalledTool<MergeToolID>]

    init(startingAt url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        showHiddenFiles = UserDefaults.standard.object(forKey: hiddenFilesDefaultsKey) as? Bool ?? false
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
        let savedDirectoryToolIDs = UserDefaults.standard.stringArray(forKey: directoryToolsDefaultsKey)
        let defaultDirectoryToolIDs = detectedDirectoryTools
            .filter { $0.builtInID != nil }
            .map(\.id)
        let resolvedEnabledDirectoryToolIDs = Set(savedDirectoryToolIDs ?? defaultDirectoryToolIDs)
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
        cloudDriveLocations = CloudDriveService().discover(in: resolvedHomeURL)
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
        loadGeneration &+= 1
        let generation = loadGeneration
        let directory = currentURL
        let hidden = showHiddenFiles
        let query = selectedTab.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        items = []
        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await Task.detached(priority: .userInitiated) {
                    let fileSystem = FileSystemService()
                    if query.isEmpty {
                        return try fileSystem.contents(of: directory, showHidden: hidden)
                    }
                    return try fileSystem.search(in: directory, query: query, showHidden: hidden)
                }.value
                guard self.loadGeneration == generation,
                      self.currentURL == directory,
                      self.selectedTab.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                self.items = loaded
                self.isLoading = false
            } catch {
                guard self.loadGeneration == generation else { return }
                self.items = []
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func toggleHiddenFiles() {
        showHiddenFiles.toggle()
        UserDefaults.standard.set(showHiddenFiles, forKey: hiddenFilesDefaultsKey)
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
        reload()
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
        favoriteURLs.contains { sameLocation($0, url) }
    }

    func addFavorite(_ url: URL) {
        let folder = url.standardizedFileURL
        guard !isFavorite(folder) else { return }
        favoriteURLs.append(folder)
        saveFavorites()
    }

    func removeFavorite(_ url: URL) {
        let folder = url.standardizedFileURL
        favoriteURLs.removeAll { sameLocation($0, folder) }
        saveFavorites()
    }

    func refreshCloudDrives() {
        cloudDriveLocations = cloudDrives.discover(in: homeURL)
    }

    func addFavoriteWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Favorite Folder"
        panel.message = "Choose a cloud drive or any other folder to show in Favorites."
        panel.prompt = "Add to Favorites"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.addFavorite(url)
                self?.refreshCloudDrives()
            }
        }
    }

    func favoriteDisplayName(for url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        if url == homeURL { return "Home" }
        return cloudDriveLocations.first(where: { sameLocation($0.url, url) })?.name
            ?? url.lastPathComponent
    }

    func favoriteSymbol(for url: URL) -> String {
        if url.path == "/" { return "internaldrive" }
        if let cloudDrive = cloudDriveLocations.first(where: { sameLocation($0.url, url) }) {
            return cloudDrive.symbol
        }
        return switch url.lastPathComponent {
        case "Desktop": "desktopcomputer"
        case "Documents": "doc.on.doc"
        case "Downloads": "arrow.down.circle"
        case "Applications": "square.grid.2x2"
        default: url == homeURL ? "house" : "folder"
        }
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
        setDirectoryTool(id.rawValue, enabled: enabled)
    }

    func setDirectoryTool(_ id: String, enabled: Bool) {
        if enabled { enabledDirectoryToolIDs.insert(id) }
        else { enabledDirectoryToolIDs.remove(id) }
        saveEnabledDirectoryTools()
    }

    func restoreDefaultDirectoryTools() {
        enabledDirectoryToolIDs = Set(
            installedDirectoryTools
                .filter { $0.builtInID != nil }
                .map(\.id)
        )
        saveEnabledDirectoryTools()
    }

    func addDirectoryTool(at url: URL) {
        guard let tool = Self.makeInstalledDirectoryTool(at: url), tool.builtInID == nil else { return }
        var paths = UserDefaults.standard.stringArray(forKey: customDirectoryToolsDefaultsKey) ?? []
        let path = tool.applicationURL.path
        guard !paths.contains(path) else {
            enabledDirectoryToolIDs.insert(tool.id)
            saveEnabledDirectoryTools()
            return
        }
        paths.append(path)
        UserDefaults.standard.set(paths, forKey: customDirectoryToolsDefaultsKey)
        installedDirectoryTools = Self.detectInstalledDirectoryTools(customApplicationPaths: paths)
        enabledDirectoryToolIDs.insert(tool.id)
        saveEnabledDirectoryTools()
    }

    func addDirectoryToolWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add Application"
        panel.message = "Choose an application that can open a folder."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                self?.addDirectoryTool(at: url)
            }
        }
    }

    func removeDirectoryTool(_ tool: InstalledDirectoryTool) {
        guard tool.builtInID == nil else { return }
        var paths = UserDefaults.standard.stringArray(forKey: customDirectoryToolsDefaultsKey) ?? []
        paths.removeAll { URL(fileURLWithPath: $0).standardizedFileURL == tool.applicationURL.standardizedFileURL }
        UserDefaults.standard.set(paths, forKey: customDirectoryToolsDefaultsKey)
        installedDirectoryTools = Self.detectInstalledDirectoryTools(customApplicationPaths: paths)
        enabledDirectoryToolIDs.remove(tool.id)
        saveEnabledDirectoryTools()
    }

    func setPreferredMergeTool(_ id: MergeToolID?) {
        preferredMergeToolID = id
        if let id { UserDefaults.standard.set(id.rawValue, forKey: mergeToolDefaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: mergeToolDefaultsKey) }
    }

    func openCurrentDirectory(with id: DirectoryToolID) {
        openCurrentDirectory(with: id.rawValue)
    }

    func openCurrentDirectory(with id: String) {
        openDirectory(currentURL, with: id)
    }

    func openDirectory(_ directory: URL, with id: String) {
        guard enabledDirectoryToolIDs.contains(id),
              let tool = installedDirectoryTools.first(where: { $0.id == id }) else { return }
        externalTools.openDirectory(directory, with: tool)
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
        var expanded = expandedFolders
        // Reveal the destination by expanding its ancestors only. Expansion of
        // the destination itself is controlled explicitly by its disclosure
        // caret or a double-click in the tree.
        if components.count > 1 {
            expanded.insert(path)
        }
        for component in components.dropFirst().dropLast() {
            path.appendPathComponent(component, isDirectory: true)
            expanded.insert(path.standardizedFileURL)
        }
        expandedFolders = expanded
    }

    private func saveFavorites() {
        UserDefaults.standard.set(favoriteURLs.map(\.path), forKey: favoritesDefaultsKey)
    }

    private func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = lhs.standardizedFileURL
        let right = rhs.standardizedFileURL
        return left == right || left.resolvingSymlinksInPath() == right.resolvingSymlinksInPath()
    }

    private func saveEnabledDirectoryTools() {
        UserDefaults.standard.set(enabledDirectoryToolIDs.sorted(), forKey: directoryToolsDefaultsKey)
    }

    private static func detectInstalledDirectoryTools(customApplicationPaths: [String] = UserDefaults.standard.stringArray(forKey: "Branch.customDirectoryTools") ?? []) -> [InstalledDirectoryTool] {
        let builtIns = DirectoryToolID.allCases.compactMap { id -> InstalledDirectoryTool? in
            let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id.bundleIdentifier)
                ?? id.applicationPaths
                    .first(where: { FileManager.default.fileExists(atPath: $0) })
                    .map { URL(fileURLWithPath: $0, isDirectory: true) }
            guard let applicationURL else { return nil }
            return makeInstalledDirectoryTool(at: applicationURL)
        }
        let custom = customApplicationPaths.compactMap { makeInstalledDirectoryTool(at: URL(fileURLWithPath: $0, isDirectory: true)) }
        var seen = Set<String>()
        return (builtIns + custom).filter { seen.insert($0.id).inserted }
    }

    private static func makeInstalledDirectoryTool(at url: URL) -> InstalledDirectoryTool? {
        let applicationURL = url.standardizedFileURL
        guard applicationURL.pathExtension == "app",
              FileManager.default.fileExists(atPath: applicationURL.path) else { return nil }
        let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier
        let builtInID = DirectoryToolID.builtIn(for: bundleIdentifier)
        let id = builtInID?.rawValue ?? bundleIdentifier ?? applicationURL.path
        let name = builtInID?.name
            ?? (Bundle(url: applicationURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle(url: applicationURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
        return InstalledDirectoryTool(
            id: id,
            name: name,
            applicationURL: applicationURL,
            bundleIdentifier: bundleIdentifier,
            builtInID: builtInID
        )
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
