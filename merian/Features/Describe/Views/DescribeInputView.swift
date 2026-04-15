import SwiftUI

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
    /// True when images (or audio) are already staged — switches the button label to
    /// "Add to Scan & Identify" so the user knows their description will be combined.
    var hasStaged: Bool = false
    let onSubmit: (ObservationContext) -> Void

    @State private var context = ObservationContext()
    @FocusState private var isTextFieldFocused: Bool
    
    // Auto-rotating prompts
    private let prompts = [
        "Describe what you saw...",
        "What color was it?",
        "How large was it?",
        "Where did you see it?",
        "Any unique markings or behaviors?"
    ]
    @State private var promptIndex = 0
    let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    private var topSafeArea: CGFloat {
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 59
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Top spacer: device safe area + MediaModeToggle (16pt padding + ~44pt height) + 20pt gap.
                    Spacer().frame(height: topSafeArea + 100)

                    // MARK: Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Describe what you saw")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Text("We'll extract the characteristics to identify it.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    // MARK: Text Area
                    ZStack(alignment: .topLeading) {
                        // Background
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        isTextFieldFocused ? Color.white.opacity(0.3) : Color.white.opacity(0.12),
                                        lineWidth: 0.5
                                    )
                            )

                        // Rotating placeholder
                        if context.freeText.isEmpty {
                            Text(prompts[promptIndex])
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.3))
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                                .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                                .id("prompt-\(promptIndex)") // Force transition
                        }

                        TextEditor(text: $context.freeText)
                            .font(.body)
                            .foregroundStyle(.white)
                            .focused($isTextFieldFocused)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .onReceive(timer) { _ in
                        // Only rotate if empty so we don't execute animations/evaluations while they type
                        if context.freeText.isEmpty {
                            withAnimation {
                                promptIndex = (promptIndex + 1) % prompts.count
                            }
                        }
                    }

                    // MARK: Identify Button (Scrollable)
                    Button(action: {
                        guard !context.isEmpty else { return }
                        isTextFieldFocused = false
                        onSubmit(context)
                        // Observation context is securely retained locally instead of rapidly wiped
                        // so users can jump back and edit their description seamlessly.
                    }) {
                        HStack(spacing: 8) {
                            Text(hasStaged ? "Add to scan & identify" : "Identify describe")
                                .fontWeight(.semibold)
                        }
                        .font(.body)
                        .foregroundStyle(context.isEmpty ? .white.opacity(0.35) : .black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(context.isEmpty ? Color.white.opacity(0.12) : Color.white)
                        )
                        .padding(.horizontal, 20)
                    }
                    .animation(.easeInOut(duration: 0.2), value: context.isEmpty)
                    .animation(.easeInOut(duration: 0.2), value: hasStaged)

                    // Bottom spacer: clears the global tab bar / scan toolbar
                    Spacer().frame(height: 160)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}
