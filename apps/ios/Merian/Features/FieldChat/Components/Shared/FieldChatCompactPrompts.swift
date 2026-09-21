import SwiftUI

/// Keeps one revealed set stable until the sheet supplies a new conversation identity.
@MainActor
struct FieldChatCompactPrompts: View {
    let candidates: [String]
    let isLoading: Bool
    let isVisible: Bool
    let isOnline: Bool
    let onSelection: (String) -> Void
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let prompts = model.displayedPrompts {
                            ForEach(prompts, id: \.self) { prompt in
                                Button { onSelection(prompt) } label: { chipLabel(prompt) }
                                    .buttonStyle(.plain)
                                    .disabled(!isOnline)
                            }
                            .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8)))
                        } else {
                            ForEach(Array(candidates.prefix(3)), id: \.self) { prompt in
                                chipLabel(prompt).hidden()
                            }
                            .accessibilityHidden(true)
                            .transition(.identity)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .transparentTopToolbar()
                .padding(.top, 8)
                .padding(.bottom, 2)
                .accessibilityIdentifier("FieldChatCompactPrompts")
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

    private func chipLabel(_ prompt: String) -> some View {
        Text(prompt)
            .lineLimit(1)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Capsule(style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            .overlay(Capsule(style: .continuous).stroke(Color.accentColor.opacity(0.28), lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
    }
}
