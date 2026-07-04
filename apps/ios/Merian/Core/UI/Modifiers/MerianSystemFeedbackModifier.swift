import SwiftData
import SwiftUI

struct MerianSystemFeedbackModifier: SwiftUI.ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Binding var toastMessage: String?
    @Binding var toastActionTitle: String?
    @Binding var toastAction: (() -> Void)?
    @Binding var showCelebration: Bool
    var commonNameForCelebration: String
    var toastAlignment: SwiftUI.Alignment
    var showsAchievementToasts: Bool

    @State private var achievementToastPresenter = AchievementToastPresenter.shared
    @State private var selectedAchievementToastAward: AwardPayload?

    func body(content: Content) -> some SwiftUI.View {
        ZStack(alignment: .top) {
            content

            if let message = toastMessage {
                VStack {
                    if toastAlignment == .bottom { Spacer() }
                    
                    ToastBanner(onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toastMessage = nil
                            toastActionTitle = nil
                            toastAction = nil
                        }
                    }) {
                        HStack(spacing: 12) {
                            Text(message)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            if let actionTitle = toastActionTitle, let action = toastAction {
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
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .padding(toastAlignment == .top ? Edge.Set.top : Edge.Set.bottom, toastAlignment == .top ? 16 : 60)
                    
                    if toastAlignment == .top { Spacer() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: toastAlignment == .top ? Edge.top : Edge.bottom).combined(with: .opacity))
                .zIndex(100)
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toastMessage = nil
                        toastActionTitle = nil
                        toastAction = nil
                    }
                }
            }

            CelebrationBanner(
                commonName: commonNameForCelebration,
                showCelebration: $showCelebration
            )

            if showsAchievementToasts, let item = achievementToastPresenter.activeUnlock {
                AchievementToastBanner(
                    item: item,
                    onDismiss: {
                        achievementToastPresenter.dismissActiveUnlock(id: item.id)
                    },
                    onOpen: {
                        selectedAchievementToastAward = item.award
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(110)
            }
        }
        .sheet(item: $selectedAchievementToastAward) { award in
            AchievementDetailSheet(award: award, modelContainer: modelContext.container)
        }
    }
}

extension View {
    func merianSystemFeedback(
        toastMessage: Binding<String?>,
        toastActionTitle: Binding<String?> = .constant(nil),
        toastAction: Binding<(() -> Void)?> = .constant(nil),
        showCelebration: Binding<Bool> = .constant(false),
        commonNameForCelebration: String = "",
        toastAlignment: Alignment = .bottom,
        showsAchievementToasts: Bool = true
    ) -> some View {
        self.modifier(MerianSystemFeedbackModifier(
            toastMessage: toastMessage,
            toastActionTitle: toastActionTitle,
            toastAction: toastAction,
            showCelebration: showCelebration,
            commonNameForCelebration: commonNameForCelebration,
            toastAlignment: toastAlignment,
            showsAchievementToasts: showsAchievementToasts
        ))
    }
}
