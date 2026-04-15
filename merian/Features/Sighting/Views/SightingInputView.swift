import SwiftUI

/// Full-screen chip-based input form for the Sighting identification mode.
///
/// The view is intentionally decoupled from `InferenceEngine` and `CameraViewModel` —
/// it only produces an `ObservationContext` value and delivers it via `onSubmit`.
/// All network orchestration and multi-modal routing lives in `CameraViewModel.submitSighting`.
///
/// Layout contract with `CameraRootView`:
/// - Fills the full page frame (same size as the camera and audio pages).
/// - The fixed `MediaModeToggle` overlay sits above this view in the Z-stack and
///   always remains interactive; this view must NOT place anything above the
///   `safeAreaInsets.top + 64` band.
struct SightingInputView: View {
    /// True when images (or audio) are already staged — switches the button label to
    /// "Add to Scan & Identify" so the user knows their description will be combined.
    var hasStaged: Bool = false
    let onSubmit: (ObservationContext) -> Void

    @State private var context = ObservationContext()
    @State private var showDetails: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    private let maxFreeTextLength = 150

    // MARK: - Body

    var body: some View {
        // GeometryReader with .ignoresSafeArea() expands to the true screen edges so
        // geo.safeAreaInsets.top always returns the real device inset (Dynamic Island,
        // notch, or plain status bar) regardless of what ancestor views have consumed.
        // The horizontal pager zeroes out safe area propagation for its child pages,
        // so this view must measure the inset independently.
        GeometryReader { geo in
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // Top spacer: device safe area + MediaModeToggle (16pt padding + ~44pt height) + 20pt gap.
                    Spacer().frame(height: geo.safeAreaInsets.top + 80)

                    // MARK: Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Describe what you saw")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)

                        Text("The more detail you add, the better the identification.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    // MARK: Section 1 — Organism Class (required)
                    SectionLabel(title: "What did you see?", isRequired: true)
                    OrganismClassGrid(selection: $context.organismClass)
                        .padding(.bottom, 28)

                    // MARK: Section 2 — Colors
                    SectionLabel(title: "Colors")
                    ColorSwatchRow(selection: $context.colors)
                        .padding(.bottom, 28)

                    // MARK: Section 3 — Size
                    SectionLabel(title: "Size")
                    SizeSegmentedPicker(selection: $context.size)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    // MARK: Section 4 — Where / Habitat
                    SectionLabel(title: "Where was it?")
                    ChipGrid(
                        items: ObservationHabitat.allCases,
                        selection: $context.habitat,
                        label: { $0.displayName },
                        icon: { $0.systemImage }
                    )
                    .padding(.bottom, 28)

                    // MARK: Section 5 — Behavior
                    SectionLabel(title: "What was it doing?")
                    ChipGrid(
                        items: ObservationBehavior.allCases,
                        selection: $context.behaviors,
                        label: { $0.displayName },
                        icon: { $0.systemImage }
                    )
                    .padding(.bottom, 28)

                    // MARK: Section 6 — Details (expandable)
                    ExpandableSection(isExpanded: $showDetails, label: "More details") {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(title: "Markings")
                            ChipGrid(
                                items: ObservationMarking.allCases,
                                selection: $context.markings,
                                label: { $0.displayName },
                                icon: nil
                            )
                            .padding(.bottom, 24)

                            SectionLabel(title: "Texture")
                            SingleSelectChipRow(
                                items: ObservationTexture.allCases,
                                selection: $context.texture,
                                label: { $0.displayName }
                            )
                            .padding(.bottom, 24)
                        }
                    }
                    .padding(.bottom, 28)

                    // MARK: Section 7 — Free-text notes
                    SectionLabel(title: "Any other notes?")
                    FreeTextEditor(text: $context.freeText, maxLength: maxFreeTextLength, isFocused: $isTextFieldFocused)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)

                    // Bottom spacer: clears the fixed identify button + bottom safe area
                    Spacer().frame(height: 120)
                }
            }
            .scrollDismissesKeyboard(.interactively)

            // MARK: Fixed Bottom — Identify Button
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .allowsHitTesting(false)

                Button(action: {
                    isTextFieldFocused = false
                    onSubmit(context)
                    context = ObservationContext()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: hasStaged ? "plus.circle.fill" : "eye.fill")
                        Text(hasStaged ? "Add to Scan & Identify" : "Identify Sighting")
                            .fontWeight(.semibold)
                    }
                    .font(.body)
                    .foregroundStyle(context.organismClass == nil ? .white.opacity(0.35) : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(context.organismClass == nil ? Color.white.opacity(0.12) : Color.white)
                    )
                    .padding(.horizontal, 20)
                }
                .disabled(context.organismClass == nil)
                .animation(.easeInOut(duration: 0.2), value: context.organismClass == nil)
                .animation(.easeInOut(duration: 0.2), value: hasStaged)
                .padding(.bottom, 24)
                .background(Color.black)
            }
        }
        .environment(\.colorScheme, .dark)
        } // GeometryReader
        .ignoresSafeArea()
    }
}
