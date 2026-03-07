import SwiftUI

import SafariServices

// MARK: - Primary Domain Models (Data received from InferenceEngine/Gemini Edge JSON)
struct SpeciesData {
    let commonName: String
    let scientificName: String
    let insightData: InsightData
    let confidenceScore: Double
    let diagnosticComparison: DiagnosticComparison?
    let wikipediaUrl: String?
    let referenceImageUrl: String?
}

struct InsightData {
    let description: String
    let isPoisonous: Bool
}

struct DiagnosticComparison {
    let primaryMatchRationale: String
    let confusingLookalikeName: String
    let keyDifferentiators: [KeyDifferentiator]
}

struct KeyDifferentiator: Identifiable {
    let id = UUID()
    let trait: String
    let subjectValue: String
    let lookalikeValue: String
}

// MARK: - Insight Sheet View
struct InsightSheetView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine

    @Binding var isPresented: Bool
    
    @State private var isSafariPresented = false
    @State private var selectedWikiURL: URL?
    
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // 0. The Image Carousel (Active Capture + Wikipedia Reference)
                let refUrls: [String] = inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",") ?? []
                let hasReferenceImage = !refUrls.isEmpty
                let hasUserImage = (inferenceEngine.activePayload != nil)
                
                if hasUserImage || hasReferenceImage {
                    TabView {
                        // Tab 0: User's Uploaded Image
                        if let payload = inferenceEngine.activePayload, let uiImage = UIImage(data: payload) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 250)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .tag("user_image")
                        }
                        
                        // Tab 1+: Wikipedia / GBIF Reference Images
                        ForEach(Array(refUrls.enumerated()), id: \.offset) { index, urlString in
                            if let refUrl = URL(string: urlString) {
                                AsyncImage(url: refUrl) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(height: 250)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.white.opacity(0.1))
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(height: 250)
                                            .frame(maxWidth: .infinity)
                                            .clipped()
                                    case .failure:
                                        Image(systemName: "photo")
                                            .font(.largeTitle)
                                            .foregroundColor(.gray.opacity(0.5))
                                            .frame(height: 250)
                                            .frame(maxWidth: .infinity)
                                            .background(Color.white.opacity(0.1))
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                .tag("ref_\(index)")
                            }
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                    .frame(height: 250)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // 1. The Toxicity Banner (Safety Critical)
                if isPoisonous {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                        VStack(alignment: .leading) {
                            Text("DANGER: TOXIC")
                                .font(.headline)
                            Text("This subject is known to be poisonous.")
                                .font(.subheadline)
                        }
                        Spacer()
                        
                        Button(action: {
                            print("Contact Local Experts Triggered")
                        }) {
                            Text("Contact")
                                .fontWeight(.bold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                        // Accessibility: Clear interactive routing
                        .accessibilityHint("Double tap to contact local poison control experts.")
                    }
                    .padding()
                    .background(Color.red.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    // Accessibility: Explicitly anchor screen readers to the threat first
                    .accessibilityAddTraits(.isHeader)
                }
                
                // 2. Core Taxonomy Block
                VStack(alignment: .leading, spacing: 4) {
                    Text(commonName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        // Tie header routing to the name if there's no active poison banner
                        .accessibilityAddTraits(isPoisonous ? [] : .isHeader)
                    
                    Text(scientificName)
                        .font(.title3)
                        .italic()
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                // 3. Ecological Descriptive Insight
                if let description = inferenceEngine.speciesData?.insightData.description {
                    Text(description)
                        .font(.body)
                        .padding(.horizontal)
                        
                    if let wikiString = inferenceEngine.speciesData?.wikipediaUrl, let wikiUrl = URL(string: wikiString) {
                        Button(action: {
                            selectedWikiURL = wikiUrl
                            isSafariPresented = true
                        }) {
                            HStack {
                                Image(systemName: "safari.fill")
                                Text("Read more on Wikipedia")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .foregroundColor(.primary)
                    }
                }
                
                // 4. Fallback Validation Block
                if let score = inferenceEngine.speciesData?.confidenceScore, score < 0.85, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                    DiagnosticComparisonView(diagnosticData: diagnosticData)
                        .padding(.horizontal)
                        .padding(.top, 16)
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
        // Force glassmorphism bounds gracefully above the underlying camera UI
        .presentationBackground(.ultraThinMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Ensure VoiceOver properly sequences the primary components autonomously upon render
        .onAppear {
            if UIAccessibility.isVoiceOverRunning {
                let announcement = isPoisonous ? "\(commonName). Warning: This subject is Poisonous." : commonName
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
        }
    }
}
// MARK: - Safari View Wrapper
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {}
}
