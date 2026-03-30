import CoreLocation
import SwiftUI

struct ConfidenceExplanationSheet: View {
    let inferenceTier: String?
    var userIdentificationOverride: String?
    var aiScientificName: String?

    @Environment(EnvironmentContextManager.self) private var environmentContext

    private var showLocationPrompt: Bool {
        let status = environmentContext.locationAuthorizationStatus
        return status == .notDetermined || status == .restricted || status == .denied
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                if let override = userIdentificationOverride {
                    // Override-specific explanation
                    ConfidenceHeader()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("You identified this as")
                            .font(.headline)
                        Text(override)
                            .font(.system(.body, design: .serif).italic())
                            .foregroundColor(.indigo)
                        if let ai = aiScientificName {
                            Text("The AI originally identified this as *\(ai)*.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Text("Your identification overrides the AI result and is stored on this scan. You can undo this from the \"Your identification\" card below.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 24)
                } else {
                    ConfidenceHeader()
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
