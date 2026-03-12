import SwiftUI

import SafariServices



// MARK: - Insight Sheet View
struct InsightSheetView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    
    @State private var isSafariPresented = false
    @State private var selectedWikiURL: URL?
    @State private var isFlagIssuePresented = false
    @State private var showCelebration = false
    
    // Safety Bounds
    private var isPoisonous: Bool {
        inferenceEngine.speciesData?.insightData.isPoisonous ?? false
    }
    
    private var commonName: String {
        inferenceEngine.speciesData?.commonName ?? "Scanning Subject..."
    }
    
    private var scientificName: String {
        inferenceEngine.speciesData?.scientificName ?? "Awaiting Taxonomy"
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 0. The Image Carousel
                    InsightCarouselView()
                    
                    // 1. The Toxicity Banner (Safety Critical)
                    InsightToxicityBanner()
                        .padding(.horizontal)
                    
                    // 2. Core Taxonomy Block
                    InsightTaxonomyHeader()
                    
                    // 3. Ecological Descriptive Insight
                    InsightDescriptionSection(isSafariPresented: $isSafariPresented, selectedWikiURL: $selectedWikiURL)
                    
                    // 3.5 Taxonomy Tree
                    InsightTaxonomyTree()
                
                // 4. Fallback Validation Block
                if let score = inferenceEngine.speciesData?.confidenceScore, score < 0.85, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                    DiagnosticComparisonView(diagnosticData: diagnosticData)
                        .padding(.horizontal)
                        .padding(.top, 16)
                }
                
                // 5. Flag Issue Action
                if let scanId = inferenceEngine.speciesData?.scanId {
                    Divider()
                        .padding(.vertical, 8)
                    
                    Button(action: {
                        isFlagIssuePresented = true
                    }) {
                        HStack {
                            Image(systemName: "flag.fill")
                            Text("Report Incorrect ID")
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    }
                }
                
                Spacer(minLength: 40)
            }
            .padding(.top, 24)
        }
        .sheet(isPresented: $isSafariPresented) {
            if let safeUrl = selectedWikiURL {
                SafariView(url: safeUrl)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $isFlagIssuePresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                FlagIssueView(scanId: scanId)
            }
        }
        .navigationTitle(commonName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                   Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)
                }
            }
            
            if inferenceEngine.speciesData?.isBiological == true {
                ToolbarItem(placement: .topBarTrailing) {
                    let shareUrl = URL(string: "https://merian.app")!
                    ShareLink(
                        item: shareUrl,
                        subject: Text("I found a \(commonName)!"),
                        message: Text("Check out this \(commonName) (\(scientificName)) I discovered using Merian!")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
        
        if showCelebration {
            NewDiscoveryCelebrationView(
                commonName: commonName,
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showCelebration = false
                    }
                }
            )
            .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95)))
            .zIndex(100)
        }
    }
    // Force solid background fill above the underlying camera UI
        .presentationBackground(Color(uiColor: .systemBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Ensure VoiceOver properly sequences the primary components autonomously upon render
        .onAppear {
            if UIAccessibility.isVoiceOverRunning {
                let announcement = isPoisonous ? "\(commonName). Warning: This subject is Poisonous." : commonName
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
            if inferenceEngine.speciesData?.isNewDiscovery == true {
                showCelebration = true
            }
        }
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            if !isStillProcessing {
                if inferenceEngine.speciesData?.isNewDiscovery != true {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }
}
}

