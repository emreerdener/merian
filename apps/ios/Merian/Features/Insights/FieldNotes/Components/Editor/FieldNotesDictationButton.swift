import SwiftUI

struct FieldNotesDictationButton: View {
    let isDictating: Bool
    let isStarting: Bool
    let isSaving: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 10) {
                    Image(systemName: isDictating ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 18)

                    Text(
                        isDictating
                            ? "Stop dictation"
                            : "Dictate field notes"
                    )
                    .font(.headline)
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(isDictating ? .white : .primary)
                        .opacity(isStarting ? 1 : 0)
                        .accessibilityHidden(!isStarting)
                }
                .padding(.trailing, 18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(isDictating ? .white : .primary)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isDictating
                            ? Color.red
                            : Color.primary.opacity(0.08)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        Color.primary.opacity(isDictating ? 0 : 0.1),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isStarting || isSaving)
        .animation(.easeInOut(duration: 0.2), value: isDictating)
    }
}
