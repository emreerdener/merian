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
    
    let isBiological: Bool
    let isLiveCapture: Bool
    let isInvasive: Bool
    let ecologyType: String
    let taxonomy: TaxonomyData?
}

struct TaxonomyData {
    let kingdom: String?
    let phylum: String?
    let className: String?
    let order: String?
    let family: String?
    let genus: String?
}

struct InsightData {
    let description: String
    let isPoisonous: Bool
    let regionalStatusRationale: String?
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
                let hasUserImage = !inferenceEngine.activePayloads.isEmpty
                
                if hasUserImage || hasReferenceImage {
                    TabView {
                        // User's Uploaded Images (Historic Pipeline)
                        ForEach(Array(inferenceEngine.activePayloads.enumerated()), id: \.offset) { index, payload in
                            if let uiImage = UIImage(data: payload) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 250)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .tag("user_image_\(index)")
                            }
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
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.gray)
                            .padding(.top, 2)
                        Text("Edibility Unknown. Merian is an educational tool. Never ingest wild flora.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // 2. Core Taxonomy Block
                VStack(alignment: .leading, spacing: 4) {
                    Text(commonName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        // Tie header routing to the name if there's no active poison banner
                        .accessibilityAddTraits(isPoisonous ? [] : .isHeader)
                    
                    HStack {
                        Text(scientificName)
                            .font(.title3)
                            .italic()
                            .foregroundColor(.secondary)
                            
                        if let score = inferenceEngine.speciesData?.confidenceScore, score > 0.0 {
                            Text("\(Int(score * 100))% Match")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(score >= 0.85 ? .green : .orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(score >= 0.85 ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    
                    if let species = inferenceEngine.speciesData {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if species.isInvasive {
                                    BadgeView(text: "Invasive", color: .purple, icon: "exclamationmark.shield.fill")
                                }
                                
                                if !species.isLiveCapture {
                                    BadgeView(text: "Not a Live Capture", color: .gray, icon: "photo.badge.exclamationmark.fill")
                                }
                                
                                if !species.isBiological {
                                    BadgeView(text: "Not Biological", color: .gray, icon: "xmark.seal.fill")
                                }
                                
                                if species.ecologyType != "unknown" {
                                    BadgeView(text: species.ecologyType.capitalized, color: .blue, icon: "leaf.fill")
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal)
                
                // 3. Ecological Descriptive Insight
                if let description = inferenceEngine.speciesData?.insightData.description {
                    Text(description)
                        .font(.body)
                        .padding(.horizontal)
                        
                    if let rationale = inferenceEngine.speciesData?.insightData.regionalStatusRationale {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Regional Context")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            Text(rationale)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                        
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
                    
                    // 3.5 Taxonomy Tree
                    if let taxonomy = inferenceEngine.speciesData?.taxonomy {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Taxonomy")
                                .font(.headline)
                                .padding(.horizontal)
                                
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    if let kingdom = taxonomy.kingdom { TaxonomyNode(level: "Kingdom", name: kingdom) }
                                    if let phylum = taxonomy.phylum { TaxonomyNode(level: "Phylum", name: phylum) }
                                    if let cls = taxonomy.className { TaxonomyNode(level: "Class", name: cls) }
                                    if let order = taxonomy.order { TaxonomyNode(level: "Order", name: order) }
                                    if let family = taxonomy.family { TaxonomyNode(level: "Family", name: family) }
                                    if let genus = taxonomy.genus { TaxonomyNode(level: "Genus", name: genus) }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top, 8)
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
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            if !isStillProcessing {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

// MARK: - Helper Views
struct BadgeView: View {
    let text: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(12)
    }
}

struct TaxonomyNode: View {
    let level: String
    let name: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(level)
                .font(.caption2)
                .bold()
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}
