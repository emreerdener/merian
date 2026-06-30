import SwiftUI

struct ScansToolbarModifier: ViewModifier {
    // MARK: - State Dependencies
    @Bindable var searchManager: ScansManager
    @Binding var activeTab: ScansTab
    let dismiss: DismissAction
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
                        Menu {
                            if activeTab == .collections {
                                Picker(selection: $searchManager.collectionSortOption) {
                                    ForEach(ScanSortOption.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                } label: {
                                    Label("Sort by", systemImage: "arrow.up.arrow.down")
                                }
                                .pickerStyle(.menu)
                                
                            } else if activeTab == .library {
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
                                
                                Picker(selection: $searchManager.sortOption) {
                                    ForEach(ScanSortOption.allCases) { option in
                                        Text(option.rawValue).tag(option)
                                    }
                                } label: {
                                    Label("Sort by", systemImage: "arrow.up.arrow.down")
                                }
                                .pickerStyle(.menu)
                                
                                Button(action: { searchManager.isSelectionMode = true }) { Label("Select multiple", systemImage: "checkmark.circle") }
                            }
                        } label: {
                            Image(systemName: activeTab == .collections ? "line.3.horizontal.decrease" : "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .accessibilityLabel(activeTab == .collections ? "Sort collections" : "More options")
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
                
                // 3. Global Keyboard Resignation
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
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
        onShare: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.modifier(ScansToolbarModifier(
            searchManager: searchManager,
            activeTab: activeTab,
            dismiss: dismiss,
            onShare: onShare,
            onDownload: onDownload,
            onDelete: onDelete
        ))
    }
}
