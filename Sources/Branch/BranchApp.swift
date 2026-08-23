import AppKit
import SwiftUI

@main
enum BranchApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = BranchAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class BranchAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = ExplorerStore()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installIcon()
        installMainMenu()

        let rootView = ExplorerView(store: store)
            .frame(minWidth: 900, minHeight: 560)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Branch"
        window.setContentSize(NSSize(width: 1240, height: 780))
        window.minSize = NSSize(width: 900, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.sharingType = .readOnly
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("BranchMainWindow")
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        self.window = window

        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func installIcon() {
        if let iconURL = Bundle.main.url(forResource: "BranchIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(menuRoot("Branch", submenu: applicationMenu()))
        mainMenu.addItem(menuRoot("File", submenu: fileMenu()))
        mainMenu.addItem(menuRoot("Edit", submenu: editMenu()))
        mainMenu.addItem(menuRoot("View", submenu: viewMenu()))
        mainMenu.addItem(menuRoot("Navigate", submenu: navigateMenu()))
        mainMenu.addItem(menuRoot("Window", submenu: windowMenu()))
        mainMenu.addItem(menuRoot("Help", submenu: helpMenu()))
        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = mainMenu.items[5].submenu
    }

    private func applicationMenu() -> NSMenu {
        let menu = NSMenu(title: "Branch")
        menu.addItem(item("About Branch", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Hide Branch", #selector(NSApplication.hide(_:)), key: "h"))
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Branch", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Tab", #selector(newTab), key: "t"))
        let newFolderItem = item("New Folder…", #selector(newFolder), key: "n")
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(newFolderItem)
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(closeTab), key: "w"))
        menu.addItem(item("Open", #selector(openSelection), key: "o"))
        menu.addItem(item("Show in Finder", #selector(revealSelection)))
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Cut for Move", #selector(cutSelection), key: "x"))
        menu.addItem(item("Copy", #selector(copySelection), key: "c"))
        menu.addItem(item("Paste", #selector(paste), key: "v"))
        menu.addItem(item("Duplicate", #selector(duplicateSelection), key: "d"))
        menu.addItem(.separator())
        menu.addItem(item("Rename…", #selector(renameSelection), key: "\r", modifiers: []))
        menu.addItem(item("Move to Trash…", #selector(confirmTrash), key: "\u{8}"))
        menu.addItem(.separator())
        menu.addItem(item("Select All", #selector(selectAll), key: "a"))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("as List", #selector(showList), key: "1"))
        menu.addItem(item("as Icons", #selector(showIcons), key: "2"))
        menu.addItem(.separator())
        let inspector = item("Toggle Inspector", #selector(toggleInspector), key: "i")
        inspector.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(inspector)
        let hidden = item(store.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files", #selector(toggleHidden), key: ".")
        hidden.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(hidden)
        menu.addItem(item("Reload", #selector(reload), key: "r"))
        return menu
    }

    private func navigateMenu() -> NSMenu {
        let menu = NSMenu(title: "Navigate")
        menu.addItem(item("Back", #selector(goBack), key: "["))
        menu.addItem(item("Forward", #selector(goForward), key: "]"))
        let up = item("Enclosing Folder", #selector(goUp), key: String(UnicodeScalar(NSUpArrowFunctionKey)!))
        up.keyEquivalentModifierMask = [.command]
        menu.addItem(up)
        menu.addItem(.separator())
        menu.addItem(item("Home", #selector(goHome), key: "h", modifiers: [.command, .shift]))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(minimizeWindow), key: "m"))
        menu.addItem(item("Zoom", #selector(zoomWindow)))
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Branch Help", #selector(showHelp)))
        return menu
    }

    private func menuRoot(_ title: String, submenu: NSMenu) -> NSMenuItem {
        let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        root.submenu = submenu
        return root
    }

    private func item(
        _ title: String,
        _ action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = action.description.contains("hide") || action.description.contains("terminate") ? nil : self
        menuItem.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return menuItem
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Branch",
            .applicationVersion: version,
            .credits: NSAttributedString(string: "A tree-first file explorer for macOS.")
        ])
    }
    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Branch Help"
        alert.informativeText = "Use the folder tree and breadcrumbs to navigate. Double-click folders to open them, or use the context menu to open one in a new tab."
        alert.runModal()
    }
    @objc private func showSettings() { store.showsToolSettings = true }
    @objc private func newTab() { store.newTab() }
    @objc private func newFolder() { store.showsNewFolderPrompt = true }
    @objc private func closeTab() {
        if store.tabs.count == 1 { window?.performClose(nil) }
        else { store.closeTab(store.selectedTabID) }
    }
    @objc private func openSelection() { if let item = store.selectedItems.first { store.open(item) } }
    @objc private func revealSelection() { store.revealSelection() }
    @objc private func cutSelection() { store.copySelection(cut: true) }
    @objc private func copySelection() { store.copySelection() }
    @objc private func paste() { store.paste() }
    @objc private func duplicateSelection() { store.duplicateSelection() }
    @objc private func renameSelection() { if let url = store.selectedTab.selectedURLs.first { store.beginRename(url) } }
    @objc private func confirmTrash() { if !store.selectedTab.selectedURLs.isEmpty { store.showsDeleteConfirmation = true } }
    @objc private func selectAll() { store.setSelection(Set(store.displayedItems.map(\.url))) }
    @objc private func showList() { store.setViewMode(.list) }
    @objc private func showIcons() { store.setViewMode(.icons) }
    @objc private func toggleInspector() { store.showsInspector.toggle() }
    @objc private func toggleHidden() { store.toggleHiddenFiles() }
    @objc private func reload() { store.reload() }
    @objc private func goBack() { store.goBack() }
    @objc private func goForward() { store.goForward() }
    @objc private func goUp() { store.goUp() }
    @objc private func goHome() { store.navigate(to: store.homeURL) }
    @objc private func minimizeWindow() { window?.miniaturize(nil) }
    @objc private func zoomWindow() { window?.performZoom(nil) }
}
