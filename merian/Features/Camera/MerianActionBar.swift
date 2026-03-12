import SwiftUI
import PhotosUI
import SwiftData

struct MerianActionBar: View {
    @Binding var isLifeListOpen: Bool
    @Binding var isPaywallOpen: Bool
    @Binding var isInsightSheetOpen: Bool
    @Binding var isAnalyzingFullscreen: Bool
    @Binding var isUserProfileOpen: Bool
    @Binding var imageToCrop: IdentifiableImage?
    
    var onCaptureTriggered: () -> Void
    
    var body: some View {
        HStack {
            // Life List
            GlassCircularButton(iconName: "book") {
                isLifeListOpen = true
            }
            
            Spacer()
            
            // The Shutter / Analyze Button
            Button(action: onCaptureTriggered) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 62, height: 62)
                }
            }
            
            Spacer()
            
            // User Profile Button
            GlassCircularButton(iconName: "person") {
                isUserProfileOpen = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .padding(.bottom, 24)
    }
}

