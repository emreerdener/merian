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
    var captureMode: CaptureMode
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

    private var topSafeArea: CGFloat {
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 59
    }

    @AppStorage("isMultiCaptureEnabled") private var isMultiCaptureEnabled: Bool = false
    @AppStorage("requiresScanConfirmation") private var requiresScanConfirmation: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(UIColor.systemBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Top spacer: device safe area + MediaModeToggle (16pt padding + ~44pt height) + 20pt gap.
                    Spacer().frame(height: topSafeArea + 100)

                    // MARK: Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prompts[promptIndex])
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .transition(.opacity.animation(.easeInOut(duration: 0.5)))
                            .id("prompt-\(promptIndex)")

                        Text("We'll extract the characteristics to identify it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    // MARK: Text Area
                    ZStack(alignment: .topLeading) {
                        // Background
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        isTextFieldFocused ? Color.primary.opacity(0.3) : Color.primary.opacity(0.12),
                                        lineWidth: 0.5
                                    )
                            )

                        // Static placeholder
                        if context.freeText.isEmpty {
                            Text("Describe what you saw...")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $context.freeText)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .focused($isTextFieldFocused)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .task {
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            // Only rotate if empty so we don't execute animations/evaluations while they type
                            if context.freeText.isEmpty && captureMode == .describe {
                                withAnimation {
                                    promptIndex = (promptIndex + 1) % prompts.count
                                }
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
                            Text((hasStaged || isMultiCaptureEnabled || requiresScanConfirmation) ? "Add description" : "Identify")
                                .fontWeight(.semibold)
                        }
                        .font(.body)
                        .foregroundStyle(Color(UIColor.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            Capsule()
                                .fill(Color.primary)
                        )
                        .padding(.horizontal, 20)
                    }
                    .animation(.easeInOut(duration: 0.2), value: hasStaged)

                    // Bottom spacer: clears the global tab bar / scan toolbar
                    Spacer().frame(height: 160)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: captureMode) { _, newMode in
                if newMode != .describe {
                    isTextFieldFocused = false
                }
            }
        }
    }
}
