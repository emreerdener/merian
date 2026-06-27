import PhotosUI
import SwiftUI
import UIKit

/// Abstracted Profile identity component natively interpreting both Ghost mode states
/// and dynamically rendering high-fidelity Auth provider payloads seamlessly.
struct UserProfile: View {
    @Environment(ProfileViewModel.self) private var profileViewModel
    @State private var isShowingUsernameEditor = false
    @State private var isShowingDisplayNameEditor = false
    @State private var avatarImageToCrop: IdentifiableImage?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isShowingAvatarError = false
    var totalScans: Int = 0
    var completedAchievements: Int = 0
    
    var body: some View {
        VStack {
            if profileViewModel.isGuestUser {
                VStack(spacing: 24) {
                    profileCard
                    signInButtons
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                profileCard
            }
        }
        .task(id: profileViewModel.currentUserId) {
            await profileViewModel.fetchPublicIdentity()
            await profileViewModel.fetchSocialStats()
        }
        .sheet(isPresented: $isShowingUsernameEditor) {
            PublicUsernameEditSheet(viewModel: profileViewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(UIColor.systemGroupedBackground))
        }
        .sheet(isPresented: $isShowingDisplayNameEditor) {
            PublicDisplayNameEditSheet(viewModel: profileViewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(UIColor.systemGroupedBackground))
        }
        .fullScreenCover(item: $avatarImageToCrop) { item in
            ImageCropperView(
                image: item.image,
                onCrop: { croppedData, _, _, _ in
                    avatarImageToCrop = nil
                    uploadConfirmedAvatarCrop(croppedData)
                },
                onCancel: {
                    avatarImageToCrop = nil
                }
            )
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            handleAvatarSelection(newItem)
        }
        .alert("Profile picture update failed", isPresented: $isShowingAvatarError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(profileViewModel.avatarUpdateErrorMessage ?? "Merian could not update your profile picture.")
        }
    }

    private var profileCard: some View {
        VStack(spacing: 12) {
            identityHeader
            Divider()
            summaryCountsRow
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private var identityHeader: some View {
        HStack(spacing: 12) {
            avatarPicker

            VStack(alignment: .leading, spacing: 2) {
                Text(profileViewModel.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(profileViewModel.publicUsernameDisplayName ?? "Loading username")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            profileMenu
        }
    }

    private var profileMenu: some View {
        Menu {
            Button {
                isShowingDisplayNameEditor = true
            } label: {
                Label("Edit name", systemImage: "person.text.rectangle")
            }

            Button {
                isShowingUsernameEditor = true
            } label: {
                Label("Edit username", systemImage: "at")
            }

            if !profileViewModel.isGuestUser {
                Button(role: .destructive) {
                    Task {
                        await profileViewModel.signOut()
                    }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
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
        .accessibilityLabel("Profile options")
    }

    private var signInButtons: some View {
        VStack(spacing: 12) {
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
    }

    private var avatarPicker: some View {
        let isUpdatingAvatar = profileViewModel.isUpdatingAvatar

        return PhotosPicker(
            selection: $selectedAvatarItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            ZStack(alignment: .bottomTrailing) {
                avatarImage(size: 48)

                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.accentColor, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(Color(UIColor.secondarySystemGroupedBackground), lineWidth: 2)
                    )

                if isUpdatingAvatar {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 48, height: 48)
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingAvatar)
        .accessibilityLabel("Change profile picture")
    }

    @ViewBuilder
    private func avatarImage(size: CGFloat) -> some View {
        if let avatarURL = profileViewModel.userAvatarURL {
            AsyncImage(url: avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackAvatar(size: size)
                case .empty:
                    Color(uiColor: .tertiarySystemFill)
                @unknown default:
                    fallbackAvatar(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            fallbackAvatar(size: size)
        }
    }

    private func fallbackAvatar(size: CGFloat) -> some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }

    private func handleAvatarSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        selectedAvatarItem = nil

        Task {
            do {
                guard let wrapper = try await item.loadTransferable(type: ImageFileWrapper.self) else {
                    profileViewModel.avatarUpdateErrorMessage = "Merian could not load that image."
                    isShowingAvatarError = true
                    return
                }

                let fileURL = wrapper.url
                defer { try? FileManager.default.removeItem(at: fileURL) }

                guard let image = UIImage(contentsOfFile: fileURL.path) else {
                    profileViewModel.avatarUpdateErrorMessage = "Merian could not read that image."
                    isShowingAvatarError = true
                    return
                }

                avatarImageToCrop = IdentifiableImage(image: image)
            } catch {
                profileViewModel.avatarUpdateErrorMessage = error.localizedDescription
                isShowingAvatarError = true
            }
        }
    }

    private func uploadConfirmedAvatarCrop(_ croppedData: Data) {
        guard !croppedData.isEmpty else {
            profileViewModel.avatarUpdateErrorMessage = "Merian could not crop that image."
            isShowingAvatarError = true
            return
        }

        Task {
            do {
                let avatar = try await Task.detached(priority: .userInitiated) {
                    try ProfileAvatarImagePreparer.prepare(croppedData: croppedData)
                }.value

                let didUpdate = await profileViewModel.updatePublicAvatar(avatar)
                if !didUpdate {
                    isShowingAvatarError = true
                }
            } catch {
                profileViewModel.avatarUpdateErrorMessage = error.localizedDescription
                isShowingAvatarError = true
            }
        }
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

private struct PublicDisplayNameEditSheet: View {
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
                    .background(canSave ? Color.primary : Color.secondary.opacity(0.18))
                    .foregroundStyle(canSave ? Color(UIColor.systemBackground) : .secondary)
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
            Text("Use 1-40 characters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var normalizedDraft: String {
        draft
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard !isSaving, validationError == nil else { return false }
        return normalizedDraft != viewModel.publicAuthorName
    }

    private var inputBorderColor: Color {
        validationError == nil ? Color.primary.opacity(0.08) : .red.opacity(0.45)
    }

    private var validationError: String? {
        if normalizedDraft.isEmpty { return "Name cannot be empty." }
        if normalizedDraft.count > 40 { return "Name must be 40 characters or fewer." }
        if normalizedDraft.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
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

private struct PublicUsernameEditSheet: View {
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
                    .background(canSave ? Color.primary : Color.secondary.opacity(0.18))
                    .foregroundStyle(canSave ? Color(UIColor.systemBackground) : .secondary)
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
            case .invalid(let message), .unavailable(let message), .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
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

    private var canSave: Bool {
        guard !isSaving, normalizedDraft != viewModel.publicUsername else { return false }
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
            let response = try await viewModel.checkPublicUsernameAvailability(username)
            guard !Task.isCancelled, response.username == normalizedDraft else { return }
            if response.available {
                validationState = .available
            } else {
                validationState = .unavailable(response.error ?? "That username is already taken.")
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

    private static func validationError(for username: String) -> String? {
        if username.count < 3 { return "Username must be at least 3 characters." }
        if username.count > 24 { return "Username must be 24 characters or fewer." }
        if username.range(of: #"^[a-z]"#, options: .regularExpression) == nil {
            return "Username must start with a letter."
        }
        if username.range(of: #"[a-z0-9]$"#, options: .regularExpression) == nil {
            return "Username must end with a letter or number."
        }
        if username.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) == nil {
            return "Username can only use letters, numbers, and underscores."
        }
        if username.contains("__") {
            return "Username cannot use repeated underscores."
        }
        if reservedUsernames.contains(username) {
            return "That username is reserved."
        }
        return nil
    }

    private static let reservedUsernames: Set<String> = [
        "admin",
        "administrator",
        "api",
        "explore",
        "help",
        "merian",
        "moderator",
        "null",
        "official",
        "root",
        "staff",
        "support",
        "system",
        "undefined"
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
