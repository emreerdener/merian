import SwiftUI

struct CameraZoomControl: View {
    @EnvironmentObject var cameraManager: CameraManager
    
    var body: some View {
        HStack(spacing: 24) {
            ForEach(cameraManager.availableZoomFactors, id: \.self) { factor in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        cameraManager.setZoom(factor: factor)
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    Text(formatZoom(factor))
                        .font(.system(size: 15, weight: cameraManager.activeZoomFactor == factor ? .bold : .medium))
                        .foregroundColor(cameraManager.activeZoomFactor == factor ? .yellow : .white)
                        .frame(width: 44, height: 44)
                        .background(
                            ZStack {
                                if cameraManager.activeZoomFactor == factor {
                                    Circle()
                                        .fill(Color.black.opacity(0.6))
                                }
                            }
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func formatZoom(_ factor: CGFloat) -> String {
        let isInt = factor.truncatingRemainder(dividingBy: 1) == 0
        let baseString = isInt ? "\(Int(factor))" : String(format: "%.1f", factor)
        return cameraManager.activeZoomFactor == factor ? "\(baseString)x" : baseString
    }
}
