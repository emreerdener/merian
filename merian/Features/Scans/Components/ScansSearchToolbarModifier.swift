import SwiftUI

struct ScansSearchToolbarModifier: ViewModifier {
    @ObservedObject var searchManager: ScansSearchManager
    @Binding var activeTab: ScansTab
    @Binding var showNewCollectionAlert: Bool
    @Binding var isSelectionMode: Bool
    @Binding var selectedScans: Set<String>
    let dismiss: DismissAction
    let onShare: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    @AppStorage("gridColumns") private var gridColumns: Int = 3
    
    func body(content: Content) -> some View {
        content
            .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            isSelectionMode = false
                            selectedScans.removeAll()
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("\(selectedScans.count) Selected")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select All") {
                            let maxLimit = 20
                            let maximumScans = Array(searchManager.filteredScans.prefix(maxLimit))
                            if selectedScans.count == maximumScans.count {
                                selectedScans.removeAll()
                            } else {
                                selectedScans = Set(maximumScans.map { $0.id })
                            }
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(action: onShare) { 
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(selectedScans.isEmpty)
                        
                        Spacer()
                        
                        Button(action: onDownload) { 
                            Image(systemName: "arrow.down.circle")
                            Text("Download").fontWeight(.semibold)
                        }
                        .disabled(selectedScans.isEmpty)
                        
                        Spacer()
                        
                        Button(role: .destructive, action: onDelete) { 
                            Image(systemName: "trash")
                        }
                        .tint(selectedScans.isEmpty ? .gray : .red)
                        .disabled(selectedScans.isEmpty)
                    }
                } else {
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
                            Button(action: {
                                showNewCollectionAlert = true
                            }) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.circle)
                            .tint(.blue)
                        } else if activeTab == .library {
                            Menu {
                                ControlGroup {
                                    Toggle(isOn: Binding(get: { gridColumns == 1 }, set: { if $0 { gridColumns = 1 } })) {
                                        Label("1x1", systemImage: "rectangle.grid.1x2")
                                    }
                                    Toggle(isOn: Binding(get: { gridColumns == 2 }, set: { if $0 { gridColumns = 2 } })) {
                                        Label("2x2", systemImage: "square.grid.2x2")
                                    }
                                    Toggle(isOn: Binding(get: { gridColumns == 3 }, set: { if $0 { gridColumns = 3 } })) {
                                        Label("3x3", systemImage: "square.grid.3x3")
                                    }
                                }
                                
                                Button(action: { isSelectionMode = true }) { Label("Select multiple", systemImage: "checkmark.circle") }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 16, weight: .bold))
                            }
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
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
            }
            .toolbarBackground(isSelectionMode ? .visible : .hidden, for: .bottomBar)
    }
}

extension View {
    func scansSearchToolbar(
        searchManager: ScansSearchManager,
        activeTab: Binding<ScansTab>,
        showNewCollectionAlert: Binding<Bool>,
        isSelectionMode: Binding<Bool>,
        selectedScans: Binding<Set<String>>,
        dismiss: DismissAction,
        onShare: @escaping () -> Void,
        onDownload: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.modifier(ScansSearchToolbarModifier(
            searchManager: searchManager,
            activeTab: activeTab,
            showNewCollectionAlert: showNewCollectionAlert,
            isSelectionMode: isSelectionMode,
            selectedScans: selectedScans,
            dismiss: dismiss,
            onShare: onShare,
            onDownload: onDownload,
            onDelete: onDelete
        ))
    }
}
