import SwiftUI
import CoreLocation

struct ConfidenceExplanationSheet: View {
    @State private var showLocationPrompt: Bool = false
    
    private func checkLocationStatus() {
        let manager = CLLocationManager()
        let status = manager.authorizationStatus
        showLocationPrompt = (status == .notDetermined || status == .restricted || status == .denied)
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // MARK: - Vibrant Header
                ConfidenceHeader()
                
                // MARK: - Continuous Spectrum Timeline
                ConfidenceSpectrum()
                
                // MARK: - AI Acknowledgment Banner
                AIMistakesBanner()
                
                // MARK: - Pro Tips
                ProTips(showLocationPrompt: showLocationPrompt)
            }
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .onAppear {
            checkLocationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkLocationStatus()
        }
    }
}
