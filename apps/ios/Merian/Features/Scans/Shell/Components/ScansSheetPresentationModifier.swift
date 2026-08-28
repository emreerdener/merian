import SwiftData
import SwiftUI

struct ScansSheetPresentationModifier: ViewModifier {
    @Bindable var searchManager: ScansManager
    @Binding var activeTab: ScansTab
    @Binding var isSearchFocused: Bool
    @Binding var showNewCollectionAlert: Bool
    @Binding var newCollectionName: String
    @Binding var scanToDelete: String?
    @Binding var showDeleteConfirmation: Bool
    @Binding var showBatchDeleteConfirmation: Bool
    @Binding var showSelectionLimitAlert: Bool
    @Binding var toastMessage: ToastPayload?
    @Binding var isDownloading: Bool

    let modelContext: ModelContext
    let onBatchDelete: () -> Void
    let onCollectionCreated: (ScanCollection) -> Void

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: activeTab) { _, newValue in
                guard !searchManager.searchQuery.isEmpty else { return }
                searchManager.searchQuery = ""
                isSearchFocused = false
                if newValue == .library {
                    searchManager.performSearch(query: "")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchManager.searchQuery,
                isPresented: $isSearchFocused,
                placement: .toolbar,
                prompt: activeTab == .library
                    ? "Search scans"
                    : "Search collections"
            )
            .onChange(of: searchManager.searchQuery) { _, newValue in
                if activeTab == .library {
                    searchManager.performSearch(query: newValue)
                }
            }
            .newCollectionAlert(
                isPresented: $showNewCollectionAlert,
                newCollectionName: $newCollectionName,
                modelContext: modelContext,
                onCreated: onCollectionCreated
            )
            .scanDeletionDialog(
                isPresented: $showDeleteConfirmation,
                scanId: scanToDelete,
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
                .disabled(isDownloading)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(
                    "This permanently removes these discoveries and their visuals. Any published Explore posts, likes, and comments linked to them will also be permanently removed."
                )
            }
            .alert(
                "Selection limit reached",
                isPresented: $showSelectionLimitAlert
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(
                    "You can only select up to 20 items at a time to ensure optimal system performance during export and deletion workloads."
                )
            }
            .overlay(alignment: .bottom) {
                if isDownloading {
                    savingMediaProgress
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isDownloading)
            .merianSystemFeedback(
                toast: $toastMessage,
                showsAchievementToasts: false
            )
    }

    private var savingMediaProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Saving media…")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .adaptiveToastSurface(in: Capsule(), shadowRadius: 10, shadowY: 5)
        .padding(.bottom, toastMessage == nil ? 60 : 112)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saving selected media")
    }
}
