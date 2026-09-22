import SwiftUI
import XCTest

@testable import Merian

/// Retains deterministic visual evidence without opening a live chat endpoint.
@MainActor
final class FieldChatEmptyStateRenderingTests: XCTestCase {
    func testCompactSuggestionVisualFixtures() async throws {
        for (name, loading, dark) in [
            ("loading", true, false),
            ("ready", false, false),
            ("dark", false, true)
        ] {
            let content = FieldChatCompactPrompts(
                candidates: ["What habitat does it prefer?", "How can I distinguish it?"],
                isLoading: loading, isVisible: true, isOnline: true, onSelection: { _ in }
            )
            let controller = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 180))
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            controller.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(350))
            controller.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "field-chat-compact-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testEmptyStateVisualFixtures() async throws {
        let image = try XCTUnwrap(UIImage(named: "fieldtrip-park-flowering-plant"))
        for (name, count, dark, largeText, compact, fails) in [
            ("single-light", 1, false, false, false, false),
            ("stack-light", 3, false, false, false, false),
            ("stack-tall", 3, false, false, false, false),
            ("waiting-for-prompts", 3, false, false, false, false),
            ("five-image-stack", 5, false, false, false, false),
            ("stack-dark", 3, true, false, false, false),
            ("stack-large-text-compact", 3, false, true, true, false),
            ("no-images", 0, false, false, false, false),
            ("failed-images", 2, false, false, false, true)
        ] {
            var loadCount = 0
            let media = (0..<count).compactMap {
                FieldChatMedia.image(
                    path: "fixture-\($0).jpg", label: "Species reference image",
                    attribution: "Example photographer · https://example.org/credit · https://creativecommons.org/licenses/by/4.0/ · Reference"
                )
            }
            let height: CGFloat = name == "stack-tall" ? 1000 : compact ? 280 : 620
            let content = ScrollView {
                FieldChatEmptyState(
                    displayName: "Dakota Mock Vervain",
                    media: media,
                    imageDependencies: .init { _, _ in
                        loadCount += 1
                        return fails ? nil : image
                    },
                    prompts: [
                        "What traits are characteristic of Dakota Mock Vervain?",
                        "What habitat does Dakota Mock Vervain prefer?",
                        "What is most interesting about Dakota Mock Vervain?"
                    ],
                    isLoadingPrompts: name == "waiting-for-prompts",
                    onImageSelection: {}
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: height, alignment: .top)
            }
            .background {
                Color(uiColor: .systemBackground)
                InsightChatEmptyAccentGradient()
            }
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)

            let controller = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: height))
            controller.overrideUserInterfaceStyle = dark ? .dark : .light
            window.overrideUserInterfaceStyle = dark ? .dark : .light
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()

            // Allow SwiftUI's structured image tasks and layout to settle.
            for _ in 0..<50 where loadCount < min(count, 3) {
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertGreaterThanOrEqual(loadCount, min(count, 3))
            controller.view.layoutIfNeeded()
            if compact {
                let scrollView = try XCTUnwrap(findScrollView(in: controller.view))
                XCTAssertGreaterThan(scrollView.contentSize.height, scrollView.bounds.height)
                scrollView.setContentOffset(
                    CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.bounds.height),
                    animated: false
                )
                controller.view.layoutIfNeeded()
            }

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let rendered = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "field-chat-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        return view.subviews.lazy.compactMap { self.findScrollView(in: $0) }.first
    }
}
