import Foundation

struct CloudDriveService {
    private let manager: FileManager

    init(manager: FileManager = .default) {
        self.manager = manager
    }

    func discover(in homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CloudDriveLocation] {
        let home = homeURL.standardizedFileURL
        var candidates: [URL] = []

        let iCloud = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)
        if isDirectory(iCloud) {
            candidates.append(iCloud)
        }

        let cloudStorage = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("CloudStorage", isDirectory: true)
        if let providerURLs = try? manager.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: providerURLs.filter(isDirectory))
        }

        // Some providers also install a convenient link directly in the home
        // directory. Include those for older installs, then de-duplicate them
        // against their modern ~/Library/CloudStorage destination.
        if let homeURLs = try? manager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: homeURLs.filter { url in
                isKnownLegacyCloudName(url.lastPathComponent) && isDirectory(url)
            })
        }

        var seenDestinations = Set<String>()
        let uniqueCandidates = candidates
            .filter { seenDestinations.insert($0.resolvingSymlinksInPath().standardizedFileURL.path).inserted }
        return uniqueCandidates
            .sorted { sortKey(for: $0) < sortKey(for: $1) }
            .map { location(for: $0) }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return manager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isKnownLegacyCloudName(_ name: String) -> Bool {
        let normalized = name.lowercased().replacingOccurrences(of: " ", with: "")
        return ["googledrive", "onedrive", "dropbox", "box", "pcloud", "protondrive"]
            .contains { normalized.hasPrefix($0) }
    }

    private func sortKey(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name == "com~apple~clouddocs" { return "0-icloud" }
        if name.hasPrefix("googledrive") || name.hasPrefix("google drive") { return "1-\(name)" }
        if name.hasPrefix("onedrive") { return "2-\(name)" }
        if name.hasPrefix("dropbox") { return "3-\(name)" }
        return "4-\(name)"
    }

    private func location(for url: URL) -> CloudDriveLocation {
        let component = url.lastPathComponent
        let lowercased = component.lowercased()

        if component == "com~apple~CloudDocs" {
            return CloudDriveLocation(url: url.standardizedFileURL, name: "iCloud Drive", symbol: "icloud")
        }
        if lowercased.hasPrefix("googledrive") || lowercased.hasPrefix("google drive") {
            return CloudDriveLocation(
                url: url.standardizedFileURL,
                name: providerName("Google Drive", component: component, prefixes: ["GoogleDrive", "Google Drive"]),
                symbol: "externaldrive.connected.to.line.below"
            )
        }
        if lowercased.hasPrefix("onedrive") {
            return CloudDriveLocation(
                url: url.standardizedFileURL,
                name: providerName("OneDrive", component: component, prefixes: ["OneDrive"]),
                symbol: "cloud"
            )
        }
        if lowercased.hasPrefix("dropbox") {
            return CloudDriveLocation(
                url: url.standardizedFileURL,
                name: providerName("Dropbox", component: component, prefixes: ["Dropbox"]),
                symbol: "shippingbox"
            )
        }
        if lowercased.hasPrefix("box") {
            return CloudDriveLocation(url: url.standardizedFileURL, name: component, symbol: "shippingbox")
        }
        return CloudDriveLocation(url: url.standardizedFileURL, name: component, symbol: "externaldrive")
    }

    private func providerName(_ provider: String, component: String, prefixes: [String]) -> String {
        var detail = component
        for prefix in prefixes where detail.lowercased().hasPrefix(prefix.lowercased()) {
            detail.removeFirst(prefix.count)
            break
        }
        detail = detail.trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
        return detail.isEmpty ? provider : "\(provider) — \(detail)"
    }
}
