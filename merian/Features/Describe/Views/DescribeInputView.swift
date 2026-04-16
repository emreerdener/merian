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

    @Binding var context: ObservationContext
    @FocusState private var isTextFieldFocused: Bool
    
    // Auto-rotating prompts layer
    private let promptTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let prompts = [
        "What did you see?",
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

                        TextField("Enter description...", text: $context.freeText, axis: .vertical)
                            .lineLimit(8...14)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .focused($isTextFieldFocused)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .onReceive(promptTimer) { _ in
                        guard captureMode == .describe else { return }
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
