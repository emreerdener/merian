import SwiftUI

struct ScansToolbarModifier: ViewModifier {
    // MARK: - State Dependencies
    @Bindable var searchManager: ScansManager
    @Binding var activeTab: ScansTab
    let dismiss: DismissAction
    let onNewCollection: () -> Void
    let onShare: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    @Environment(AppSettings.self) private var appSettings
    
    // MARK: - View Engine
    func body(content: Content) -> some View {
        @Bindable var appSettings = appSettings

        content
            .toolbar {
                if searchManager.isSelectionMode {
                    // 1. Batch Selection Controls
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            searchManager.exitSelectionMode()
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("\(searchManager.selectedScans.count) Selected")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select All") {
                            searchManager.selectAll()
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(action: onShare) { 
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(searchManager.selectedScans.isEmpty)
                        
                        Spacer()
                        
                        Button(action: onDownload) { 
                            Image(systemName: "arrow.down.circle")
                            Text("Download").fontWeight(.semibold)
                        }
                        .disabled(searchManager.selectedScans.isEmpty)
                        
                        Spacer()
                        
                        Button(role: .destructive, action: onDelete) { 
                            Image(systemName: "trash")
                        }
                        .tint(searchManager.selectedScans.isEmpty ? .gray : .red)
                        .disabled(searchManager.selectedScans.isEmpty)
                    }
                } else {
                    // 2. Default Navigation State
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            if !searchManager.searchQuery.isEmpty {
                                searchManager.searchQuery = ""
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if activeTab == .collections {
                            Button(action: onNewCollection) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.circle)
                            .tint(.blue)
                            .accessibilityLabel("New collection")
                        } else if activeTab == .library {
                            Menu {
                                ControlGroup {
                                    Toggle(isOn: Binding(get: { appSettings.gridColumns == 1 }, set: { if $0 { appSettings.gridColumns = 1 } })) {
                                        Label("1x1", systemImage: "rectangle.grid.1x2")
                                    }
                                    Toggle(isOn: Binding(get: { appSettings.gridColumns == 2 }, set: { if $0 { appSettings.gridColumns = 2 } })) {
                                        Label("2x2", systemImage: "square.grid.2x2")
                                    }
                                    Toggle(isOn: Binding(get: { appSettings.gridColumns == 3 }, set: { if $0 { appSettings.gridColumns = 3 } })) {
                                        Label("3x3", systemImage: "square.grid.3x3")
                                    }
                                }

                                Button(action: { searchManager.isSelectionMode = true }) {
                                    Label("Select multiple", systemImage: "checkmark.circle")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .accessibilityLabel("More options")
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $activeTab) {
                            Text("Scans").tag(ScansTab.library)
                            Text("Collections").tag(ScansTab.collections)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }

                }
            }
            .toolbarBackground(searchManager.isSelectionMode ? .visible : .hidden, for: .bottomBar)
    }
}

// MARK: - View Extension

extension View {
    func scansToolbar(
        searchManager: ScansManager,
        activeTab: Binding<ScansTab>,
        dismiss: DismissAction,
        onNewCollection: @escaping () -> Void = {},
        onShare: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.modifier(ScansToolbarModifier(
            searchManager: searchManager,
            activeTab: activeTab,
            dismiss: dismiss,
            onNewCollection: onNewCollection,
            onShare: onShare,
            onDownload: onDownload,
            onDelete: onDelete
        ))
    }
}
