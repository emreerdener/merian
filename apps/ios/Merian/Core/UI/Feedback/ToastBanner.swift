import SwiftUI

private struct ToastReduceTransparencyOverrideKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private extension EnvironmentValues {
    var toastReduceTransparencyOverride: Bool? {
        get { self[ToastReduceTransparencyOverrideKey.self] }
        set { self[ToastReduceTransparencyOverrideKey.self] = newValue }
    }
}

enum ToastStackPresentation {
    /// Queue payloads stay data-only until they become active. Decorative
    /// backplates communicate depth without mounting additional card trees.
    static let maximumMountedPayloadCount = 1
    static let maximumVisibleBackingLayers = 2

    static func visibleBackingLayerCount(for pendingItemCount: Int) -> Int {
        min(max(pendingItemCount, 0), maximumVisibleBackingLayers)
    }

    static func horizontalScale(for layer: Int) -> CGFloat {
        layer == 1 ? 0.96 : 0.92
    }

    static func verticalOffset(for layer: Int) -> CGFloat {
        layer == 1 ? 8 : 14
    }

    static func opacity(for layer: Int) -> Double {
        layer == 1 ? 0.86 : 0.68
    }
}

struct ToastBannerForegroundTransform: Equatable {
    let offset: CGSize
    let scale: CGFloat
    let opacity: Double

    init(
        offset: CGSize = .zero,
        scale: CGFloat = 1,
        opacity: Double = 1
    ) {
        self.offset = offset
        self.scale = scale
        self.opacity = opacity
    }
}

