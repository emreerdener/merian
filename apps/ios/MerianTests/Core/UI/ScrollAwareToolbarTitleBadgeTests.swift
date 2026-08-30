import CoreData
import MapKit
import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Merian

@MainActor
final class ScrollAwareToolbarTitleBadgeTests: XCTestCase {
    private let longTitle = "Fragrant Olive, Sweet Olive, Tea Olive, and Many More Common Names"

    func testLongTitleUsesCompactMaximumWidth() {
        let size = fittingSize(for: longTitle, horizontalSizeClass: .compact)

        XCTAssertEqual(size.width, 200, accuracy: 0.5)
    }

    func testLongTitleUsesRegularMaximumWidth() {
        let size = fittingSize(for: longTitle, horizontalSizeClass: .regular)

        XCTAssertEqual(size.width, 320, accuracy: 0.5)
    }

    func testShortTitleKeepsItsNaturalWidth() {
        let size = fittingSize(for: "Bee", horizontalSizeClass: .compact)

        XCTAssertLessThan(size.width, 200)
    }

    private func fittingSize(
        for title: String,
        horizontalSizeClass: UserInterfaceSizeClass
    ) -> CGSize {
        let view = ScrollAwareToolbarTitleBadge(title: title, isVisible: true)
            .environment(\.horizontalSizeClass, horizontalSizeClass)
        let controller = UIHostingController(rootView: view)

        return controller.sizeThatFits(in: CGSize(width: 1_000, height: 100))
    }
}
