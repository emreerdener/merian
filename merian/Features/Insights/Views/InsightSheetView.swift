import SwiftUI
import SwiftData
import SafariServices

// MARK: - Insight Sheet View
struct InsightSheetView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    
    // MARK: Component State
    @State var isSafariPresented = false
    @State var selectedWikiURL: URL?
    @State var isFlagIssuePresented = false
    @State var showCelebration = false
    @State var showCollectionPicker = false
    @State var showDeleteConfirmation = false
    @State var isSavingPhotos = false
    @State var showSaveSuccessAlert = false
    @State var showMiniTitle = false
    
    // MARK: Diagnostic Bounds
    var isPoisonous: Bool { inferenceEngine.speciesData?.insightData.isPoisonous ?? false }
    var commonName: String { inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..." }
    var scientificName: String { inferenceEngine.speciesData?.scientificName ?? "Awaiting taxonomy" }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                scrollableCanvas
                
                // Native Synthesized Mini Title
                if showMiniTitle {
                    Text(commonName)
                        .font(.system(.subheadline))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.15))
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 14) // Seamlessly visually maps to standard Navigation bounds height
                        .zIndex(50)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                
                celebrationOverlay
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                InsightSheetHeader(
                    commonName: commonName,
                    showTitle: $showMiniTitle,
                    isFlagIssuePresented: $isFlagIssuePresented,
                    isSavingPhotos: $isSavingPhotos,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    onSavePhotos: saveUserPhotos
                )
                
                if let speciesData = inferenceEngine.speciesData, speciesData.isBiological && speciesData.commonName.lowercased() != "not applicable" {
                    ToolbarItemGroup(placement: .bottomBar) {
                        addCollectionButton
                        Spacer()
                        shareActionButton
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(.visible, for: .bottomBar)
            .toolbarBackground(.ultraThinMaterial, for: .bottomBar)
            
            // Dialogs
            .confirmationDialog("Delete scan", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete scan permanently", role: .destructive) { eradicateCurrentScan() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this scan? This will permanently remove the photo and data from your device and the global biological archive.")
            }
            .alert("Photos Saved", isPresented: $showSaveSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your photos have been securely saved to your Camera Roll.")
            }
            
            // Presentation Logic Hook
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .onAppear { evaluateVoiceOverAndCelebration() }
            .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
                evaluateProcessingCompletion(isStillProcessing: isStillProcessing)
            }
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                // Once the offset dips past -200, the main title is scrolled out of view, so show the mini header!
                let shouldShow = offset < -200
                if showMiniTitle != shouldShow {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMiniTitle = shouldShow
                    }
                }
            }
        }
    }
}

// MARK: - Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


