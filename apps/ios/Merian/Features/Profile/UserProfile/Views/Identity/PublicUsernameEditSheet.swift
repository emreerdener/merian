import SwiftUI
import UIKit

struct PublicUsernameEditSheet: View {
    let viewModel: ProfileViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var isSaving = false
    @State private var validationState: UsernameValidationState = .idle
    @FocusState private var isUsernameFocused: Bool

    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.publicUsername ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(.headline)

                    HStack(spacing: 6) {
                        Text("@")
                            .font(.body.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("username", text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                            .submitLabel(.done)
                            .focused($isUsernameFocused)
                            .disabled(isSaving)
                    }
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

                        Text(isSaving ? "Saving" : "Save username")
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
                viewModel.usernameUpdateErrorMessage = nil
                isUsernameFocused = true
            }
            .onChange(of: draft) {
                viewModel.usernameUpdateErrorMessage = nil
            }
            .task(id: normalizedDraft) {
                await validateUsername()
            }
        }
    }

    @ViewBuilder
    private var validationMessage: some View {
        if let message = viewModel.usernameUpdateErrorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        } else {
            switch validationState {
            case .idle:
                Text("Use 3-24 letters, numbers, or underscores.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Checking availability")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .available:
                Text("Username is available.")
                    .font(.footnote)
                    .foregroundStyle(.green)
            case .current:
                Text("This is your current username.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .invalid(let message),
                 .unavailable(let message),
                 .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var normalizedDraft: String {
        draft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"^@+"#,
                with: "",
                options: .regularExpression
            )
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "_",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"_+"#,
                with: "_",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private var canSave: Bool {
        guard !isSaving, normalizedDraft != viewModel.publicUsername else {
            return false
        }
        return validationState == .available
    }

    private var inputBorderColor: Color {
        switch validationState {
        case .invalid, .unavailable, .failed:
            return .red.opacity(0.45)
        case .available:
            return .green.opacity(0.45)
        case .idle, .checking, .current:
            return Color.primary.opacity(0.08)
        }
    }

    private func validateUsername() async {
        viewModel.usernameUpdateErrorMessage = nil

        let username = normalizedDraft
        guard !username.isEmpty else {
            validationState = .idle
            return
        }

        if let validationError = Self.validationError(for: username) {
            validationState = .invalid(validationError)
            return
        }

        if username == viewModel.publicUsername {
            validationState = .current
            return
        }

        validationState = .checking
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }

        do {
            let response = try await viewModel
                .checkPublicUsernameAvailability(username)
            guard !Task.isCancelled,
                  response.username == normalizedDraft else { return }
            if response.available {
                validationState = .available
            } else {
                validationState = .unavailable(
                    response.error ?? "That username is already taken."
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
            validationState = .failed("Couldn't check availability. Try again.")
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        let didSave = await viewModel.updatePublicUsername(normalizedDraft)
        if didSave {
            dismiss()
        }
    }

    static func validationError(for username: String) -> String? {
        if username.count < 3 {
            return "Username must be at least 3 characters."
        }
        if username.count > 24 {
            return "Username must be 24 characters or fewer."
        }
        if username.range(of: #"^[a-z]"#, options: .regularExpression) == nil {
            return "Username must start with a letter."
        }
        if username.range(of: #"[a-z0-9]$"#, options: .regularExpression) == nil {
            return "Username must end with a letter or number."
        }
        if username.range(
            of: #"^[a-z0-9_]+$"#,
            options: .regularExpression
        ) == nil {
            return "Username can only use letters, numbers, and underscores."
        }
        if username.contains("__") {
            return "Username cannot use repeated underscores."
        }
        if isReservedUsername(username) {
            return "That username is reserved."
        }
        return nil
    }

    private static func isReservedUsername(_ username: String) -> Bool {
        if reservedExactUsernames.contains(username)
            || reservedBrandUsernames.contains(username)
            || reservedRoleUsernames.contains(username) {
            return true
        }

        return reservedBrandUsernames.contains { brand in
            reservedRoleUsernames.contains { role in
                username == "\(brand)_\(role)" || username == "\(role)_\(brand)"
            }
        }
    }

    private static let reservedExactUsernames: Set<String> = [
        "null",
        "undefined"
    ]

    private static let reservedBrandUsernames: Set<String> = [
        "explore",
        "merian",
        "naturebook",
        "naturebookearth"
    ]

    private static let reservedRoleUsernames: Set<String> = [
        "abuse",
        "account",
        "accounts",
        "admin",
        "administrator",
        "api",
        "auth",
        "billing",
        "bot",
        "contact",
        "customer_service",
        "customer_support",
        "developer",
        "developers",
        "help",
        "legal",
        "moderation",
        "moderator",
        "notifications",
        "official",
        "press",
        "privacy",
        "root",
        "safety",
        "security",
        "staff",
        "status",
        "support",
        "system",
        "team",
        "trust",
        "verified",
        "verify"
    ]
}

private enum UsernameValidationState: Equatable {
    case idle
    case checking
    case available
    case current
    case invalid(String)
    case unavailable(String)
    case failed(String)
}
