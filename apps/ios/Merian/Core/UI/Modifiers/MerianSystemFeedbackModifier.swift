import SwiftUI

struct MerianSystemFeedbackModifier: SwiftUI.ViewModifier {
    @Binding var toastMessage: String?
    @Binding var toastActionTitle: String?
    @Binding var toastAction: (() -> Void)?
    var toastAlignment: SwiftUI.Alignment
    var showsAchievementToasts: Bool

    @State private var milestoneToastPresenter = MilestoneToastPresenter.shared

    func body(content: Content) -> some SwiftUI.View {
        content
            .overlay(alignment: toastAlignment) {
                if let message = toastMessage,
                   !showsAchievementToasts || milestoneToastPresenter.presentedItems.isEmpty {
                    let display = SystemToastDisplay(message: message)

                    ToastBanner(onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toastMessage = nil
                            toastActionTitle = nil
                            toastAction = nil
                        }
                    }) {
                        HStack(alignment: .center, spacing: 12) {
                            if display.isError {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.orange)
                                    .frame(width: 22, height: 22)
                                    .accessibilityHidden(true)
                            }

                            VStack(alignment: .leading, spacing: display.body == nil ? 0 : 3) {
                                Text(display.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)

                                if let body = display.body {
                                    Text(body)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            if let actionTitle = toastActionTitle, let action = toastAction {
                                Spacer(minLength: 0)

                                Button(action: {
                                    action()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        toastMessage = nil
                                        toastActionTitle = nil
                                        toastAction = nil
                                    }
                                }) {
                                    Text(actionTitle)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(
                        toastAlignment == .top ? Edge.Set.top : Edge.Set.bottom,
                        toastAlignment == .top ? 16 : 60
                    )
                    .transition(
                        .move(edge: toastAlignment == .top ? Edge.top : Edge.bottom)
                            .combined(with: .opacity)
                    )
                    .zIndex(100)
                    .task(id: message) {
                        do {
                            try await Task.sleep(for: .seconds(3))
                        } catch {
                            return
                        }
                        guard !Task.isCancelled, toastMessage == message else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toastMessage = nil
                            toastActionTitle = nil
                            toastAction = nil
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: toastMessage)
            .animation(
                .easeInOut(duration: 0.2),
                value: milestoneToastPresenter.presentedItems.map(\.id)
            )
            .overlay(alignment: .bottom) {
                if showsAchievementToasts, !milestoneToastPresenter.presentedItems.isEmpty {
                    MilestoneToastStack(
                        items: milestoneToastPresenter.presentedItems,
                        onDismiss: { id in
                            milestoneToastPresenter.dismissActiveItem(id: id)
                        },
                        onOpenAchievement: { award in
                            AppDIContainer.shared.appRouteCoordinator.request(
                                .achievement(award),
                                source: .internalUserAction
                            )
                        },
                        onOpenFieldTrip: { destination in
                            AppDIContainer.shared.appRouteCoordinator.request(
                                .captureGoal(destination),
                                source: .internalUserAction
                            )
                        }
                    )
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(110)
                }
            }
    }
}

extension View {
    func merianSystemFeedback(
        toastMessage: Binding<String?>,
        toastActionTitle: Binding<String?> = .constant(nil),
        toastAction: Binding<(() -> Void)?> = .constant(nil),
        toastAlignment: Alignment = .bottom,
        showsAchievementToasts: Bool = true
    ) -> some View {
        self.modifier(MerianSystemFeedbackModifier(
            toastMessage: toastMessage,
            toastActionTitle: toastActionTitle,
            toastAction: toastAction,
            toastAlignment: toastAlignment,
            showsAchievementToasts: showsAchievementToasts
        ))
    }
}

private struct SystemToastDisplay {
    let title: String
    let body: String?
    let isError: Bool

    init(message: String) {
        let parts = message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = parts.first, parts.count > 1 {
            title = first
            body = parts.dropFirst().joined(separator: " ")
        } else {
            title = message.trimmingCharacters(in: .whitespacesAndNewlines)
            body = nil
        }

        isError = Self.isErrorTitle(title) || body?.localizedCaseInsensitiveContains("try again") == true
    }

    private static func isErrorTitle(_ title: String) -> Bool {
        let lowercasedTitle = title.lowercased()
        return lowercasedTitle.hasPrefix("couldn't")
            || lowercasedTitle.hasPrefix("couldn’t")
            || lowercasedTitle.hasPrefix("could not")
            || lowercasedTitle.hasPrefix("can't")
            || lowercasedTitle.hasPrefix("can’t")
            || lowercasedTitle.hasPrefix("unable")
            || lowercasedTitle.hasPrefix("error")
            || lowercasedTitle.hasPrefix("we couldn't")
            || lowercasedTitle.hasPrefix("we couldn’t")
    }
}
