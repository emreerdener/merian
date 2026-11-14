import MapKit
import SwiftUI

/// Keep app annotations below the untouched, system-styled UserAnnotation.
struct MapObservationPriority: UIViewRepresentable {
    var isSelected = false

    func makeUIView(context: Context) -> MapObservationPriorityView {
        let view = MapObservationPriorityView()
        view.isSelected = isSelected
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: MapObservationPriorityView, context: Context) {
        uiView.isSelected = isSelected
        uiView.updateAnnotationPriority()
    }
}

/// SwiftUI zIndex only orders content inside an annotation. Set MapKit's own
/// priorities on the enclosing annotation instead, without replacing its delegate
/// or depending on private hosting-view class names.
final class MapObservationPriorityView: UIView {
    var isSelected = false

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
                // Selected observations stay above other observations, but both
                // remain below MapKit's default user-location annotation.
                let selectedPriority = MKAnnotationViewZPriority(
                    rawValue: MKAnnotationViewZPriority.defaultUnselected.rawValue - 1
                )
                let priority: MKAnnotationViewZPriority = isSelected ? selectedPriority : .min
                if annotation.zPriority != priority { annotation.zPriority = priority }
                if annotation.selectedZPriority != selectedPriority {
                    annotation.selectedZPriority = selectedPriority
                }
                return
            }
            ancestor = view.superview
        }
    }
}
