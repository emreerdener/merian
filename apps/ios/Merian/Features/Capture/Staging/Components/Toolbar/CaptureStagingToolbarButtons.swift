import SwiftUI

/// Populated evidence has an opaque backing; empty slots reveal the tray beneath.
struct CaptureStagingNodeSurface: ViewModifier {
    var isEmpty = false

    func body(content: Content) -> some View {
        content
            .background(
                Color(uiColor: .systemBackground)
                    .opacity(isEmpty ? 0 : 1),
                in: Circle()
            )
            .overlay {
                Circle().strokeBorder(
                    .primary.opacity(0.5),
                    style: StrokeStyle(lineWidth: isEmpty ? 1.5 : 1, dash: isEmpty ? [4] : [])
                )
            }
            .contentShape(Circle())
    }
}

struct CaptureStagingCancelButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(discardColor)
                .frame(width: 48, height: 48)
                .modifier(CaptureTrayGlass(isCircular: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discard scan")
    }

    private var discardColor: Color {
        colorScheme == .dark
            ? Color(red: 1, green: 0.30, blue: 0.32)
            : Color(red: 0.75, green: 0.08, blue: 0.12)
    }
}

/// Native glass honors the same thermal/Expedition policy as camera effects.
struct CaptureTrayGlass: ViewModifier {
    var isCircular = false
    var isExpanded = false
    @Environment(HardwareOrchestrator.self) private var hardware
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: isExpanded ? 32 : 1000, style: .continuous)
        if !hardware.isGlassmorphismEnabled || reduceTransparency {
            content.background(Color(UIColor.secondarySystemBackground), in: shape)
        } else if #available(iOS 26.0, *) {
            if isCircular {
                content.glassEffect(.regular.interactive(), in: Circle())
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

struct CaptureStagingSubmitButton: View {
    let title: String
    let isDisabled: Bool
    let onSubmit: () -> Void

    var body: some View {
        Button(action: onSubmit) {
            Image(systemName: "arrow.up")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(isDisabled ? Color.primary.opacity(0.15) : Color.accentColor)
                .foregroundStyle(isDisabled ? Color.secondary : .white)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(
                        isDisabled ? .clear : Color.accentColor.opacity(0.4), lineWidth: 1.5
                    )
                )
                .shadow(
                    color: isDisabled ? .clear : Color.accentColor.opacity(0.25),
                    radius: 10, x: 0, y: 4
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(title == "Analyze" ? "Submit scan for reanalysis" : "Submit scan for identification"))
        .accessibilityShowsLargeContentViewer {
            Label(title, systemImage: "arrow.up")
        }
        .disabled(isDisabled)
        .animation(.easeInOut(duration: 0.2), value: isDisabled)
    }
}
