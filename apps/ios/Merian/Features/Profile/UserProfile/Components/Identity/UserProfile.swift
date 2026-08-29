import PhotosUI
import SwiftUI
import UIKit

/// Profile identity component for anonymous and linked account states.
struct UserProfile: View {
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Binding var isShowingAvatarPicker: Bool
    @Binding var isShowingDisplayNameEditor: Bool
    @Binding var isShowingUsernameEditor: Bool
    @State private var activePresentation: UserProfilePresentation?
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarCoordinator = UserProfileAvatarCoordinator()
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
        .onChange(of: avatarCoordinator.preparedCropImage?.id) {
            presentPreparedAvatarIfPossible()
        }
        .onChange(of: avatarCoordinator.pendingErrorMessage) { _, message in
            profileViewModel.avatarUpdateErrorMessage = message
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
                presentPreparedAvatarIfPossible()
                return
            }
            if activePresentation != nil || avatarCoordinator.isUploading {
                isShowingAvatarPicker = false
                return
            }
            avatarCoordinator.cancelSelection()
        }
        .onChange(of: profileViewModel.currentUserId) { _, _ in
            avatarCoordinator.cancelAll()
            selectedAvatarItem = nil
            isShowingAvatarPicker = false
            avatarCoordinator.clearPendingError()
            profileViewModel.avatarUpdateErrorMessage = nil
            dismissActivePresentation()
        }
        .onDisappear {
            avatarCoordinator.cancelAll()
        }
        .photosPicker(
            isPresented: $isShowingAvatarPicker,
            selection: $selectedAvatarItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .alert("Profile picture update failed", isPresented: avatarErrorBinding) {
            Button("OK", role: .cancel) {
                avatarCoordinator.clearPendingError()
            }
        } message: {
            Text(
                avatarCoordinator.pendingErrorMessage
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
                    avatarCoordinator.pendingErrorMessage != nil
            },
            set: { isPresented in
                if !isPresented {
                    avatarCoordinator.clearPendingError()
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
            avatarCoordinator.cancelSelection()
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
        revenueCatManager.isSubscribed
    }

    private var isPurchaseContinuityPending: Bool {
        revenueCatManager.isPurchaseIdentityHandoffPending
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
              !avatarCoordinator.isUploading else { return }

        avatarCoordinator.select(
            item,
            isPresentationSlotAvailable: { activePresentation == nil }
        )
    }

    private func presentPreparedAvatarIfPossible() {
        guard avatarCoordinator.preparedCropImage != nil else { return }
        guard activePresentation == nil else {
            avatarCoordinator.discardPreparedCropImage()
            return
        }
        guard !isShowingAvatarPicker,
              let image = avatarCoordinator.takePreparedCropImage() else {
            return
        }
        _ = beginPresentation(.avatarCrop(image))
    }

    private func uploadConfirmedAvatarCrop(_ croppedData: Data) {
        let expectedUserID = profileViewModel.currentUserId
        avatarCoordinator.upload(
            croppedData: croppedData,
            expectedUserID: expectedUserID,
            currentUserID: { profileViewModel.currentUserId },
            updateAvatar: { avatar in
                await profileViewModel.updatePublicAvatar(avatar)
            },
            updateFailureMessage: {
                profileViewModel.avatarUpdateErrorMessage
            }
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
