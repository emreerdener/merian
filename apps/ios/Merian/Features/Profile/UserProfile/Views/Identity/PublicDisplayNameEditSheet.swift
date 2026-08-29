import SwiftUI
import UIKit

struct PublicDisplayNameEditSheet: View {
    let viewModel: ProfileViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        let initialName: String
        if viewModel.publicIdentitySource == "display_name",
           let publicAuthorName = viewModel.publicAuthorName,
           !publicAuthorName.isEmpty {
            initialName = publicAuthorName
        } else if !viewModel.isGuestUser,
                  let loggedInName = viewModel.userName,
                  !loggedInName.isEmpty {
            initialName = loggedInName
        } else {
            initialName = ""
        }
        _draft = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.headline)

                    TextField("Explorer", text: $draft)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .disabled(isSaving)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(UIColor.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(inputBorderColor, lineWidth: 1)
                        )

                    validationMessage
                        .frame(minHeight: 20, alignment: .leading)
                }

                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(Color(UIColor.systemBackground))
                        }

                        Text(isSaving ? "Saving" : "Save name")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        canSave ? Color.primary : Color.secondary.opacity(0.18)
                    )
                    .foregroundStyle(
                        canSave ? Color(UIColor.systemBackground) : .secondary
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)

                Spacer(minLength: 0)
            }
            .padding(24)
            .onAppear {
                viewModel.displayNameUpdateErrorMessage = nil
                isNameFocused = true
            }
            .onChange(of: draft) {
                viewModel.displayNameUpdateErrorMessage = nil
            }
        }
    }

    @ViewBuilder
    private var validationMessage: some View {
        if let message = viewModel.displayNameUpdateErrorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        } else if let message = validationError {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            Text("Optional · up to 40 characters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var normalizedDraft: String {
        draft
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard !isSaving, validationError == nil else { return false }
        return normalizedDraft != currentCustomDisplayName
    }

    private var currentCustomDisplayName: String {
        guard viewModel.publicIdentitySource == "display_name" else { return "" }
        return viewModel.publicAuthorName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var inputBorderColor: Color {
        validationError == nil ? Color.primary.opacity(0.08) : .red.opacity(0.45)
    }

    private var validationError: String? {
        if normalizedDraft.count > 40 {
            return "Name must be 40 characters or fewer."
        }
        if normalizedDraft.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        }) {
            return "Name cannot include control characters."
        }
        return nil
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        let didSave = await viewModel.updatePublicDisplayName(normalizedDraft)
        if didSave {
            dismiss()
        }
    }
}
