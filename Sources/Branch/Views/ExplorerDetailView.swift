import AppKit
import SwiftUI

struct ExplorerDetailView: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        VStack(spacing: 0) {
            ExplorerToolbar(store: store)
            Divider()
            BreadcrumbBar(store: store)
            Divider()

            HStack(spacing: 0) {
                Group {
                    if store.isLoading && store.items.isEmpty {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if store.displayedItems.isEmpty {
                        ContentUnavailableView(
                            store.selectedTab.searchText.isEmpty ? "This Folder Is Empty" : "No Results",
                            systemImage: store.selectedTab.searchText.isEmpty ? "folder" : "magnifyingglass",
                            description: Text(store.selectedTab.searchText.isEmpty ? "Drop files here or create a new folder." : "Try a different search term.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contextMenu { DirectoryBackgroundMenu(store: store) }
                        .dropDestination(for: URL.self) { urls, _ in
                            store.importURLs(urls, to: store.currentURL)
                        }
                    } else {
                        switch store.selectedTab.viewMode {
                        case .list:
                            FileListView(store: store)
                        case .icons:
                            FileGridView(store: store)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.showsInspector {
                    Divider()
                    InspectorView(store: store)
                        .frame(width: 265)
                }
            }

            Divider()
            StatusBar(store: store)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ExplorerToolbar: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        HStack(spacing: 8) {
            ControlGroup {
                Button { store.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!store.selectedTab.canGoBack)
                    .help("Back")
                Button { store.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!store.selectedTab.canGoForward)
                    .help("Forward")
                Button { store.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(store.currentURL.path == "/")
                    .help("Enclosing Folder")
            }
            .fixedSize()

            Button { store.reload(refreshingFolderTree: true) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Reload")

            Button { store.showsNewFolderPrompt = true } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .help("New Folder")

            Spacer(minLength: 10)

            Picker("View", selection: Binding(
                get: { store.selectedTab.viewMode },
                set: { store.setViewMode($0) }
            )) {
                ForEach(ExplorerViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 82)

            Menu {
                ColumnPicker(store: store)
            } label: {
                Image(systemName: "tablecells")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26)
            .help("Choose Columns")
            .accessibilityLabel("Columns")

            Menu {
                ForEach(FileSort.allCases, id: \.self) { sort in
                    Button {
                        store.setSort(sort)
                    } label: {
                        if store.selectedTab.sort == sort {
                            Label(sort.title, systemImage: store.selectedTab.sortAscending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(sort.title)
                        }
                    }
                }
                Divider()
                Button(store.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    store.toggleHiddenFiles()
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
            .help("Sort and View Options")

            Button { store.showsInspector.toggle() } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.borderless)
            .help("Toggle Inspector")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search this folder", text: Binding(
                    get: { store.selectedTab.searchText },
                    set: { store.setSearchText($0) }
                ))
                .textFieldStyle(.plain)
                if !store.selectedTab.searchText.isEmpty {
                    Button { store.setSearchText("") } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: 205, height: 26)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(.bar)
    }
}

private struct BreadcrumbBar: View {
    @Bindable var store: ExplorerStore

    private var crumbs: [(String, URL)] {
        let components = store.currentURL.pathComponents
        var result: [(String, URL)] = [("Macintosh HD", URL(fileURLWithPath: "/", isDirectory: true))]
        var running = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst() {
            running.appendPathComponent(component, isDirectory: true)
            result.append((component, running.standardizedFileURL))
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button { store.navigate(to: crumb.1) } label: {
                        HStack(spacing: 5) {
                            if index == 0 { Image(systemName: "internaldrive") }
                            Text(crumb.0)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(index == crumbs.count - 1 ? Color.primary.opacity(0.07) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .dropDestination(for: URL.self) { urls, _ in
            store.importURLs(urls, to: store.currentURL)
        }
    }
}

private struct StatusBar: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        HStack {
            let selected = store.selectedTab.selectedURLs.count
            Text(selected == 0 ? "\(store.displayedItems.count) items" : "\(selected) of \(store.displayedItems.count) selected")
            Spacer()
            if store.isCalculatingFolderSizes {
                Text("Calculating folder sizes…")
            }
            if store.showHiddenFiles {
                Label("Hidden files visible", systemImage: "eye")
            }
            Text(store.currentURL.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(store.currentURL.path)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.bar)
    }
}
