import SwiftUI

struct InsightChatNotesDraftSheet: View {
    @State private var draftText: String
    @State private var confirmationToast: ToastPayload?
    @State private var isCompletingAppend = false
    let onCancel: () -> Void
    let onAppend: (String) -> Void

    init(draftText: String, onCancel: @escaping () -> Void, onAppend: @escaping (String) -> Void) {
        _draftText = State(initialValue: draftText)
        self.onCancel = onCancel
        self.onAppend = onAppend
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $draftText)
                .padding()
                .navigationTitle("Review note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onCancel()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .accessibilityLabel("Close note review")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        appendAndConfirm()
                    } label: {
                        Label("Add to field notes", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCompletingAppend)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.bar)
                }
        }
        .overlay(alignment: .bottom) {
            if let confirmationToast {
                ToastPayloadBanner(payload: confirmationToast, onDismiss: nil)
                .padding(.bottom, 104)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .animation(
            .spring(response: 0.35, dampingFraction: 0.85),
            value: confirmationToast?.id
        )
        .task(id: confirmationToast?.id) {
            guard let confirmationToast else { return }
            do {
                try await Task.sleep(for: .milliseconds(1_200))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  isCompletingAppend,
                  self.confirmationToast?.id == confirmationToast.id else {
                return
            }
            onCancel()
        }
    }

    private func appendAndConfirm() {
        guard !isCompletingAppend else { return }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isCompletingAppend = true
        onAppend(draftText)
        confirmationToast = .success("Added to field notes")
    }
}
