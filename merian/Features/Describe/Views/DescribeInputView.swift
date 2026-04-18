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

    @Binding var context: ObservationContext
    @FocusState private var isTextFieldFocused: Bool
    
    // Curated, conversational prompts targeting Morphology, Ecology, and Behavior
    private let prompts = [
        "Any striking colors, patterns, or unusual textures?",
        "How large was it compared to an everyday object?",
        "Where exactly was it? (e.g., under a log, high in a tree)",
        "What was it doing? Was it moving or staying still?",
        "Did it have any distinct features like a unique shell or wings?",
        "Describe its overall shape or the vibe it gave off.",
        "Was it alone, or interacting with others in a group?",
        "What kind of environment or weather was it in?"
    ]
    
    private struct QuickTag: Hashable {
        let emoji: String
        let text: String
    }

    private let quickTags: [QuickTag] = [
        QuickTag(emoji: "🪵", text: "On wood"),
        QuickTag(emoji: "💧", text: "In water"),
        QuickTag(emoji: "🪨", text: "Under a rock"),
        QuickTag(emoji: "🌿", text: "On a leaf"),
        QuickTag(emoji: "🌙", text: "Nocturnal"),
        QuickTag(emoji: "💨", text: "Fast moving"),
        QuickTag(emoji: "🛑", text: "Completely still"),
        QuickTag(emoji: "🪲", text: "Hard shell"),
        QuickTag(emoji: "🪶", text: "Feathers")
    ]

    private var topSafeArea: CGFloat {
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 59
    }

    // MARK: - Body

    var body: some View {
        
        ZStack(alignment: .bottom) {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
                .onTapGesture {
                    isTextFieldFocused = false
                }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Top spacer: device safe area + MediaModeToggle (16pt padding + ~44pt height) + 20pt gap.
                    Spacer().frame(height: topSafeArea + 100)

                    // MARK: Header
                    VStack(alignment: .leading, spacing: 6) {
                        // Pacing slowed to 6.0 seconds to reduce reading anxiety
                        TimelineView(.periodic(from: .now, by: 6.0)) { contextView in
                            let rawIndex = Int(contextView.date.timeIntervalSince1970 / 6)
                            let activeIndex = rawIndex % prompts.count
                            
                            // Wrapping in ZStack with an explicit ID guarantees crossfade in SwiftUI over all OS versions
                            ZStack(alignment: .leading) {
                                Text(prompts[activeIndex])
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)
                                    .id("prompt-\(activeIndex)")
                                    .transition(.opacity.animation(.easeInOut(duration: 0.6)))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                                        // MARK: Quick Tags Pill Bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickTags, id: \.self) { tag in
                                Button(action: {
                                    appendTag(tag.text)
                                }) {
                                    HStack(spacing: 4) {
                                        Text(tag.emoji)
                                        Text(tag.text)
                                            .foregroundStyle(.primary)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 24)

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

                        TextField("e.g., A bright green beetle with gold stripes resting on an oak leaf...", text: $context.freeText, axis: .vertical)
                            .lineLimit(8...14)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .focused($isTextFieldFocused)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 48)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") {
                                        isTextFieldFocused = false
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    }
                                    .bold()
                                    .padding(.trailing, 8)
                                    .padding(.bottom, 6)
                                }
                            }
                            
                        // Inline Dictation Mic
                        Button(action: {
                            // TODO
                        }) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(UIColor.systemBackground))
                                .frame(width: 30, height: 30)
                                .background(Color.primary)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    


                    // Bottom spacer: clears the global tab bar / scan toolbar
                    Spacer().frame(height: 180)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isTextFieldFocused = false
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
    
    // MARK: - Helpers
    
    /// Appends the selected tag to the free text field intelligently.
    private func appendTag(_ textToAppend: String) {
        if context.freeText.isEmpty {
            context.freeText = textToAppend.capitalized
        } else {
            // Check if user already typed a trailing space to prevent double spacing
            let separator = context.freeText.hasSuffix(" ") ? "" : ", "
            context.freeText += "\(separator)\(textToAppend)"
        }
    }
}
