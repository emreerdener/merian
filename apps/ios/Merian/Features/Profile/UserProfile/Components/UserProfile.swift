import PhotosUI
import SwiftUI
import UIKit

enum UserProfilePresentation: Identifiable {
    case usernameEditor
    case displayNameEditor
    case avatarCrop(IdentifiableImage)

    var id: String {
        switch self {
        case .usernameEditor:
            "username-editor"
        case .displayNameEditor:
            "display-name-editor"
        case .avatarCrop(let image):
            "avatar-crop-\(image.id.uuidString)"
        }
    }

    var usesFullscreenCover: Bool {
        if case .avatarCrop = self { return true }
        return false
    }
}

enum UserProfileAvatarPresentationPolicy {
    static func canAcceptPreparedAvatar(
        requestID: UUID,
        currentRequestID: UUID?,
        hasActivePresentation: Bool,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && !hasActivePresentation && currentRequestID == requestID
    }
}

private struct PreparedAvatarCropRequest {
    let requestID: UUID
    let image: IdentifiableImage
}

/// Profile identity component for anonymous and linked account states.
struct UserProfile: View {
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(RevenueCatManager.self) private var revenueCatManager: RevenueCatManager?
    @Binding var isShowingAvatarPicker: Bool
    @Binding var isShowingDisplayNameEditor: Bool
    @Binding var isShowingUsernameEditor: Bool
    @State private var activePresentation: UserProfilePresentation?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarSelectionRequestID: UUID?
    @State private var avatarSelectionTask: Task<Void, Never>?
    @State private var preparedAvatarCropRequest: PreparedAvatarCropRequest?
    @State private var avatarUploadRequestID: UUID?
    @State private var avatarUploadTask: Task<Void, Never>?
    @State private var pendingAvatarErrorMessage: String?
    @State private var isRetryingPurchaseContinuity = false
    @State private var purchaseContinuityRetryFailed = false
    var totalScans: Int = 0
    var completedAchievements: Int = 0
    var earnedFieldTripPatches: [EarnedFieldTripPatch] = []
    var isLoadingEarnedFieldTripPatches = false
    let onOpenFieldTrip: (String) -> Void
    
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
        .sheet(item: sheetPresentationBinding) { presentation in
            sheetContent(presentation)
        }
        .fullScreenCover(item: fullscreenPresentationBinding) { presentation in
            fullscreenContent(presentation)
        }
        .onChange(of: selectedAvatarItem) { _, newItem in
            handleAvatarSelection(newItem)
        }
        .onChange(of: isShowingUsernameEditor, initial: true) { _, isRequested in
            synchronizeEditorRequest(
                .usernameEditor,
                isRequested: isRequested,
                source: $isShowingUsernameEditor
            )
        }
        .onChange(of: isShowingDisplayNameEditor, initial: true) { _, isRequested in
            synchronizeEditorRequest(
                .displayNameEditor,
                isRequested: isRequested,
                source: $isShowingDisplayNameEditor
            )
        }
        .onChange(of: isShowingAvatarPicker) { _, isRequested in
            guard isRequested else {
                commitPreparedAvatarCropIfPossible()
                return
            }
            if activePresentation != nil || avatarUploadTask != nil {
                isShowingAvatarPicker = false
                return
            }
            cancelAvatarSelectionTask()
        }
        .onChange(of: profileViewModel.currentUserId) { _, _ in
            cancelAvatarTasks()
            selectedAvatarItem = nil
            isShowingAvatarPicker = false
            pendingAvatarErrorMessage = nil
            profileViewModel.avatarUpdateErrorMessage = nil
            dismissActivePresentation()
        }
        .onDisappear {
            cancelAvatarTasks()
        }
        .photosPicker(
            isPresented: $isShowingAvatarPicker,
            selection: $selectedAvatarItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .alert("Profile picture update failed", isPresented: avatarErrorBinding) {
            Button("OK", role: .cancel) {
                pendingAvatarErrorMessage = nil
            }
        } message: {
            Text(
                pendingAvatarErrorMessage
                    ?? profileViewModel.avatarUpdateErrorMessage
                    ?? "Naturebook could not update your profile picture."
            )
        }
    }

