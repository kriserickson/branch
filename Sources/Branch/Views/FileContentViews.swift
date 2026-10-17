import AppKit
import SwiftUI

struct FileListView: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    ListHeader(store: store)
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.displayedItems) { item in
                                FileListRow(item: item, store: store)
                            }
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                    }
                    .background {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { store.setSelection([]) }
                    }
                    .contextMenu { DirectoryBackgroundMenu(store: store) }
                    .dropDestination(for: URL.self) { urls, _ in
                        store.importURLs(urls, to: store.currentURL)
                    }
                }
                .frame(
                    width: max(geometry.size.width, store.visibleColumns.reduce(38) { $0 + $1.width }),
                    height: geometry.size.height
                )
            }
        }
    }
}

private struct ListHeader: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        HStack(spacing: 0) {
            SortHeader(sort: .name, store: store)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(store.visibleColumns.filter { $0 != .name }, id: \.self) { column in
                SortHeader(sort: column, store: store)
                    .frame(width: column.width, alignment: column == .size ? .trailing : .leading)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 19)
        .frame(height: 28)
        .background(.bar)
        .contextMenu { ColumnPicker(store: store) }
    }
}

private struct SortHeader: View {
    let sort: FileSort
    @Bindable var store: ExplorerStore

    var body: some View {
        HStack(spacing: 4) {
            Text(sort.title)
            if store.selectedTab.sort == sort {
                Image(systemName: store.selectedTab.sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .padding(.horizontal, sort == .name ? 0 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sort == .size ? .trailing : .leading)
        .contentShape(Rectangle())
        // Give a double-click precedence so it changes the sort only once.
        .onTapGesture(count: 2) { store.setSort(sort) }
        .onTapGesture { store.setSort(sort) }
        .focusable()
        .onKeyPress(.space) {
            store.setSort(sort)
            return .handled
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(sort.title)
        .accessibilityValue(store.selectedTab.sort == sort ? (store.selectedTab.sortAscending ? "Ascending" : "Descending") : "Not sorted")
        .accessibilityAction { store.setSort(sort) }
        .help("Click or double-click to sort by \(sort.title); repeat to reverse")
    }
}

private struct FileListRow: View {
    let item: FileItem
    @Bindable var store: ExplorerStore
    @State private var isTargeted = false

    private var isSelected: Bool { store.selectedTab.selectedURLs.contains(item.url) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                FileIcon(url: item.url, isDirectory: item.isDirectory, size: 22)
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(store.visibleColumns.filter { $0 != .name }, id: \.self) { column in
                Text(item.text(for: column))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: column.width - 12, alignment: column == .size ? .trailing : .leading)
                    .clipped()
                    .padding(.horizontal, 6)
                    .foregroundStyle(.secondary)
                    .help(item.text(for: column))
            }
        }
        .opacity(item.isHidden ? 0.7 : 1)
        .font(.system(size: 12.5))
        .padding(.horizontal, 15)
        .frame(height: 30)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.open(item) }
        .onTapGesture { select() }
        .draggable(item.url)
        .dropDestination(for: URL.self, action: { urls, _ in
            guard item.isDirectory else { return false }
            return store.importURLs(urls, to: item.url)
        }, isTargeted: { isTargeted = $0 })
        .contextMenu {
            FileContextMenu(item: item, store: store)
                .onAppear { store.ensureSelectedForContextMenu(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        if isTargeted && item.isDirectory { return .accentColor.opacity(0.32) }
        if isSelected { return .accentColor.opacity(0.24) }
        return .clear
    }

    private func select() {
        store.select(item, modifiers: NSEvent.modifierFlags)
    }
}

struct FileGridView: View {
    @Bindable var store: ExplorerStore
    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.displayedItems) { item in
                    FileGridCell(item: item, store: store)
                }
            }
            .padding(14)
        }
        .background {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { store.setSelection([]) }
        }
        .contextMenu { DirectoryBackgroundMenu(store: store) }
        .dropDestination(for: URL.self) { urls, _ in
            store.importURLs(urls, to: store.currentURL)
        }
    }
}

