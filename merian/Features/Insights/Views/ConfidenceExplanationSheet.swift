import CoreLocation
import SwiftUI

struct ConfidenceExplanationSheet: View {
    let inferenceTier: String?
    var userIdentificationOverride: String?
    var userConfirmedIdentification: Bool = false
    var aiScientificName: String?

    @Environment(EnvironmentContextManager.self) private var environmentContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext

    private var showLocationPrompt: Bool {
        let status = environmentContext.locationAuthorizationStatus
        return status == .notDetermined || status == .restricted || status == .denied
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                ConfidenceHeader()
                
                if let override = userIdentificationOverride {
                    OverriddenView(
                        overrideName: override,
                        aiScientificName: aiScientificName ?? "Unknown",
                        onUndo: {
                            Task {
                                await inferenceEngine.resetIdentificationReview(modelContext: modelContext)
                            }
                        }
                    )
                    .padding(.horizontal, 24)
                } else if userConfirmedIdentification {
                    ConfirmedView(
                        onReset: {
                            Task {
                                await inferenceEngine.resetIdentificationReview(modelContext: modelContext)
                            }
                        }
                    )
                    .padding(.horizontal, 24)
                    
                    ConfidenceSpectrum(inferenceTier: inferenceTier)
                    AIMistakesBanner()
                    ProTips(showLocationPrompt: showLocationPrompt)
                } else {
                    ConfidenceSpectrum(inferenceTier: inferenceTier)
                    AIMistakesBanner()
                    ProTips(showLocationPrompt: showLocationPrompt)
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Confirmed View (State 3)

private struct ConfirmedView: View {
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("You confirmed this identification")
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Button("Change", action: onReset)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .buttonStyle(.plain)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Overridden View (State 4)

private struct OverriddenView: View {
    let overrideName: String
    let aiScientificName: String
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.checkmark")
                    .foregroundColor(.indigo)
                Text("Your identification")
                    .font(.system(.headline))
                    .foregroundColor(.primary)
                Spacer()
                Button("Undo", action: onUndo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
            }

            Text(overrideName)
                .font(.system(.subheadline, design: .serif).italic())
                .foregroundColor(.primary)

            Text("AI originally suggested *\(aiScientificName)*")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
    }
}
