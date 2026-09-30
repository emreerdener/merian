import MapKit
import Testing
import UIKit

@testable import Merian

@MainActor
struct MapUserLocationPriorityTests {
    @Test func nestedPinRaisesOnlyItsOwnAnnotationAboveObservationMarkers() {
        let container = UIView()
        let observation = MKAnnotationView()
        // Both maps select observations through Button/view-model state, not
        // MKAnnotationView.isSelected, so selected thumbnails retain this priority.
        observation.zPriority = .defaultUnselected
        let user = MKAnnotationView()
        user.displayPriority = .defaultLow
        let hostingView = UIView()
        let pin = MapUserLocationPriorityView()
        container.addSubview(observation)
        container.addSubview(user)
        user.addSubview(hostingView)
        hostingView.addSubview(pin)

        #expect(user.zPriority == .max)
        #expect(user.selectedZPriority == .max)
        #expect(user.displayPriority == .required)
        #expect(user.zPriority.rawValue > observation.zPriority.rawValue)
        #expect(observation.zPriority == .defaultUnselected)
    }

    @Test func layoutAfterDelayedHostingAttachmentRestoresPriority() {
        let hostingView = UIView()
        let pin = MapUserLocationPriorityView()
        hostingView.addSubview(pin)
        pin.updateAnnotationPriority() // No annotation host yet.

        let user = MKAnnotationView()
        user.addSubview(hostingView)
        pin.layoutSubviews()
        #expect(user.zPriority == .max)

        user.zPriority = .defaultUnselected
        user.selectedZPriority = .defaultSelected
        user.displayPriority = .defaultLow
        pin.layoutSubviews()
        #expect(user.zPriority == .max)
        #expect(user.selectedZPriority == .max)
        #expect(user.displayPriority == .required)
    }
}