/// Shared adaptive chrome for transient in-app feedback.
///
/// Toasts intentionally use the inverse of the surrounding appearance so they
/// remain distinct from sheets, cards, imagery, and other glass surfaces.
private struct AdaptiveToastSurfaceModifier<SurfaceShape: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.toastReduceTransparencyOverride) private var reduceTransparencyOverride

    let shape: SurfaceShape
    let pendingItemCount: Int
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let foregroundTransform: ToastBannerForegroundTransform

    func body(content: Content) -> some View {
        content
            .background {
                surfaceLayer
            }
            .shadow(
                color: .black.opacity(0.15),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .offset(
                x: foregroundTransform.offset.width,
                y: foregroundTransform.offset.height
            )
            .scaleEffect(foregroundTransform.scale)
            .opacity(foregroundTransform.opacity)
            // Keep backplates outside the active surface's render transform.
            // Offset and scale preserve the foreground's layout bounds, so this
            // outer background stays sized and anchored to the resting card.
            .background {
                backingLayers
            }
            .environment(\.colorScheme, inverseColorScheme)
            .animation(
                .spring(response: 0.36, dampingFraction: 0.86),
                value: visibleBackingLayerCount
            )
    }

    private var visibleBackingLayerCount: Int {
        ToastStackPresentation.visibleBackingLayerCount(for: pendingItemCount)
    }

    @ViewBuilder private var backingLayers: some View {
        if visibleBackingLayerCount > 0 {
            ZStack {
                ForEach((1...visibleBackingLayerCount).reversed(), id: \.self) { layer in
                    surfaceLayer
                        .scaleEffect(
                            x: ToastStackPresentation.horizontalScale(for: layer),
                            y: 1,
                            anchor: .center
                        )
                        .offset(y: ToastStackPresentation.verticalOffset(for: layer))
                        .opacity(ToastStackPresentation.opacity(for: layer))
                        .transition(.opacity.combined(with: .offset(y: -4)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .shadow(
                color: .black.opacity(0.15),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
        }
    }

    @ViewBuilder private var surfaceLayer: some View {
        if reduceTransparencyOverride ?? reduceTransparency {
            shape.fill(opaqueSurfaceColor)
                .overlay {
                    shape.strokeBorder(borderColor, lineWidth: 0.5)
                }
        } else {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.fill(tintColor)
                }
                .overlay {
                    shape.strokeBorder(borderColor, lineWidth: 0.5)
                }
        }
    }

    private var inverseColorScheme: ColorScheme {
        colorScheme == .light ? .dark : .light
    }

    private var tintColor: Color {
        colorScheme == .light
            ? .black.opacity(0.72)
            : .white.opacity(0.80)
    }

    private var opaqueSurfaceColor: Color {
        colorScheme == .light
            ? Color(white: 0.06)
            : Color(white: 0.96)
    }

    private var borderColor: Color {
        colorScheme == .light
            ? .white.opacity(0.18)
            : .black.opacity(0.14)
    }
}

extension View {
    func adaptiveToastSurface<SurfaceShape: InsettableShape>(
        in shape: SurfaceShape,
        pendingItemCount: Int = 0,
        shadowRadius: CGFloat = 30,
        shadowY: CGFloat = 15,
        foregroundTransform: ToastBannerForegroundTransform = .init()
    ) -> some View {
        modifier(AdaptiveToastSurfaceModifier(
            shape: shape,
            pendingItemCount: pendingItemCount,
            shadowRadius: shadowRadius,
            shadowY: shadowY,
            foregroundTransform: foregroundTransform
        ))
    }
}

/// A reusable floating banner scaffold with adaptive inverse-glass styling and an optional dismiss button.
///
/// Callers are responsible for positioning (e.g. `.overlay(alignment: .bottom)`) and
/// defining the entry/exit transition at the call site. The dismiss button is rendered
/// as a floating X pill at the top-trailing corner of the card.
///
/// Example:
/// ```swift
/// hostContent
///     .overlay(alignment: .bottom) {
///         if showToast {
///             ToastBanner(onDismiss: { showToast = false }) {
///                 MyContent()
///             }
///             .padding(.bottom, 60)
///             .transition(.move(edge: .bottom).combined(with: .opacity))
///         }
///     }
/// ```
struct ToastBanner<Content: View>: View {
    var onDismiss: (() -> Void)?
    var pendingItemCount = 0
    var foregroundTransform = ToastBannerForegroundTransform()
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            content()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .circularMaterialControl(
                            size: 24,
                            borderColor: Color(UIColor.separator)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 16)
        .padding(.leading, 20)
        .padding(.trailing, onDismiss != nil ? 16 : 20)
        .frame(maxWidth: 560, alignment: .leading)
        .adaptiveToastSurface(
            in: RoundedRectangle(cornerRadius: 32, style: .continuous),
            pendingItemCount: pendingItemCount,
            foregroundTransform: foregroundTransform
        )
        .padding(.horizontal, 16)
    }
}

struct ToastPayloadBanner: View {
    let payload: ToastPayload
    var onDismiss: (() -> Void)?
    var onAction: (() -> Void)?

    var body: some View {
        ToastBanner(onDismiss: onDismiss) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: payload.body == nil ? 0 : 3) {
                    Text(payload.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let body = payload.body {
                        Text(body)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let action = payload.action, let onAction {
                    Spacer(minLength: 0)

                    Button(action.title, action: onAction)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("ToastPayloadBanner_\(payload.severity.accessibilityIdentifier)")
    }

    private var iconName: String {
        switch payload.severity {
        case .information: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "exclamationmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch payload.severity {
        case .information: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

private extension ToastSeverity {
    var accessibilityIdentifier: String {
        switch self {
        case .information: "Information"
        case .success: "Success"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}

#if DEBUG
private struct ToastSurfacePreviewCanvas: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.cyan.opacity(0.7), .green.opacity(0.45), .orange.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ToastBanner(onDismiss: {}) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scan saved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("Your observation is ready in the Library.")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                ToastBanner(onDismiss: {}) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text("We couldn’t upload this scan. Please try again.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Button("Retry") {}
                            .font(.subheadline.weight(.bold))
                    }
                }

                MilestoneToastBanner(
                    item: .toastSurfacePreview,
                    pendingItemCount: 3,
                    clock: ContinuousMilestoneToastClock(),
                    onClaimPresentationEffects: { _, _ in false },
                    automaticDismissInterval: { _, _ in nil },
                    onDismiss: {}
                )
            }
        }
    }
}

private extension MilestoneToastItem {
    static let toastSurfacePreview = MilestoneToastItem(
        id: UUID(),
        payload: .fieldTrip(.preview),
        source: .preview
    )
}

#Preview("Adaptive toasts — Light") {
    ToastSurfacePreviewCanvas()
        .preferredColorScheme(.light)
}

#Preview("Adaptive toasts — Dark") {
    ToastSurfacePreviewCanvas()
        .preferredColorScheme(.dark)
}

#Preview("Adaptive toasts — Reduce Transparency") {
    ToastSurfacePreviewCanvas()
        .environment(\.toastReduceTransparencyOverride, true)
        .preferredColorScheme(.light)
}
#endif
