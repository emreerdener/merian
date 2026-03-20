import SwiftUI

struct ScansSearchToolbarModifier: ViewModifier {
    @ObservedObject var searchManager: ScansSearchManager
    @Binding var activeTab: ScansTab
    @Binding var showNewCollectionAlert: Bool
    let dismiss: DismissAction
    
    func body(content: Content) -> some View {
        content
            .toolbar {
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
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
            }
    }
}

extension View {
    func scansSearchToolbar(
        searchManager: ScansSearchManager,
        activeTab: Binding<ScansTab>,
        showNewCollectionAlert: Binding<Bool>,
        dismiss: DismissAction
    ) -> some View {
        self.modifier(ScansSearchToolbarModifier(
            searchManager: searchManager,
            activeTab: activeTab,
            showNewCollectionAlert: showNewCollectionAlert,
            dismiss: dismiss
        ))
    }
}
