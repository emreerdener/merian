import SwiftUI

// MARK: - Supporting types

struct GuidedQuestion: Hashable {
    struct Tag: Hashable {
        let label: String
        /// Optimized natural-language fragment written into freeText.
        let aiText: String
    }
    let prompt: String
    let tags: [Tag]
}

let guidedQuestions: [GuidedQuestion] = [
    GuidedQuestion(
        prompt: "What did you see?",
        tags: [
            .init(label: "A bird", aiText: "a bird"),
            .init(label: "An insect", aiText: "an insect"),
            .init(label: "A spider", aiText: "a spider or arachnid"),
            .init(label: "A reptile", aiText: "a reptile or amphibian"),
            .init(label: "A plant", aiText: "a plant or flower"),
            .init(label: "A mushroom", aiText: "a mushroom or fungus"),
            .init(label: "A small mammal", aiText: "a small mammal"),
            .init(label: "A fish", aiText: "a fish or aquatic creature")
        ]
    ),
    GuidedQuestion(
        prompt: "Where exactly did you find it?",
        tags: [
            .init(label: "On wood", aiText: "resting on wood or bark"),
            .init(label: "Near water", aiText: "found near or in water"),
            .init(label: "Under a rock", aiText: "sheltering beneath a rock"),
            .init(label: "On a leaf", aiText: "perched on a leaf surface"),
            .init(label: "In soil", aiText: "found in or on bare soil"),
            .init(label: "High in tree", aiText: "observed high up in a tree canopy")
        ]
    ),
    GuidedQuestion(
        prompt: "How large was it?",
        tags: [
            .init(label: "Tiny (< 5mm)", aiText: "very small, under 5mm in length"),
            .init(label: "Coin-sized", aiText: "roughly coin-sized"),
            .init(label: "Palm-sized", aiText: "approximately palm-sized"),
            .init(label: "Larger than a hand", aiText: "larger than a human hand")
        ]
    ),
    GuidedQuestion(
        prompt: "What was it doing?",
        tags: [
            .init(label: "Motionless", aiText: "completely still when observed"),
            .init(label: "Fast moving", aiText: "moving quickly when disturbed"),
            .init(label: "Feeding", aiText: "actively feeding"),
            .init(label: "Burrowing", aiText: "burrowing into the substrate"),
            .init(label: "Making sounds", aiText: "producing audible sounds")
        ]
    ),
    GuidedQuestion(
        prompt: "Any striking colors or patterns?",
        tags: [
            .init(label: "Iridescent", aiText: "with iridescent, shifting coloring"),
            .init(label: "Camouflaged", aiText: "camouflaged to blend with surroundings"),
            .init(label: "Vivid solid color", aiText: "a single vivid, solid color"),
            .init(label: "Dark + markings", aiText: "dark-bodied with contrasting markings"),
            .init(label: "Striped or spotted", aiText: "with distinct stripes or spots")
        ]
    ),
    GuidedQuestion(
        prompt: "Any distinct features — wings, shell, legs?",
        tags: [
            .init(label: "Hard shell", aiText: "with a hard protective shell"),
            .init(label: "Wings", aiText: "with clearly visible wings"),
            .init(label: "Feathers", aiText: "covered in feathers"),
            .init(label: "Long antennae", aiText: "with notably long antennae"),
            .init(label: "Scaly skin", aiText: "with scaly or rough skin"),
            .init(label: "Many legs", aiText: "with many clearly visible legs")
        ]
    ),
    GuidedQuestion(
        prompt: "Describe its overall body shape.",
        tags: [
            .init(label: "Elongated", aiText: "with an elongated, slender body"),
            .init(label: "Round/oval", aiText: "with a round or oval body"),
            .init(label: "Flattened", aiText: "noticeably flat or disc-shaped"),
            .init(label: "Coiled", aiText: "coiled or curled when observed")
        ]
    ),
    GuidedQuestion(
        prompt: "Was it alone or with others?",
        tags: [
            .init(label: "Solitary", aiText: "observed alone with none nearby"),
            .init(label: "Small group", aiText: "part of a small cluster or pair"),
            .init(label: "Large colony", aiText: "part of a large colony or swarm")
        ]
    ),
    GuidedQuestion(
        prompt: "What was the environment like?",
        tags: [
            .init(label: "Sunny & dry", aiText: "in a sunny, dry environment"),
            .init(label: "Damp/after rain", aiText: "in a damp habitat after recent rain"),
            .init(label: "At night", aiText: "observed at night or in low light"),
            .init(label: "Dense forest", aiText: "within dense forest or woodland"),
            .init(label: "Open dry land", aiText: "in open, arid, or grassland habitat")
        ]
    )
]

// MARK: - Prompt Manager

@Observable
final class DescribePromptManager {
    var activeQuestionIndex: Int = 0
}

// MARK: - View

/// Full-screen text-first input field for Describe identification.
///
/// The view is intentionally decoupled from `InferenceEngine` and `CameraViewModel` —
/// it only produces an `ObservationContext` value and delivers it via `onSubmit`.
/// All network orchestration and multi-modal routing lives in `CameraViewModel.submitDescribe`.
///
/// Layout contract with `CameraRootView`:
/// - Fills the full page frame (same size as the camera and audio pages).
/// - The fixed `MediaModeToggle` overlay sits above this view in the Z-stack and
///   always remains interactive; this view must NOT place anything above the
///   `safeAreaInsets.top + 64` band.
struct DescribeInputView: View {
    var captureMode: CaptureMode

