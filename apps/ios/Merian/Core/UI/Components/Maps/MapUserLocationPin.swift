import MapKit
import SwiftUI

/// Custom content for UserAnnotation, which retains MapKit's live location updates.
struct MapUserLocationPin: View {
    var body: some View {
        pinShape
            .fill(.blue)
            .overlay {
                pinShape.stroke(.white, lineWidth: 2)
            }
            .overlay(alignment: .top) {
                Image(systemName: "person.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 7)
            }
            .frame(width: 32, height: 42)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            .background(MapUserLocationPriority())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your location")
            .accessibilityAddTraits(.isImage)
            .allowsHitTesting(false)
    }

    private var pinShape: Path {
        Path { path in
            path.move(to: CGPoint(x: 16, y: 41))
            path.addCurve(
                to: CGPoint(x: 1, y: 16),
                control1: CGPoint(x: 12, y: 34),
                control2: CGPoint(x: 1, y: 26)
            )
            path.addArc(
                center: CGPoint(x: 16, y: 16), radius: 15,
                startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false
            )
            path.addCurve(
                to: CGPoint(x: 16, y: 41),
                control1: CGPoint(x: 31, y: 26),
                control2: CGPoint(x: 20, y: 34)
            )
            path.closeSubpath()
        }
    }
}

private struct MapUserLocationPriority: UIViewRepresentable {
    func makeUIView(context: Context) -> MapUserLocationPriorityView {
        let view = MapUserLocationPriorityView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: MapUserLocationPriorityView, context: Context) {
        uiView.updateAnnotationPriority()
    }
}

/// SwiftUI zIndex only orders content inside an annotation. Set MapKit's own
/// priorities on the enclosing annotation instead, without replacing its delegate
/// or depending on private hosting-view class names.
final class MapUserLocationPriorityView: UIView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateAnnotationPriority()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnnotationPriority()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateAnnotationPriority()
    }

    func updateAnnotationPriority() {
        var ancestor = superview
        while let view = ancestor {
            if let annotation = view as? MKAnnotationView {
                if annotation.zPriority != .max { annotation.zPriority = .max }
                if annotation.selectedZPriority != .max { annotation.selectedZPriority = .max }
                if annotation.displayPriority != .required { annotation.displayPriority = .required }
                return
            }
            ancestor = view.superview
        }
    }
}
