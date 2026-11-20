import MapKit
import Testing
import UIKit

@testable import Merian

@MainActor
struct MapUserLocationPriorityTests {
    @Test func observationsRemainBelowTheDefaultUserLocationIncludingSelection() {
        let container = UIView()
        let user = MKUserLocationView(annotation: MKUserLocation(), reuseIdentifier: nil)
        let userPriority = user.zPriority
        let observation = MKAnnotationView()
        observation.displayPriority = .defaultLow
        let hostingView = UIView()
        let bridge = MapObservationPriorityView()
        container.addSubview(user)
        container.addSubview(observation)
        observation.addSubview(hostingView)
        hostingView.addSubview(bridge)

        let unselectedPriority = observation.zPriority
        #expect(unselectedPriority.rawValue < user.zPriority.rawValue)
        #expect(observation.selectedZPriority.rawValue < user.zPriority.rawValue)
        #expect(observation.displayPriority == .defaultLow)

        bridge.isSelected = true
        bridge.updateAnnotationPriority()
        #expect(observation.zPriority.rawValue > unselectedPriority.rawValue)
        #expect(observation.zPriority.rawValue < user.zPriority.rawValue)
        #expect(user.zPriority == userPriority)

        bridge.isSelected = false
        bridge.updateAnnotationPriority()
        #expect(observation.zPriority == unselectedPriority)
    }

    @Test func layoutAfterDelayedHostingAttachmentRestoresPriority() {
        let hostingView = UIView()
        let bridge = MapObservationPriorityView()
        hostingView.addSubview(bridge)
        bridge.updateAnnotationPriority() // No annotation host yet.

        let observation = MKAnnotationView()
        observation.addSubview(hostingView)
        bridge.layoutSubviews()
        #expect(observation.zPriority == .min)

        observation.zPriority = .max
        observation.selectedZPriority = .max
        bridge.layoutSubviews()
        #expect(observation.zPriority == .min)
        #expect(observation.selectedZPriority.rawValue < MKAnnotationViewZPriority.defaultUnselected.rawValue)
    }
}
