import SwiftUI

/// A reusable floating banner scaffold with glassmorphic card styling and an optional dismiss button.
///
/// Callers are responsible for positioning (e.g. `.overlay(alignment: .bottom)`) and
/// defining the entry/exit transition at the call site. The dismiss button is rendered
/// as a floating X pill at the top-trailing corner of the card.
///
/// Example:
/// ```swift
/// if showToast {
///     ToastBanner(onDismiss: { showToast = false }) {
///         MyContent()
///     }
///     .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
///     .padding(.bottom, 60)
///     .transition(.move(edge: .bottom).combined(with: .opacity))
/// }
/// ```
struct ToastBanner<Content: View>: View {
    var onDismiss: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            content()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(Color(UIColor.separator), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 16)
        .padding(.leading, 20)
        .padding(.trailing, onDismiss != nil ? 16 : 20)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color(UIColor.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
}
