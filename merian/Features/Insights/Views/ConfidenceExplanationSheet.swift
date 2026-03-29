import CoreLocation
import SwiftUI

struct ConfidenceExplanationSheet: View {
    let inferenceTier: String?
    @Environment(EnvironmentContextManager.self) private var environmentContext

    private var showLocationPrompt: Bool {
        let status = environmentContext.locationAuthorizationStatus
        return status == .notDetermined || status == .restricted || status == .denied
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // MARK: - Vibrant Header
                ConfidenceHeader()

                // MARK: - Continuous Spectrum Timeline
                ConfidenceSpectrum(inferenceTier: inferenceTier)
                
                // MARK: - AI Acknowledgment Banner
                AIMistakesBanner()
                
                // MARK: - Pro Tips
                ProTips(showLocationPrompt: showLocationPrompt)
            }
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }
}
