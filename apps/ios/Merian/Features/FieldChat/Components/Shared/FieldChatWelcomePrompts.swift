import SwiftUI

@MainActor
struct FieldChatWelcomePrompts: View {
    let candidates: [String]
    let isLoading: Bool
    let isVisible: Bool
    let isOnline: Bool
    let onSelection: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = FieldChatPromptRevealModel()

    private struct Input: Equatable {
        let candidates: [String]
        let isLoading: Bool
        let isVisible: Bool
    }

    var body: some View {
        Group {
            if isVisible {
                VStack(spacing: 10) {
                    if let prompts = model.displayedPrompts {
                        ForEach(prompts, id: \.self) { prompt in
                            Button { onSelection(prompt) } label: { promptLabel(prompt) }
                                .buttonStyle(.plain)
                                .disabled(!isOnline)
                        }
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
                    } else {
                        // Reserve space without exposing temporary questions or tappable controls.
                        ForEach(Array(candidates.prefix(3)), id: \.self) { prompt in
                            promptLabel(prompt).hidden()
                        }
                        .accessibilityHidden(true)
                        .transition(.identity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .accessibilityIdentifier("FieldChatWelcomePrompts")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: model.isRevealed)
        .onChange(of: Input(candidates: candidates, isLoading: isLoading, isVisible: isVisible), initial: true) { _, input in
            model.update(candidates: input.candidates, isLoading: input.isLoading, isVisible: input.isVisible)
        }
        .task(id: model.isRevealed) {
            await model.waitForFallback()
        }
    }

    private func promptLabel(_ prompt: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(prompt)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.forward")
                .accessibilityHidden(true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(minHeight: 24)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : .white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
