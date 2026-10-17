import SwiftUI

struct ExplorerView: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(store: store)
            Divider()
            NavigationSplitView {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 245, max: 360)
            } detail: {
                ExplorerDetailView(store: store)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .background(.background)
        .sheet(isPresented: $store.showsToolSettings) {
            ToolSettingsView(store: store)
        }
        .alert("New Folder", isPresented: $store.showsNewFolderPrompt) {
            TextField("Folder name", text: $store.newFolderText)
            Button("Cancel", role: .cancel) { store.newFolderText = "Untitled Folder" }
            Button("Create") { store.createFolder() }
        } message: {
            Text("Create a folder in \(store.currentURL.lastPathComponent).")
        }
        .alert("Rename Item", isPresented: $store.showsRenamePrompt) {
            TextField("Name", text: $store.renameText)
            Button("Cancel", role: .cancel) { store.renameTarget = nil }
            Button("Rename") { store.commitRename() }
        }
        .alert("Move to Trash?", isPresented: $store.showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) { store.cancelTrash() }
            Button("Move to Trash", role: .destructive) { store.trashSelection() }
        } message: {
            Text(deleteMessage)
        }
        .alert("Branch couldn’t complete that action", isPresented: errorBinding) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private var deleteMessage: String {
        let count = store.pendingTrashURLs.count
        return count == 1 ? "The selected item will be moved to the Trash." : "These \(count) items will be moved to the Trash."
    }
}

private struct TabStrip: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.tabs) { tab in
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.yellow)
                        Text(tab.title)
                            .lineLimit(1)
                        if store.tabs.count > 1 {
                            Button { store.closeTab(tab.id) } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                            .buttonStyle(.plain)
                            .help("Close Tab")
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(store.selectedTabID == tab.id ? Color(nsColor: .controlBackgroundColor) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { store.selectTab(tab.id) }
                    .contextMenu {
                        Button("Close Tab") { store.closeTab(tab.id) }
                            .disabled(store.tabs.count == 1)
                    }
                }
                Button { store.newTab() } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("New Tab")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 38)
        .background(.bar)
    }
}
