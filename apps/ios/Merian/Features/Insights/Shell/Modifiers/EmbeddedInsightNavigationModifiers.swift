import SwiftUI
import UIKit

struct EmbeddedInsightBackSwipeModifier: ViewModifier {
    let isEnabled: Bool
    let onBack: () -> Void

    @State private var didTriggerBack = false

    private let edgeActivationWidth: CGFloat = 44
    private let minimumHorizontalTranslation: CGFloat = 70
    private let minimumHorizontalVelocity: CGFloat = 420

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            if isEnabled {
                content
                    .simultaneousGesture(edgeSwipeGesture)
                    .overlay(alignment: .leading) {
                        Color.clear
                            .frame(width: edgeActivationWidth)
                            .contentShape(Rectangle())
                            .gesture(edgeSwipeGesture)
                    }
            } else {
                content
            }
        }
        .task(id: didTriggerBack) {
            guard didTriggerBack else { return }
            do {
                try await Task.sleep(for: .milliseconds(450))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            didTriggerBack = false
        }
    }

    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard shouldTriggerBack(for: value), !didTriggerBack else { return }

                didTriggerBack = true
                onBack()
            }
    }

    private func shouldTriggerBack(for value: DragGesture.Value) -> Bool {
        guard value.startLocation.x <= edgeActivationWidth else { return false }

        let horizontalTranslation = value.translation.width
        let verticalTranslation = abs(value.translation.height)
        let predictedHorizontalTranslation = value.predictedEndTranslation.width
        let horizontalVelocity = predictedHorizontalTranslation - horizontalTranslation

        guard horizontalTranslation > 0 else { return false }
        guard horizontalTranslation > verticalTranslation * 1.15 else { return false }

        return horizontalTranslation >= minimumHorizontalTranslation
            || horizontalVelocity >= minimumHorizontalVelocity
    }
}

struct EmbeddedNavigationSwipeBackEnabler: UIViewControllerRepresentable {
    var onNavigationPop: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationPop: onNavigationPop)
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        context.coordinator.onNavigationPop = onNavigationPop
        controller.enableSwipeBack()
    }

    final class Controller: UIViewController {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            return nil
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSwipeBack()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            enableSwipeBack()
        }

        func enableSwipeBack() {
            guard let navigationController else { return }
            coordinator.attach(to: navigationController)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var navigationController: UINavigationController?
        private weak var previousDelegate: UIGestureRecognizerDelegate?
        private var mountedNavigationDepth: Int?
        var onNavigationPop: () -> Void

        init(onNavigationPop: @escaping () -> Void) {
            self.onNavigationPop = onNavigationPop
        }

        func attach(to navigationController: UINavigationController) {
            guard self.navigationController !== navigationController else {
                enableGesture()
                return
            }

            restorePreviousDelegate()
            self.navigationController = navigationController
            mountedNavigationDepth = navigationController.viewControllers.count
            previousDelegate = navigationController.interactivePopGestureRecognizer?.delegate
            navigationController.interactivePopGestureRecognizer?.addTarget(
                self,
                action: #selector(handleInteractivePopGesture(_:))
            )
            enableGesture()
        }

        private func enableGesture() {
            guard let gesture = navigationController?.interactivePopGestureRecognizer else {
                return
            }

            gesture.isEnabled = true
            gesture.delegate = self
        }

        private func restorePreviousDelegate() {
            guard let gesture = navigationController?
                .interactivePopGestureRecognizer else { return }
            gesture.removeTarget(
                self,
                action: #selector(handleInteractivePopGesture(_:))
            )
            if gesture.delegate === self {
                gesture.delegate = previousDelegate
            }
        }

        @objc
        private func handleInteractivePopGesture(
            _ gesture: UIGestureRecognizer
        ) {
            guard gesture.state == .ended,
                  let mountedNavigationDepth,
                  let navigationController,
                  let transitionCoordinator = navigationController
                    .transitionCoordinator else { return }
            let onNavigationPop = onNavigationPop
            transitionCoordinator.animate(
                alongsideTransition: nil
            ) { [weak navigationController] context in
                guard !context.isCancelled,
                      let navigationController,
                      navigationController.viewControllers.count
                        < mountedNavigationDepth else {
                    return
                }
                onNavigationPop()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let navigationController,
                navigationController.viewControllers.count > 1
            else {
                return false
            }

            if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
                let translation = panGesture.translation(in: panGesture.view)
                guard translation.x > 0, abs(translation.x) > abs(translation.y) else {
                    return false
                }
            }

            return true
        }

        deinit {
            restorePreviousDelegate()
        }
    }
}

struct SpeciesDictionaryDestinationModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                    SpeciesDictionaryPageContentView(
                        scientificName: route.scientificName,
                        speciesId: route.speciesId,
                        entryPoint: route.entryPoint,
                        showsCloseButton: false
                    )
                }
        } else {
            content
        }
    }
}
