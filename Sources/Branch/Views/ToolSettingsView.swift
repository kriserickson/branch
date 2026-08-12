import SwiftUI

struct ToolSettingsView: View {
    @Bindable var store: ExplorerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("External Tools")
                        .font(.title2.bold())
                    Text("Choose which installed tools appear in Branch’s context menus.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            GroupBox("Open Current Folder With") {
                VStack(alignment: .leading, spacing: 10) {
                    if store.installedDirectoryTools.isEmpty {
                        Text("No supported terminal or editor apps were found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.installedDirectoryTools) { tool in
                            Toggle(tool.id.name, isOn: Binding(
                                get: { store.enabledDirectoryToolIDs.contains(tool.id) },
                                set: { store.setDirectoryTool(tool.id, enabled: $0) }
                            ))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            GroupBox("Two-File Comparison") {
                VStack(alignment: .leading, spacing: 8) {
                    if store.installedMergeTools.isEmpty {
                        Text("No supported merge tools were found.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Preferred tool", selection: Binding(
                            get: { store.preferredMergeToolID },
                            set: { store.setPreferredMergeTool($0) }
                        )) {
                            Text("None").tag(MergeToolID?.none)
                            ForEach(store.installedMergeTools) { tool in
                                Text(tool.id.name).tag(Optional(tool.id))
                            }
                        }
                        .pickerStyle(.radioGroup)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
