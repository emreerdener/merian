import SwiftUI

// MARK: - Action Bar
struct CandidateActionBar: View {
    let onReject: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            CandidateActionButton(label: "Reject", color: .red, action: onReject)
            CandidateActionButton(label: "Confirm", color: .green, action: onConfirm)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 12)
        .padding(.horizontal, 20)
    }
}

// MARK: - Action Button
struct CandidateActionButton: View {
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}
