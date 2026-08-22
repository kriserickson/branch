import Foundation

enum DirectoryToolID: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case iTerm
    case ghostty
    case vsCode

    var id: String { rawValue }

    var name: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm: "iTerm"
        case .ghostty: "Ghostty"
        case .vsCode: "Visual Studio Code"
        }
    }

    var symbol: String {
        switch self {
        case .terminal, .iTerm, .ghostty: "terminal"
        case .vsCode: "chevron.left.forwardslash.chevron.right"
        }
    }

    var applicationPaths: [String] {
        switch self {
        case .terminal:
            ["/System/Applications/Utilities/Terminal.app", "/Applications/Utilities/Terminal.app"]
        case .iTerm:
            ["/Applications/iTerm.app", "/Applications/iTerm2.app"]
        case .ghostty:
            ["/Applications/Ghostty.app"]
        case .vsCode:
            ["/Applications/Visual Studio Code.app"]
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .vsCode: "com.microsoft.VSCode"
        }
    }

    static func builtIn(for bundleIdentifier: String?) -> DirectoryToolID? {
        guard let bundleIdentifier else { return nil }
        return allCases.first { $0.bundleIdentifier == bundleIdentifier }
    }
}

struct InstalledDirectoryTool: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let applicationURL: URL
    let bundleIdentifier: String?
    let builtInID: DirectoryToolID?

    var symbol: String {
        builtInID?.symbol ?? "app"
    }
}

enum MergeToolID: String, CaseIterable, Identifiable, Sendable {
    case p4merge
    case fileMerge
    case vsCode

    var id: String { rawValue }
    var name: String {
        switch self {
        case .p4merge: "p4merge"
        case .fileMerge: "FileMerge"
        case .vsCode: "Visual Studio Code"
        }
    }

    var applicationPaths: [String] {
        switch self {
        case .p4merge: ["/Applications/p4merge.app"]
        case .fileMerge: ["/Applications/Xcode.app/Contents/Applications/FileMerge.app"]
        case .vsCode: ["/Applications/Visual Studio Code.app"]
        }
    }
}

struct InstalledTool<ID: Identifiable & Hashable>: Identifiable where ID.ID == String {
    let id: ID
    let applicationURL: URL
}
