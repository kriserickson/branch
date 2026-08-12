import AppKit
import QuickLookUI
import SwiftUI

struct InspectorView: View {
    @Bindable var store: ExplorerStore

    var body: some View {
        Group {
            if let item = store.selectedItems.first, store.selectedItems.count == 1 {
                ScrollView {
                    VStack(spacing: 16) {
                        if item.isDirectory {
                            FileIcon(url: item.url, isDirectory: true, size: 96)
                                .padding(.top, 22)
                        } else {
                            QuickLookPreview(url: item.url)
                                .frame(height: 185)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .padding(.top, 12)
                        }

                        VStack(spacing: 5) {
                            Text(item.name)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                            Text(item.kindDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                            InspectorRow(label: "Size", value: item.formattedSize)
                            InspectorRow(label: "Modified", value: item.modifiedDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                            InspectorRow(label: "Created", value: item.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                            InspectorRow(label: "Where", value: item.url.deletingLastPathComponent().path)
                        }
                        .font(.caption)

                        HStack {
                            Button("Open") { store.open(item) }
                                .buttonStyle(.borderedProminent)
                            Button("Rename") { store.beginRename(item.url) }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 18)
                }
            } else if store.selectedItems.count > 1 {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 45))
                        .foregroundStyle(.secondary)
                    Text("\(store.selectedItems.count) Items Selected")
                        .font(.headline)
                    Button("Move to Trash", role: .destructive) {
                        store.showsDeleteConfirmation = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Select an item to preview it")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42))
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = url as NSURL
    }
}
