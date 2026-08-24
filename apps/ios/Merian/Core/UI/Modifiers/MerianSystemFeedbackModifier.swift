import SwiftUI

enum SystemFeedbackOverlayPolicy {
    static func suppressesToast(
        showsAchievementToasts: Bool,
        toastAlignment: SwiftUI.Alignment,
        milestoneAlignment: SwiftUI.Alignment,
        hasPresentedMilestone: Bool
    ) -> Bool {
        showsAchievementToasts
            && toastAlignment == milestoneAlignment
            && hasPresentedMilestone
    }

    static func allowsHitTesting(
        hasActionDescriptor: Bool,
        hasActionHandler: Bool
    ) -> Bool {
        hasActionDescriptor && hasActionHandler
    }
}

struct MerianSystemFeedbackModifier: SwiftUI.ViewModifier {
    @Binding var toast: ToastPayload?
    @Binding var toastAction: (() -> Void)?
    var toastAlignment: SwiftUI.Alignment
    var milestoneAlignment: SwiftUI.Alignment
    var showsAchievementToasts: Bool

    @Environment(MilestoneToastPresenter.self) private var milestoneToastPresenter:
        MilestoneToastPresenter?
    @Environment(MilestoneToastHostRegistry.self) private var milestoneToastHostRegistry:
        MilestoneToastHostRegistry?
    @Environment(AppRouteCoordinator.self) private var appRouteCoordinator:
        AppRouteCoordinator?
    @Environment(\.milestoneToastClock) private var milestoneToastClock

    @State private var milestoneHostID = UUID()

    func body(content: Content) -> some SwiftUI.View {
        content
            .overlay(alignment: toastAlignment) {
                toastOverlay
            }
            .overlay(alignment: milestoneAlignment) {
                milestoneOverlay
            }
            .onAppear {
                updateMilestoneHostRegistration()
            }
            .onChange(of: showsAchievementToasts) { _, _ in
                updateMilestoneHostRegistration()
            }
            .onDisappear {
                milestoneToastHostRegistry?.unregister(milestoneHostID)
            }
    }

    private var toastOverlay: some View {
        Group {
            if let toast, !isToastSuppressedByMilestone {
                toastBanner(for: toast)
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: ToastOverlayAnimationContext(
                toastID: toast?.id,
                isSuppressedByMilestone: isToastSuppressedByMilestone
            )
        )
    }

    private var isToastSuppressedByMilestone: Bool {
        SystemFeedbackOverlayPolicy.suppressesToast(
            showsAchievementToasts: showsAchievementToasts,
            toastAlignment: toastAlignment,
            milestoneAlignment: milestoneAlignment,
            hasPresentedMilestone: milestoneToastPresenter?.presentedItems.isEmpty == false
        )
    }

    private func toastBanner(for toast: ToastPayload) -> some View {
        let hasInteractiveControls = SystemFeedbackOverlayPolicy.allowsHitTesting(
            hasActionDescriptor: toast.action != nil,
            hasActionHandler: toastAction != nil
        )
        let onDismiss: (() -> Void)?
        let onAction: (() -> Void)?

        if hasInteractiveControls {
            onDismiss = { dismissToast(ifMatching: toast.id) }
            onAction = {
                let action = toastAction
                action?()
                dismissToast(ifMatching: toast.id)
            }
        } else {
            onDismiss = nil
            onAction = nil
        }

        return ToastPayloadBanner(
            payload: toast,
            onDismiss: onDismiss,
            onAction: onAction
        )
        .id(toast.id)
        .padding(
            toastAlignment == .top ? Edge.Set.top : Edge.Set.bottom,
            toastAlignment == .top ? 16 : 60
        )
        .transition(
            .move(edge: toastAlignment == .top ? Edge.top : Edge.bottom)
                .combined(with: .opacity)
        )
        .zIndex(100)
        .allowsHitTesting(hasInteractiveControls)
        .task(id: toast.id) {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled, self.toast?.id == toast.id else { return }
            dismissToast(ifMatching: toast.id)
        }
    }

    private var milestoneOverlay: some View {
        Group {
            if let milestoneToastPresenter,
               let milestoneToastHostRegistry,
               showsAchievementToasts,
               milestoneToastHostRegistry.activeHostID == milestoneHostID,
               !milestoneToastPresenter.presentedItems.isEmpty {
                MilestoneToastStack(
                    items: milestoneToastPresenter.presentedItems,
                    clock: milestoneToastClock,
                    onClaimPresentationEffects: { id, now in
                        milestoneToastPresenter.claimPresentationEffects(id: id, now: now)
                    },
                    automaticDismissInterval: { id, now in
                        milestoneToastPresenter.remainingAutomaticDismissInterval(
                            id: id,
                            now: now
                        )
                    },
                    onDismiss: { id in
                        milestoneToastPresenter.dismissActiveItem(id: id)
                    },
                    onOpenAchievement: { award in
                        appRouteCoordinator?.request(
                            .achievement(award),
                            source: .internalUserAction
                        )
                    },
                    onOpenFieldTrip: { destination in
                        appRouteCoordinator?.request(
                            .captureGoal(destination),
                            source: .internalUserAction
                        )
                    }
                )
                .padding(
                    milestoneAlignment == .top ? Edge.Set.top : Edge.Set.bottom,
                    milestoneAlignment == .top ? 16 : 24
                )
                .transition(
                    .move(edge: milestoneAlignment == .top ? .top : .bottom)
                        .combined(with: .opacity)
                )
                .zIndex(110)
            }
        }
        .animation(
            .easeInOut(duration: 0.2),
            value: isMilestoneOverlayVisible
        )
    }

    /// The outer overlay owns only host-level insertion and removal. Active
    /// item replacement is animated by `MilestoneToastStack`, while decorative
    /// backing-layer changes are animated by the toast surface. Keying this
    /// transaction to the full queue would allocate an ID array and apply a
    /// second animation to every FIFO mutation.
    private var isMilestoneOverlayVisible: Bool {
        guard let milestoneToastPresenter,
              let milestoneToastHostRegistry,
              showsAchievementToasts,
              milestoneToastHostRegistry.activeHostID == milestoneHostID else {
            return false
        }
        return !milestoneToastPresenter.presentedItems.isEmpty
    }

    private func updateMilestoneHostRegistration() {
        guard let milestoneToastHostRegistry else { return }
        if showsAchievementToasts {
            milestoneToastHostRegistry.register(milestoneHostID)
        } else {
            milestoneToastHostRegistry.unregister(milestoneHostID)
        }
    }

    private func dismissToast(ifMatching toastID: UUID) {
        guard toast?.id == toastID else { return }
        toast = nil
        toastAction = nil
    }

    private struct ToastOverlayAnimationContext: Equatable {
        let toastID: UUID?
        let isSuppressedByMilestone: Bool
    }
}

extension View {
    func merianSystemFeedback(
        toast: Binding<ToastPayload?>,
        toastAction: Binding<(() -> Void)?> = .constant(nil),
        toastAlignment: Alignment = .bottom,
        milestoneAlignment: Alignment = .bottom,
        showsAchievementToasts: Bool = true
    ) -> some View {
        self.modifier(MerianSystemFeedbackModifier(
            toast: toast,
            toastAction: toastAction,
            toastAlignment: toastAlignment,
            milestoneAlignment: milestoneAlignment,
            showsAchievementToasts: showsAchievementToasts
        ))
    }
}
