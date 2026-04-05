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
        ZStack(alignment: .topTrailing) {
            content()
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 30, x: 0, y: 15)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color(UIColor.separator), lineWidth: 0.5)
                )

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
                .padding([.top, .trailing], 16)
            }
        }
        .padding(.horizontal, 16)
    }
}
