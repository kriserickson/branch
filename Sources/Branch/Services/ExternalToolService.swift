import AppKit
import Foundation

struct ExternalToolService {
    func openDirectory(_ directory: URL, with tool: InstalledTool<DirectoryToolID>) throws {
        switch tool.id {
        case .terminal:
            try runAppleScript(terminalScript(for: directory))
        case .iTerm:
            try launch(
                application: tool.applicationURL,
                arguments: ["--command=cd -- \(shellQuote(directory.path)); exec \"${SHELL:-/bin/zsh}\" -l"]
            )
        case .ghostty:
            try launch(application: tool.applicationURL, arguments: ["--working-directory=\(directory.path)"])
        case .vsCode:
            try launch(application: tool.applicationURL, arguments: [directory.path])
        }
    }

    func compare(_ urls: [URL], with tool: InstalledTool<MergeToolID>) throws {
        guard urls.count == 2 else { return }
        let arguments = switch tool.id {
        case .vsCode: ["--diff"] + urls.map(\.path)
        case .p4merge, .fileMerge: urls.map(\.path)
        }
        try launch(application: tool.applicationURL, arguments: arguments)
    }

    private func launch(application: URL, arguments: [String]) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application, configuration: configuration)
    }

    private func terminalScript(for directory: URL) -> String {
        let command = "cd -- \(shellQuote(directory.path))"
        return """
        tell application "Terminal"
            activate
            do script \(appleScriptString(command))
        end tell
        """
    }

    private func runAppleScript(_ source: String) throws {
        var error: NSDictionary?
        guard NSAppleScript(source: source)?.executeAndReturnError(&error) != nil else {
            let message = error?[NSAppleScript.errorMessage] as? String ?? "The script could not be run."
            throw NSError(domain: "Branch.ExternalTool", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
