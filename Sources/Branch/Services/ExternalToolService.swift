import AppKit
import Foundation

struct ExternalToolService {
    func openDirectory(_ directory: URL, with tool: InstalledDirectoryTool) {
        switch tool.builtInID {
        case .ghostty:
            // Ghostty's CLI is the most reliable way to set the initial working
            // directory, including when Ghostty is already running.
            launch(
                application: tool.applicationURL,
                arguments: ["--working-directory=\(directory.path)"],
                createsNewApplicationInstance: true
            )
        case .vsCode:
            // Arguments are only honored for a new app instance. Supplying
            // both the flag and the folder fixes the common "VS Code opened,
            // but reused the wrong window" behavior.
            launch(
                application: tool.applicationURL,
                arguments: ["--new-window", directory.path],
                createsNewApplicationInstance: true
            )
        case .terminal, .iTerm, .none:
            // Terminal and iTerm both register public.folder with Launch
            // Services. This avoids AppleScript/Automation permissions and
            // lets each app create its own correctly configured session.
            openURLs([directory], in: tool.applicationURL)
        }
    }

    func compare(_ urls: [URL], with tool: InstalledTool<MergeToolID>) throws {
        guard urls.count == 2 else { return }
        let arguments = switch tool.id {
        case .vsCode: ["--diff"] + urls.map(\.path)
        case .p4merge, .fileMerge: urls.map(\.path)
        }
        launch(application: tool.applicationURL, arguments: arguments)
    }

    private func openURLs(
        _ urls: [URL],
        in application: URL,
        arguments: [String] = [],
        createsNewApplicationInstance: Bool = false
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = createsNewApplicationInstance
        configuration.activates = true
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: application,
            configuration: configuration
        )
    }

    private func launch(
        application: URL,
        arguments: [String],
        createsNewApplicationInstance: Bool = false
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = createsNewApplicationInstance
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: application, configuration: configuration)
    }
}
