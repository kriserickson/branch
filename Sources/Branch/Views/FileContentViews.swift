import AppKit
import SwiftUI

struct FileListView: View {
    @Bindable var store: ExplorerStore

    var body: some View {
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
            }
            .contentShape(Rectangle())
            .onTapGesture { store.setSelection([]) }
            .contextMenu { DirectoryBackgroundMenu(store: store) }
            .dropDestination(for: URL.self) { urls, _ in
                store.importURLs(urls, to: store.currentURL)
            }
        }
    }
}

private struct ListHeader: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        HStack(spacing: 0) {
            SortHeader("Name", sort: .name, store: store)
                .frame(maxWidth: .infinity, alignment: .leading)
            SortHeader("Date Modified", sort: .dateModified, store: store)
                .frame(width: 155, alignment: .leading)
            SortHeader("Kind", sort: .kind, store: store)
                .frame(width: 120, alignment: .leading)
            SortHeader("Size", sort: .size, store: store)
                .frame(width: 86, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
    }
}

private struct SortHeader: View {
    let title: String
    let sort: FileSort
    @Bindable var store: ExplorerStore

    init(_ title: String, sort: FileSort, store: ExplorerStore) {
        self.title = title
        self.sort = sort
        self.store = store
    }

    var body: some View {
        Button { store.setSort(sort) } label: {
            HStack(spacing: 4) {
                Text(title)
                if store.selectedTab.sort == sort {
                    Image(systemName: store.selectedTab.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: sort == .size ? .trailing : .leading)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
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
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.modifiedDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                .frame(width: 155, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(item.kindDescription)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Text(item.formattedSize)
                .frame(width: 86, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
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
        .contentShape(Rectangle())
        .onTapGesture { store.setSelection([]) }
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
        store.setSelection([item.url])
        store.showsDeleteConfirmation = true
    }
}

@ViewBuilder
@MainActor
func DirectoryBackgroundMenu(store: ExplorerStore) -> some View {
    let enabledTools = store.installedDirectoryTools.filter { store.enabledDirectoryToolIDs.contains($0.id) }
    if enabledTools.isEmpty {
        Button("Configure Open With Tools…") { store.showsToolSettings = true }
    } else {
        Menu("Open Current Folder With") {
            ForEach(enabledTools) { tool in
                Button {
                    store.openCurrentDirectory(with: tool.id)
                } label: {
                    Label(tool.name, systemImage: tool.symbol)
                }
            }
        }
        Divider()
        Button("Configure Tools…") { store.showsToolSettings = true }
    }
}
