import SwiftUI

struct SidebarView: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        List {
            Section("Favorites") {
                ForEach(store.favoriteURLs, id: \.self) { url in
                    SidebarDestinationRow(
                        title: displayName(for: url),
                        symbol: symbol(for: url),
                        url: url,
                        store: store
                    )
                }
            }

            Section("Folder Tree") {
                FolderTreeNode(url: store.rootURL, store: store, isRoot: true)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Label("\(store.items.count) items", systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func displayName(for url: URL) -> String {
        if url.path == "/" { return "Macintosh HD" }
        if url == store.homeURL { return "Home" }
        return url.lastPathComponent
    }

    private func symbol(for url: URL) -> String {
        if url.path == "/" { return "internaldrive" }
        return switch url.lastPathComponent {
        case "Desktop": "desktopcomputer"
        case "Documents": "doc.on.doc"
        case "Downloads": "arrow.down.circle"
        case "Applications": "square.grid.2x2"
        default: url == store.homeURL ? "house" : "folder"
        }
    }
}

private struct SidebarDestinationRow: View {
    let title: String
    let symbol: String
    let url: URL
    @Bindable var store: ExplorerStore

    var body: some View {
        Button { store.navigate(to: url) } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(store.currentURL == url ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button("Open in New Tab") { store.newTab(at: url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove from Favorites") { store.removeFavorite(url) }
        }
    }
}

private struct FolderTreeNode: View {
    let url: URL
    @Bindable var store: ExplorerStore
    let isRoot: Bool
    @State private var children: [FileItem] = []
    @State private var hasLoaded = false

    private var isOnCurrentPath: Bool { store.isCurrentOrAncestor(url) }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { store.expandedFolders.contains(url.standardizedFileURL) },
            set: { expanded in
                if expanded {
                    store.expandedFolders.insert(url.standardizedFileURL)
                    loadChildren()
                } else {
                    store.expandedFolders.remove(url.standardizedFileURL)
                }
            }
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(children) { child in
                FolderTreeNode(url: child.url, store: store, isRoot: false)
            }
        } label: {
            HStack(spacing: 7) {
                TreeFolderIcon(
                    isRoot: isRoot,
                    isExpanded: isExpanded.wrappedValue,
                    isFilled: isOnCurrentPath
                )
                Text(isRoot ? "Macintosh HD" : url.lastPathComponent)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                isExpanded.wrappedValue.toggle()
                store.navigate(to: url)
            }
            .onTapGesture { store.navigate(to: url) }
            .contextMenu {
                Button("Open in New Tab") { store.newTab(at: url) }
                Button("New Folder") {
                    store.navigate(to: url)
                    store.showsNewFolderPrompt = true
                }
                Divider()
                if store.isFavorite(url) {
                    Button("Remove from Favorites") { store.removeFavorite(url) }
                } else {
                    Button("Add to Favorites") { store.addFavorite(url) }
                }
            }
        }
        .listRowBackground(store.currentURL == url ? Color.accentColor.opacity(0.18) : Color.clear)
        .onAppear {
            if isExpanded.wrappedValue { loadChildren() }
        }
        .onChange(of: store.showHiddenFiles) { _, _ in
            hasLoaded = false
            if isExpanded.wrappedValue { loadChildren() }
        }
    }

    private func loadChildren() {
        guard !hasLoaded else { return }
        children = store.folders(in: url)
        hasLoaded = true
    }
}

private struct TreeFolderIcon: View {
    let isRoot: Bool
    let isExpanded: Bool
    let isFilled: Bool

    var body: some View {
        Group {
            if isRoot {
                Image(systemName: isFilled ? "internaldrive.fill" : "internaldrive")
                    .resizable()
                    .scaledToFit()
            } else {
                TreeFolderShape(isOpen: isExpanded)
                    .fill(isFilled ? Color.yellow : Color.clear)
                    .overlay {
                        TreeFolderShape(isOpen: isExpanded)
                            .stroke(Color.yellow, lineWidth: 1.4)
                    }
            }
        }
        .frame(width: 17, height: 14)
        .foregroundStyle(isRoot ? Color.secondary : Color.yellow)
        .accessibilityHidden(true)
    }
}

private struct TreeFolderShape: Shape {
    let isOpen: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        if isOpen {
            path.move(to: CGPoint(x: 0.08 * w, y: 0.35 * h))
            path.addLine(to: CGPoint(x: 0.36 * w, y: 0.35 * h))
            path.addLine(to: CGPoint(x: 0.46 * w, y: 0.20 * h))
            path.addLine(to: CGPoint(x: 0.90 * w, y: 0.20 * h))
            path.addQuadCurve(to: CGPoint(x: 0.97 * w, y: 0.31 * h), control: CGPoint(x: 0.97 * w, y: 0.20 * h))
            path.addLine(to: CGPoint(x: 0.82 * w, y: 0.88 * h))
            path.addQuadCurve(to: CGPoint(x: 0.72 * w, y: 0.96 * h), control: CGPoint(x: 0.79 * w, y: 0.96 * h))
            path.addLine(to: CGPoint(x: 0.13 * w, y: 0.96 * h))
            path.addQuadCurve(to: CGPoint(x: 0.04 * w, y: 0.84 * h), control: CGPoint(x: 0.04 * w, y: 0.96 * h))
            path.addLine(to: CGPoint(x: 0.08 * w, y: 0.35 * h))
        } else {
            path.move(to: CGPoint(x: 0.06 * w, y: 0.27 * h))
            path.addQuadCurve(to: CGPoint(x: 0.16 * w, y: 0.17 * h), control: CGPoint(x: 0.06 * w, y: 0.17 * h))
            path.addLine(to: CGPoint(x: 0.42 * w, y: 0.17 * h))
            path.addLine(to: CGPoint(x: 0.53 * w, y: 0.31 * h))
            path.addLine(to: CGPoint(x: 0.90 * w, y: 0.31 * h))
            path.addQuadCurve(to: CGPoint(x: 0.96 * w, y: 0.39 * h), control: CGPoint(x: 0.96 * w, y: 0.31 * h))
            path.addLine(to: CGPoint(x: 0.96 * w, y: 0.88 * h))
            path.addQuadCurve(to: CGPoint(x: 0.88 * w, y: 0.96 * h), control: CGPoint(x: 0.96 * w, y: 0.96 * h))
            path.addLine(to: CGPoint(x: 0.13 * w, y: 0.96 * h))
            path.addQuadCurve(to: CGPoint(x: 0.06 * w, y: 0.88 * h), control: CGPoint(x: 0.06 * w, y: 0.96 * h))
            path.closeSubpath()
        }
        return path
    }
}