    private var sheetPresentationBinding: Binding<UserProfilePresentation?> {
        Binding(
            get: {
                guard activePresentation?.usesFullscreenCover == false else {
                    return nil
                }
                return activePresentation
            },
            set: { presentation in
                guard presentation == nil,
                      activePresentation?.usesFullscreenCover == false else {
                    return
                }
                dismissActivePresentation()
            }
        )
    }

    private var fullscreenPresentationBinding:
        Binding<UserProfilePresentation?> {
        Binding(
            get: {
                guard activePresentation?.usesFullscreenCover == true else {
                    return nil
                }
                return activePresentation
            },
            set: { presentation in
                guard presentation == nil,
                      activePresentation?.usesFullscreenCover == true else {
                    return
                }
                dismissActivePresentation()
            }
        )
    }

    private var avatarErrorBinding: Binding<Bool> {
        Binding(
            get: {
                activePresentation == nil &&
                    !isShowingAvatarPicker &&
                    pendingAvatarErrorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    pendingAvatarErrorMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func sheetContent(_ presentation: UserProfilePresentation) -> some View {
        switch presentation {
        case .usernameEditor:
            PublicUsernameEditSheet(viewModel: profileViewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(UIColor.systemGroupedBackground))

        case .displayNameEditor:
            PublicDisplayNameEditSheet(viewModel: profileViewModel)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color(UIColor.systemGroupedBackground))

        case .avatarCrop:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fullscreenContent(
        _ presentation: UserProfilePresentation
    ) -> some View {
        switch presentation {
        case .avatarCrop(let item):
            ImageCropperView(
                image: item.image,
                onCrop: { croppedData, _, _, _ in
                    dismissPresentation(ifMatching: presentation.id)
                    uploadConfirmedAvatarCrop(croppedData)
                },
                onCancel: {
                    dismissPresentation(ifMatching: presentation.id)
                }
            )

        case .usernameEditor, .displayNameEditor:
            EmptyView()
        }
    }

    private func synchronizeEditorRequest(
        _ presentation: UserProfilePresentation,
        isRequested: Bool,
        source: Binding<Bool>
    ) {
        if isRequested {
            cancelAvatarSelectionTask()
            guard beginPresentation(presentation) else {
                source.wrappedValue = false
                return
            }
        } else if activePresentation?.id == presentation.id {
            dismissActivePresentation()
        }
    }

    @discardableResult
    private func beginPresentation(
        _ presentation: UserProfilePresentation
    ) -> Bool {
        guard activePresentation == nil,
              !isShowingAvatarPicker else { return false }
        activePresentation = presentation
        return true
    }

    private func dismissPresentation(ifMatching presentationID: String) {
        guard activePresentation?.id == presentationID else { return }
        dismissActivePresentation()
    }

    private func dismissActivePresentation() {
        guard let presentation = activePresentation else { return }
        activePresentation = nil
        switch presentation {
        case .usernameEditor:
            isShowingUsernameEditor = false
        case .displayNameEditor:
            isShowingDisplayNameEditor = false
        case .avatarCrop:
            break
        }
    }

    private var profileCard: some View {
        VStack(spacing: 12) {
            identityHeader
            Divider()
            summaryCountsRow

            if !earnedFieldTripPatches.isEmpty {
                Divider()
                EarnedFieldTripPatchCarousel(
                    patches: earnedFieldTripPatches,
                    onOpenFieldTrip: onOpenFieldTrip
                )
            } else if isLoadingEarnedFieldTripPatches {
                Divider()
                EarnedFieldTripPatchCarouselSkeleton()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private var isPaidPro: Bool {
        revenueCatManager?.isSubscribed ?? RevenueCatManager.shared.isSubscribed
    }

    private var isPurchaseContinuityPending: Bool {
        revenueCatManager?.isPurchaseIdentityHandoffPending
            ?? RevenueCatManager.shared.isPurchaseIdentityHandoffPending
    }

    private var identityHeader: some View {
        HStack(spacing: 12) {
            avatarPicker

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(profileViewModel.displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if isPaidPro {
                        MerianProBadge()
                    }
                }

                Text(profileViewModel.publicUsernameDisplayName ?? "Loading username")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    private var signInButtons: some View {
        VStack(spacing: 12) {
            if isPurchaseContinuityPending {
                VStack(spacing: 8) {
                    Text("Finish signing out before changing accounts or making purchases.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task { await retryPurchaseContinuity() }
                    } label: {
                        HStack {
                            if isRetryingPurchaseContinuity {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Finish sign out")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(isRetryingPurchaseContinuity)

                    if purchaseContinuityRetryFailed {
                        Text("Purchase access is still syncing. Check your connection and try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            Button(action: {
                Task {
                    await profileViewModel.signInWithApple()
                }
            }) {
                HStack {
                    if profileViewModel.activeOAuthProvider == .apple {
                        ProgressView()
                            .tint(Color(UIColor.systemBackground))
                    } else {
                        Image(systemName: "applelogo")
                    }
                    Text("Continue with Apple")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .foregroundColor(Color(UIColor.systemBackground))
                .clipShape(Capsule())
            }
            .disabled(
                isPurchaseContinuityPending ||
                    profileViewModel.isAuthTransitionInProgress
            )

            Button(action: {
                Task {
                    await profileViewModel.signInWithGoogle()
                }
            }) {
                HStack {
                    if profileViewModel.activeOAuthProvider == .google {
                        ProgressView()
                    } else {
                        Image("google-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    Text("Continue with Google")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .foregroundColor(.primary)
                .clipShape(Capsule())
            }
            .disabled(
                isPurchaseContinuityPending ||
                    profileViewModel.isAuthTransitionInProgress
            )
        }
    }

    @MainActor
    private func retryPurchaseContinuity() async {
        isRetryingPurchaseContinuity = true
        purchaseContinuityRetryFailed = false
        let completed = await profileViewModel
            .retryPendingSignOutPurchaseHandoff()
        purchaseContinuityRetryFailed = !completed
        isRetryingPurchaseContinuity = false
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
        guard activePresentation == nil,
              avatarUploadTask == nil else { return }

        cancelAvatarSelectionTask()
        let requestID = UUID()
        avatarSelectionRequestID = requestID
        avatarSelectionTask = Task { @MainActor in
            defer {
                if avatarSelectionRequestID == requestID {
                    avatarSelectionTask = nil
                    if preparedAvatarCropRequest?.requestID != requestID {
                        avatarSelectionRequestID = nil
                    }
                }
            }
            do {
                guard let wrapper = try await item.loadTransferable(type: ImageFileWrapper.self) else {
                    guard UserProfileAvatarPresentationPolicy.canAcceptPreparedAvatar(
                        requestID: requestID,
                        currentRequestID: avatarSelectionRequestID,
                        hasActivePresentation: activePresentation != nil,
                        isCancelled: Task.isCancelled
                    ) else { return }
                    queueAvatarError("Naturebook could not load that image.")
                    return
                }

                let fileURL = wrapper.url
                defer { try? FileManager.default.removeItem(at: fileURL) }

                let preview = try await MediaPreparationActor.shared.preparePreviewImage(
                    fileURL: fileURL,
                    maxSize: MerianConfig.displayImageMaxSize
                )
                guard UserProfileAvatarPresentationPolicy.canAcceptPreparedAvatar(
                    requestID: requestID,
                    currentRequestID: avatarSelectionRequestID,
                    hasActivePresentation: activePresentation != nil,
                    isCancelled: Task.isCancelled
                ) else { return }

                let preparedRequest = PreparedAvatarCropRequest(
                    requestID: requestID,
                    image: IdentifiableImage(
                        image: UIImage(cgImage: preview.cgImage)
                    )
                )
                if isShowingAvatarPicker {
                    preparedAvatarCropRequest = preparedRequest
                } else {
                    _ = beginPresentation(.avatarCrop(preparedRequest.image))
                }
            } catch is CancellationError {
                return
            } catch {
                guard UserProfileAvatarPresentationPolicy.canAcceptPreparedAvatar(
                    requestID: requestID,
                    currentRequestID: avatarSelectionRequestID,
                    hasActivePresentation: activePresentation != nil,
                    isCancelled: Task.isCancelled
                ) else { return }
                queueAvatarError(error.localizedDescription)
            }
        }
    }

    private func commitPreparedAvatarCropIfPossible() {
        guard !isShowingAvatarPicker,
              activePresentation == nil,
              let preparedAvatarCropRequest,
              avatarSelectionRequestID == preparedAvatarCropRequest.requestID else {
            return
        }
        self.preparedAvatarCropRequest = nil
        avatarSelectionRequestID = nil
        _ = beginPresentation(.avatarCrop(preparedAvatarCropRequest.image))
    }

    private func uploadConfirmedAvatarCrop(_ croppedData: Data) {
        guard !croppedData.isEmpty else {
            queueAvatarError("Naturebook could not crop that image.")
            return
        }

        cancelAvatarUploadTask()
        let requestID = UUID()
        let expectedUserID = profileViewModel.currentUserId
        avatarUploadRequestID = requestID
        avatarUploadTask = Task { @MainActor in
            defer {
                if avatarUploadRequestID == requestID {
                    avatarUploadRequestID = nil
                    avatarUploadTask = nil
                }
            }
            do {
                let avatar = try await DetachedWork.value(
                    priority: .userInitiated,
                    category: .imagePreparation
                ) {
                    try ProfileAvatarImagePreparer.prepare(croppedData: croppedData)
                }
                guard avatarUploadRequestID == requestID,
                      !Task.isCancelled,
                      profileViewModel.currentUserId == expectedUserID else {
                    return
                }

                let didUpdate = await profileViewModel.updatePublicAvatar(avatar)
                guard avatarUploadRequestID == requestID,
                      !Task.isCancelled,
                      profileViewModel.currentUserId == expectedUserID else {
                    return
                }
                guard !didUpdate else { return }
                queueAvatarError(
                    profileViewModel.avatarUpdateErrorMessage
                        ?? "Naturebook could not update your profile picture."
                )
            } catch is CancellationError {
                return
            } catch {
                guard avatarUploadRequestID == requestID,
                      !Task.isCancelled,
                      profileViewModel.currentUserId == expectedUserID else {
                    return
                }
                queueAvatarError(error.localizedDescription)
            }
        }
    }

    private func queueAvatarError(_ message: String) {
        profileViewModel.avatarUpdateErrorMessage = message
        pendingAvatarErrorMessage = message
    }

    private func cancelAvatarSelectionTask() {
        avatarSelectionRequestID = nil
        avatarSelectionTask?.cancel()
        avatarSelectionTask = nil
        preparedAvatarCropRequest = nil
    }

    private func cancelAvatarUploadTask() {
        avatarUploadRequestID = nil
        avatarUploadTask?.cancel()
        avatarUploadTask = nil
    }

    private func cancelAvatarTasks() {
        cancelAvatarSelectionTask()
        cancelAvatarUploadTask()
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
                summaryCountView(value: "0", label: "Followers")
                    .frame(maxWidth: .infinity)
                summaryCountView(value: "0", label: "Following")
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
            Text("Optional · up to 40 characters.")
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