    @Binding var context: ObservationContext
    @FocusState private var isTextFieldFocused: Bool
    @Environment(SpeechManager.self) private var speechManager

    var promptManager: DescribePromptManager

    // MARK: - Dictation state

    @State private var dictationTask: Task<Void, Never>?

    // MARK: - Derived

    private var topSafeArea: CGFloat {
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 59
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color(UIColor.systemBackground)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Top spacer: device safe area + MediaModeToggle (16pt padding + ~44pt height) + 20pt gap.
                    Spacer().frame(height: topSafeArea + 60)

                    // MARK: Question Header
                    VStack(alignment: .leading, spacing: 0) {

                        // Navigation row: dots flush left (decorative only), buttons flush right.
                        HStack {
                            HStack(spacing: 5) {
                                ForEach(guidedQuestions.indices, id: \.self) { idx in
                                    Circle()
                                        .fill(idx == promptManager.activeQuestionIndex
                                              ? Color.primary
                                              : Color.primary.opacity(0.2))
                                        .frame(width: 6, height: 6)
                                        .animation(.easeInOut(duration: 0.3), value: promptManager.activeQuestionIndex)
                                }
                            }

                            Spacer()

                            HStack(spacing: 4) {
                                Button(action: previousQuestion) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .frame(width: 44, height: 44)
                                }
                                Button(action: advanceQuestion) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .frame(width: 44, height: 44)
                                }
                            }
                        }

                        // Heading text — full width, crossfades between questions.
                        // We use a single Text view with an .id modifier to force
                        // a transition when the active question changes, which is far
                        // more reliable than the prior ZStack opacity workaround.
                        Text(guidedQuestions[promptManager.activeQuestionIndex].prompt)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .id("prompt_\(promptManager.activeQuestionIndex)")
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.35), value: promptManager.activeQuestionIndex)
                            .frame(maxWidth: .infinity, minHeight: 35, alignment: .topLeading)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // MARK: Contextual Quick Tags
                    // Tags are scoped to the active question. Tapping inserts the optimized
                    // aiText fragment into freeText.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(guidedQuestions[promptManager.activeQuestionIndex].tags, id: \.self) { tag in
                                Button(action: {
                                    HapticManager.shared.triggerSelectionPulse()
                                    appendTag(tag)
                                }) {
                                    Text(tag.label)
                                        .foregroundStyle(.primary)
                                        .font(.subheadline)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .clipShape(Capsule())
                                }
                                .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 20)
                        .animation(.easeInOut(duration: 0.3), value: promptManager.activeQuestionIndex)
                    }
                    .padding(.bottom, 16)

                    // MARK: Text Area
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        isTextFieldFocused
                                            ? Color.primary.opacity(0.3)
                                            : Color.primary.opacity(0.12),
                                        lineWidth: 0.5
                                    )
                            )

                        TextField(
                            "e.g., A bright green beetle with gold stripes resting on an oak leaf...",
                            text: $context.freeText,
                            axis: .vertical
                        )
                        .lineLimit(5...10)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .focused($isTextFieldFocused)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minHeight: 160)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    Spacer() // Absorbs extra vertical space

                    // Bottom spacer: clears the global tab bar / scan toolbar
                    Spacer().frame(height: 250)
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: captureMode) { _, newMode in
                if newMode != .describe {
                    isTextFieldFocused = false
                    dictationTask?.cancel()
                    dictationTask = nil
                }
            }
        }
        }
    }

    // MARK: - Helpers

    private func advanceQuestion() {
        let next = (promptManager.activeQuestionIndex + 1) % guidedQuestions.count
        withAnimation(.easeInOut(duration: 0.4)) {
            promptManager.activeQuestionIndex = next
        }
    }

    private func previousQuestion() {
        let prev = (promptManager.activeQuestionIndex - 1 + guidedQuestions.count) % guidedQuestions.count
        withAnimation(.easeInOut(duration: 0.4)) {
            promptManager.activeQuestionIndex = prev
        }
    }

    /// Inserts the tag's optimized AI text fragment into freeText, maintaining
    /// natural sentence flow.
    private func appendTag(_ tag: GuidedQuestion.Tag) {
        let insertion = tag.aiText
        let trimmed = context.freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            context.freeText = insertion.prefix(1).uppercased() + insertion.dropFirst()
        } else {
            let endsWithSentence = trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?")
            if endsWithSentence {
                let capped = insertion.prefix(1).uppercased() + insertion.dropFirst()
                context.freeText = trimmed + " " + capped + "."
            } else {
                context.freeText = trimmed + ", " + insertion
            }
        }
    }
}

// MARK: - Describe Questions Table of Contents
struct DescribeQuestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var promptManager: DescribePromptManager
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(guidedQuestions.enumerated()), id: \.offset) { idx, question in
                    Button(action: {
                        HapticManager.shared.triggerSelectionPulse()
                        withAnimation(.easeInOut(duration: 0.4)) {
                            promptManager.activeQuestionIndex = idx
                        }
                        dismiss()
                    }) {
                        HStack {
                            Text(question.prompt)
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if idx == promptManager.activeQuestionIndex {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.primary)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Prompts")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                   Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
