import SwiftUI

struct CameraFocusIndicatorView: View {
    let showFocusIndicator: Bool
    let focusLocation: CGPoint?
    
    var body: some View {
        if showFocusIndicator, let location = focusLocation {
            Rectangle()
                .stroke(Color.yellow, lineWidth: 1.5)
                .frame(width: 72, height: 72)
                .position(x: location.x, y: location.y)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: location)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
