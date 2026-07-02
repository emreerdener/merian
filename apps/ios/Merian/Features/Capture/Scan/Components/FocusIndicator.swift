import SwiftUI

struct FocusIndicator: View {
    let showFocusIndicator: Bool
    let focusLocation: CGPoint?
    
    var body: some View {
        if showFocusIndicator, let location = focusLocation {
            FocusCorners()
                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 72, height: 72)
                .position(x: location.x, y: location.y)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: location)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - DSLR Corner Geometry
struct FocusCorners: Shape {
    let cornerLength: CGFloat = 20
    let cornerRadius: CGFloat = 8
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Top-Left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + cornerLength, y: rect.minY),
            radius: cornerRadius
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        
        // Top-Right
        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + cornerLength),
            radius: cornerRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        
        // Bottom-Right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY),
            radius: cornerRadius
        )
        path.addLine(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        
        // Bottom-Left
        path.move(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - cornerLength),
            radius: cornerRadius
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        
        return path
    }
}
