import SwiftUI

// MARK: - Primary Domain Models (Data received from InferenceEngine/Gemini Edge JSON)
struct SpeciesData {
    let commonName: String
    let scientificName: String
    let insightData: InsightData
    let confidenceScore: Double
    let diagnosticComparison: DiagnosticComparison?
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