private struct FileGridCell: View {
    let item: FileItem
    @Bindable var store: ExplorerStore
    @State private var isTargeted = false

    private var isSelected: Bool { store.selectedTab.selectedURLs.contains(item.url) }

    var body: some View {
        VStack(spacing: 7) {
            FileIcon(url: item.url, isDirectory: item.isDirectory, size: 54)
            Text(item.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 32, alignment: .top)
        }
        .opacity(item.isHidden ? 0.7 : 1)
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.open(item) }
        .onTapGesture { select() }
        .draggable(item.url)
        .dropDestination(for: URL.self, action: { urls, _ in
            guard item.isDirectory else { return false }
            return store.importURLs(urls, to: item.url)
        }, isTargeted: { isTargeted = $0 })
        .contextMenu {
            FileContextMenu(item: item, store: store)
                .onAppear { store.ensureSelectedForContextMenu(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isTargeted && item.isDirectory { return .accentColor.opacity(0.32) }
        if isSelected { return .accentColor.opacity(0.24) }
        return .clear
    }

    private func select() {
        store.select(item, modifiers: NSEvent.modifierFlags)
    }
}

struct FileIcon: View {
    let url: URL
    let isDirectory: Bool
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

@ViewBuilder
@MainActor
private func FileContextMenu(item: FileItem, store: ExplorerStore) -> some View {
    Button("Open") { store.open(item) }
    if item.isApplicationBundle {
        Button("Open Package Contents") { store.openPackageContents(item) }
    } else if item.isDirectory {
        Button("Open in New Tab") { store.openInNewTab(item) }
        if store.isFavorite(item.url) {
            Button("Remove from Favorites") { store.removeFavorite(item.url) }
        } else {
            Button("Add to Favorites") { store.addFavorite(item.url) }
        }
        let enabledTools = store.installedDirectoryTools.filter { store.enabledDirectoryToolIDs.contains($0.id) }
        if !enabledTools.isEmpty {
            Divider()
            Menu("Open folder with") {
                ForEach(enabledTools) { tool in
                    Button {
                        store.openDirectory(item.url, with: tool.id)
                    } label: {
                        Label(tool.name, systemImage: tool.symbol)
                    }
                }
            }
        }
    }
    if store.mergeableSelection != nil, let tool = store.preferredInstalledMergeTool {
        Divider()
        Button("Compare 2 Files in \(tool.id.name)") { store.compareSelectedFiles() }
    }
    Divider()
    Button("Rename…") { store.beginRename(item.url) }
    Button("Copy") {
        store.setSelection([item.url])
        store.copySelection()
    }
    Button("Move") {
        store.setSelection([item.url])
        store.copySelection(cut: true)
    }
    Button("Duplicate") {
        store.setSelection([item.url])
        store.duplicateSelection()
    }
    Divider()
    Button("Show in Finder") {
        store.setSelection([item.url])
        store.revealSelection()
    }
    Button("Move to Trash", role: .destructive) {
        store.requestTrash(store.selectedTab.selectedURLs.contains(item.url) ? store.selectedTab.selectedURLs : [item.url])
    }
}

@ViewBuilder
@MainActor
func DirectoryBackgroundMenu(store: ExplorerStore) -> some View {
    let enabledTools = store.installedDirectoryTools.filter { store.enabledDirectoryToolIDs.contains($0.id) }
    if !enabledTools.isEmpty {
        Menu("Open folder with") {
            ForEach(enabledTools) { tool in
                Button {
                    store.openCurrentDirectory(with: tool.id)
                } label: {
                    Label(tool.name, systemImage: tool.symbol)
                }
            }
        }
    }
}

@MainActor
struct ColumnPicker: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        ForEach(FileSort.allCases, id: \.self) { column in
            Toggle(column.title, isOn: Binding(
                get: { store.visibleColumns.contains(column) },
                set: { store.setColumn(column, visible: $0) }
            ))
            .disabled(column == .name)
        }
        Divider()
        Button("Restore Default Columns") { store.restoreDefaultColumns() }
    }
}
