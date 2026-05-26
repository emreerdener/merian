import SwiftUI

/// Abstracted Profile identity component natively interpreting both Ghost mode states
/// and dynamically rendering high-fidelity Auth provider payloads seamlessly.
struct UserProfile: View {
    @Environment(ProfileViewModel.self) private var profileViewModel
    @State private var isShowingUsernameEditor = false
    var totalScans: Int = 0
    var completedAchievements: Int = 0
    
    var body: some View {
        VStack {
            if profileViewModel.isGuestUser {
                // Ghost Mode: Sign In Flow
                VStack(spacing: 16) {
                    usernameSummaryRow

                    Button(action: {
                        Task {
                            await profileViewModel.signInWithApple()
                        }
                    }) {
                        HStack {
                            Image(systemName: "applelogo")
                            Text("Sign in with Apple")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary)
                        .foregroundColor(Color(UIColor.systemBackground))
                        .clipShape(Capsule())
                    }
                    
                    Button(action: {
                        Task {
                            await profileViewModel.signInWithGoogle()
                        }
                    }) {
                        HStack {
                            Image("google")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                            Text("Sign in with Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                    }
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                VStack(spacing: 12) {
                    // Authenticated User Profile Card
                    HStack(spacing: 12) {
                        if let avatarURL = profileViewModel.userAvatarURL {
                            AsyncImage(url: avatarURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .frame(width: 48, height: 48)
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(profileViewModel.userName ?? profileViewModel.publicAuthorName ?? "Explorer")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text(profileViewModel.publicUsernameDisplayName ?? "Loading username")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        // Uses Apple's native `Menu` popover rendering to dynamically bind
                        // a systemic "liquid glass" context menu perfectly blurring behind the options.
                        Menu {
                            Button {
                                isShowingUsernameEditor = true
                            } label: {
                                Label("Edit username", systemImage: "at")
                            }

                            Button(role: .destructive) {
                                Task {
                                    // Forces a clean physical JWT removal across the device securely
                                    // instantly rehydrating back into a zero-bound Ghost mode state.
                                    await profileViewModel.signOut()
                                }
                            } label: {
                                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                                .frame(width: 36, height: 36)
                                .background(Color.secondary.opacity(0.15))
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }

                    Divider()
                    summaryCountsRow
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
            }
        }
        .task(id: profileViewModel.currentUserId) {
            await profileViewModel.fetchPublicIdentity()
            await profileViewModel.fetchSocialStats()
        }
        .sheet(isPresented: $isShowingUsernameEditor) {
            PublicUsernameEditSheet(viewModel: profileViewModel)
        }
    }

    private var usernameSummaryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Explorer")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(profileViewModel.publicUsernameDisplayName ?? "Loading username")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                isShowingUsernameEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.secondary.opacity(0.15))
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit username")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private var summaryCountsRow: some View {
        HStack(spacing: 0) {
            summaryCountView(value: compactValue(totalScans), label: "Scans")
                .frame(maxWidth: .infinity)

            summaryCountView(value: compactValue(completedAchievements), label: "Achievements")
                .frame(maxWidth: .infinity)

            if let socialStats = profileViewModel.socialStats {
                summaryCountView(value: compactValue(socialStats.followerCount), label: "Followers")
                    .frame(maxWidth: .infinity)
                summaryCountView(value: compactValue(socialStats.followingCount), label: "Following")
                    .frame(maxWidth: .infinity)
            } else if profileViewModel.isLoadingSocialStats {
                summaryCountPlaceholder(label: "Followers")
                    .frame(maxWidth: .infinity)
                summaryCountPlaceholder(label: "Following")
                    .frame(maxWidth: .infinity)
            } else {
                summaryCountView(value: "--", label: "Followers")
                    .frame(maxWidth: .infinity)
                summaryCountView(value: "--", label: "Following")
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func summaryCountView(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
    }

    private func summaryCountPlaceholder(label: String) -> some View {
        VStack(spacing: 2) {
            Text("000")
                .font(.headline.weight(.bold))
                .foregroundStyle(.secondary)
                .redacted(reason: .placeholder)
                .accessibilityLabel("Loading \(label)")

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
    }

    private func compactValue(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}

private struct PublicUsernameEditSheet: View {
    let viewModel: ProfileViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var isSaving = false

    init(viewModel: ProfileViewModel) {
        self.viewModel = viewModel
        _draft = State(initialValue: viewModel.publicUsernameDisplayName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    if let preview = previewUsername {
                        Text(preview)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = viewModel.usernameUpdateErrorMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Username")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.usernameUpdateErrorMessage = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || normalizedDraft.isEmpty)
                }
            }
        }
    }

    private var normalizedDraft: String {
        draft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^@+"#, with: "", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .replacingOccurrences(of: #"_+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private var previewUsername: String? {
        guard !normalizedDraft.isEmpty else { return nil }
        return "@\(normalizedDraft)"
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        let didSave = await viewModel.updatePublicUsername(draft)
        if didSave {
            dismiss()
        }
    }
}
