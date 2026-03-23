import SwiftUI
import SwiftData

struct ScansSheetModifiers: ViewModifier {
    @Bindable var searchManager: ScansManager
    @Binding var activeTab: ScansTab
    @Binding var isSearchFocused: Bool
    @Binding var selectedScanForInsight: LocalScanRecord?
    
    @Binding var showNewCollectionAlert: Bool
    @Binding var newCollectionName: String
    
    @Binding var scanToDelete: LocalScanRecord?
    @Binding var showDeleteConfirmation: Bool
    @Binding var showBatchDeleteConfirmation: Bool
    @Binding var showSelectionLimitAlert: Bool
    
    @Binding var toastMessage: String?
    @Binding var isDownloading: Bool
    
    let dismiss: DismissAction
    let modelContext: ModelContext
    let onBatchDelete: () -> Void
    
    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: activeTab) { _, newValue in
                if !searchManager.searchQuery.isEmpty {
                    searchManager.searchQuery = ""
                    isSearchFocused = false
                    if newValue == .library {
                        searchManager.performSearch(query: "")
                    }
                }
            }
            .sheet(item: $selectedScanForInsight) { scan in
                InsightSheetView(isPresented: Binding(
                    get: { selectedScanForInsight != nil },
                    set: { if !$0 { selectedScanForInsight = nil } }
                ))
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchManager.searchQuery, isPresented: $isSearchFocused, placement: .toolbar, prompt: activeTab == .library ? "Search keywords, habitats, colors..." : "Search collections...")
            .onChange(of: searchManager.searchQuery) { _, newValue in
                if activeTab == .library {
                    searchManager.performSearch(query: newValue)
                }
            }
            .newCollectionAlert(
                isPresented: $showNewCollectionAlert,
                newCollectionName: $newCollectionName,
                modelContext: modelContext
            )
            .scanDeletionDialog(
                isPresented: $showDeleteConfirmation,
                record: scanToDelete,
                modelContext: modelContext
            ) {
                scanToDelete = nil
            }
            .alert(
                "Delete \(searchManager.selectedScans.count) selected scans?",
                isPresented: $showBatchDeleteConfirmation
            ) {
                Button("Delete permanently", role: .destructive) {
                    onBatchDelete()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently remove these discoveries and all associated visuals from your history.")
            }
            .alert(
                "Selection limit reached",
                isPresented: $showSelectionLimitAlert
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You can only select up to 20 items at a time to ensure optimal system performance during export and deletion workloads.")
            }
            .overlay {
                if let message = toastMessage {
                    VStack {
                        Spacer()
                        Text(message)
                            .font(.footnote)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                            .colorScheme(.dark)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                            .padding(.bottom, 60)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(100)
                    }
                }
            }
            .overlay {
                if isDownloading {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Downloading...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
    }
}
