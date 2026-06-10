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

    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard shouldTriggerBack(for: value), !didTriggerBack else { return }

                didTriggerBack = true
                onBack()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    didTriggerBack = false
                }
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
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
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

        func attach(to navigationController: UINavigationController) {
            guard self.navigationController !== navigationController else {
                enableGesture()
                return
            }

            restorePreviousDelegate()
            self.navigationController = navigationController
            previousDelegate = navigationController.interactivePopGestureRecognizer?.delegate
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
            guard
                let gesture = navigationController?.interactivePopGestureRecognizer,
                gesture.delegate === self
            else { return }

            gesture.delegate = previousDelegate
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
