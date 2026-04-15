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

// MARK: - Section Label

private struct SectionLabel: View {
    let title: String
    var isRequired: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.7))
            if isRequired {
                Text("required")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

// MARK: - Organism Class Grid

private struct OrganismClassGrid: View {
    @Binding var selection: OrganismClass?

    private let columns = [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(OrganismClass.allCases, id: \.self) { cls in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = selection == cls ? nil : cls
                    }
                    HapticManager.shared.triggerFocusSnap()
                }) {
                    VStack(spacing: 6) {
                        Image(systemName: cls.systemImage)
                            .font(.system(size: 22))
                        Text(cls.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == cls ? .black : .white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selection == cls ? Color.white : Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                selection == cls ? Color.clear : Color.white.opacity(0.12),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Color Swatch Row

private struct ColorSwatchRow: View {
    @Binding var selection: Set<ObservationColor>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ObservationColor.allCases, id: \.self) { color in
                    let rgb = color.approximateColor
                    let swatchColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
                    let isSelected = selection.contains(color)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isSelected { selection.remove(color) } else { selection.insert(color) }
                        }
                        HapticManager.shared.triggerFocusSnap()
                    }) {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(swatchColor)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                isSelected ? Color.white : Color.white.opacity(0.2),
                                                lineWidth: isSelected ? 2 : 0.5
                                            )
                                    )

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(
                                            // Dark check on light swatches, white on dark
                                            (rgb.r + rgb.g + rgb.b) / 3 > 0.6 ? Color.black : Color.white
                                        )
                                }
                            }
                            Text(color.displayName)
                                .font(.caption2)
                                .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Size Segmented Picker

private struct SizeSegmentedPicker: View {
    @Binding var selection: ObservationSize?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ObservationSize.allCases, id: \.self) { size in
                    let isSelected = selection == size
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection = isSelected ? nil : size
                        }
                        HapticManager.shared.triggerFocusSnap()
                    }) {
                        Text(size.shortLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if let s = selection {
                Text(s.displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

// MARK: - Generic Multi-Select Chip Grid

private struct ChipGrid<T: Hashable & CaseIterable>: View {
    let items: [T]
    @Binding var selection: Set<T>
    let label: (T) -> String
    let icon: ((T) -> String)?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isSelected = selection.contains(item)
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isSelected { selection.remove(item) } else { selection.insert(item) }
                    }
                    HapticManager.shared.triggerFocusSnap()
                }) {
                    HStack(spacing: 5) {
                        if let iconFn = icon {
                            Image(systemName: iconFn(item))
                                .font(.caption)
                        }
                        Text(label(item))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected ? Color.clear : Color.white.opacity(0.15),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .scaleEffect(isSelected ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.12), value: isSelected)
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Single-Select Chip Row (for Texture)

private struct SingleSelectChipRow<T: Hashable & CaseIterable>: View {
    let items: [T]
    @Binding var selection: T?
    let label: (T) -> String

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isSelected = selection == item
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = isSelected ? nil : item
                    }
                    HapticManager.shared.triggerFocusSnap()
                }) {
                    Text(label(item))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    isSelected ? Color.clear : Color.white.opacity(0.15),
                                    lineWidth: 0.5
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Expandable Section

private struct ExpandableSection<Content: View>: View {
    @Binding var isExpanded: Bool
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.triggerSheetSpring()
            }) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Free Text Editor

private struct FreeTextEditor: View {
    @Binding var text: String
    let maxLength: Int
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isFocused.wrappedValue ? Color.white.opacity(0.3) : Color.white.opacity(0.12),
                                lineWidth: 0.5
                            )
                    )

                if text.isEmpty {
                    Text("e.g. had distinctive orange spots on its wings…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: Binding(
                    get: { text },
                    set: { text = String($0.prefix(maxLength)) }
                ))
                .font(.subheadline)
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(minHeight: 90, maxHeight: 140)
                .focused(isFocused)
            }

            Text("\(text.count)/\(maxLength)")
                .font(.caption2)
                .foregroundStyle(text.count >= maxLength ? .orange : .white.opacity(0.3))
                .animation(.easeInOut(duration: 0.15), value: text.count >= maxLength)
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused.wrappedValue)
    }
}

// MARK: - Flow Layout
// A left-to-right wrapping layout for chips — wraps to the next row when
// a chip would overflow the available width.

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(for: subviews, availableWidth: proposal.width ?? 0)
        let height = rows.reduce(0.0) { $0 + $1.maxHeight } + max(0, CGFloat(rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(for: subviews, availableWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.sizeThatFits(.unspecified)
                item.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.maxHeight + spacing
        }
    }

    private struct Row {
        var items: [LayoutSubview] = []
        var maxHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
    }

    private func computeRows(for subviews: Subviews, availableWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let widthNeeded = current.items.isEmpty ? size.width : size.width + spacing
            if !current.items.isEmpty && current.totalWidth + widthNeeded > availableWidth {
                rows.append(current)
                current = Row()
            }
            current.items.append(subview)
            current.totalWidth += widthNeeded
            current.maxHeight = max(current.maxHeight, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
