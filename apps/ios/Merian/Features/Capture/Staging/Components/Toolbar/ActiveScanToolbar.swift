import PhotosUI
import SwiftUI

struct ActiveScanToolbar: View {
    let stagedCapture: StagedCapture
    let isRefining: Bool
    let stagedCaptureLimit: Int
    let isSubmissionReady: Bool
    let isMutationLocked: Bool
    let onNoteTap: () -> Void
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    let onRequestPhotoPickerPresentation: @MainActor (Int) async -> Bool

    let onThumbnailTap: (Int) -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void
    let onDescriptionTap: (Int) -> Void
    let onAudioTap: (Int) -> Void
    let onVideoTap: (Int) -> Void

    private let dependencies: CaptureStagingToolbarDependencies

    @State private var showTooltip: Bool
    @State private var isPhotoPickerPresented = false
    @State private var isCheckingPhotoImportAdmission = false
    @State private var photoImportAdmissionTask: Task<Void, Never>?

    init(
        stagedCapture: StagedCapture,
        isRefining: Bool,
        stagedCaptureLimit: Int,
        isSubmissionReady: Bool = true,
        isMutationLocked: Bool = false,
        onNoteTap: @escaping () -> Void = {},
        selectedPhotoItems: Binding<[PhotosPickerItem]>,
        onRequestPhotoPickerPresentation: @escaping @MainActor (Int) async -> Bool,
        onThumbnailTap: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping () -> Void,
        onDescriptionTap: @escaping (Int) -> Void,
        onAudioTap: @escaping (Int) -> Void,
        onVideoTap: @escaping (Int) -> Void,
        dependencies: CaptureStagingToolbarDependencies
    ) {
        self.stagedCapture = stagedCapture
        self.isRefining = isRefining
        self.stagedCaptureLimit = stagedCaptureLimit
        self.isSubmissionReady = isSubmissionReady
        self.isMutationLocked = isMutationLocked
        self.onNoteTap = onNoteTap
        self._selectedPhotoItems = selectedPhotoItems
        self.onRequestPhotoPickerPresentation =
            onRequestPhotoPickerPresentation
        self.onThumbnailTap = onThumbnailTap
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.onDescriptionTap = onDescriptionTap
        self.onAudioTap = onAudioTap
        self.onVideoTap = onVideoTap
        self.dependencies = dependencies
        self._showTooltip = State(
            initialValue: !dependencies.hasShownTooltip()
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CaptureStagingCancelButton {
                dependencies.performCancelFeedback()
                onCancel()
            }

            HStack(spacing: 16) {
                ScrollView(.horizontal) {
                    mediaRow
                }
                .transparentTopToolbar()
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .frame(maxWidth: CGFloat(mediaNodeCount * 64 - 16))
                .frame(height: 48)
                .accessibilityIdentifier("StagedMediaRowScroll")

                CaptureStagingSubmitButton(
                    title: presentation.submitTitle,
                    isDisabled: presentation.isSubmitDisabled || !isSubmissionReady,
                    onSubmit: onSubmit
                )
            }
            .padding(8)
            .modifier(CaptureTrayGlass())
            .disabled(isCheckingPhotoImportAdmission)
        }
        .overlay(alignment: .top) {
            if showTooltip {
                Text("Add a note about what you noticed")
                    .font(.caption).padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: -64)
                    .allowsHitTesting(false)
            }
        }
        .disabled(isMutationLocked)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.75),
            value: stagedCapture.images.count
        )
        .animation(
            .spring(response: 0.4, dampingFraction: 0.75),
            value: stagedCapture.observationContexts.count
        )
        .animation(
            .spring(response: 0.4, dampingFraction: 0.75),
            value: stagedCapture.audios.count
        )
        .animation(
            .spring(response: 0.4, dampingFraction: 0.75),
            value: stagedCapture.videos.count
        )
        .task {
            guard showTooltip else { return }
            dependencies.markTooltipShown()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showTooltip = false }
        }
        .onDisappear {
            photoImportAdmissionTask?.cancel()
        }
    }

    private var mediaNodeCount: Int {
        presentation.visibleNodes.count + (presentation.photoSelectionCount == nil ? 0 : 1) + 1
    }

    private var mediaRow: some View {
        HStack(spacing: 16) {
            CaptureStagingToolbarMediaRow(
                presentation: presentation,
                selectedPhotoItems: $selectedPhotoItems,
                isPhotoPickerPresented: $isPhotoPickerPresented,
                isCheckingPhotoImportAdmission:
                    isCheckingPhotoImportAdmission,
                showTooltip: false,
                photoLibrary: dependencies.photoLibrary,
                onRequestPhotoPickerPresentation:
                    requestPhotoPickerPresentation,
                onThumbnailTap: onThumbnailTap,
                onDescriptionTap: onDescriptionTap,
                onAudioTap: onAudioTap,
                onVideoTap: onVideoTap
            )
            Button(action: onNoteTap) {
                CaptureStagingNoteIcon(hasNote: hasSharedNote)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(.primary.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hasSharedNote ? "Edit note" : "Add note")
        }
    }

    private var hasSharedNote: Bool {
        stagedCapture.observationContexts.contains {
            !isRefining || $0.isRefinementSupplement
        }
    }

    private var presentation: CaptureStagingToolbarPresentation {
        CaptureStagingToolbarPresentation(
            stagedCapture: stagedCapture,
            isRefining: isRefining,
            stagedCaptureLimit: stagedCaptureLimit
        )
    }

    private func requestPhotoPickerPresentation(selectionCount: Int) {
        guard photoImportAdmissionTask == nil else { return }

        isCheckingPhotoImportAdmission = true
        photoImportAdmissionTask = Task { @MainActor in
            defer {
                isCheckingPhotoImportAdmission = false
                photoImportAdmissionTask = nil
            }

            let shouldPresent = await onRequestPhotoPickerPresentation(
                selectionCount
            )
            guard shouldPresent, !Task.isCancelled else { return }

            dependencies.dismissKeyboard()
            isPhotoPickerPresented = true
        }
    }

}

/// Compose the empty badge from symbols available on every supported iOS version.
struct CaptureStagingNoteIcon: View {
    static let emptySymbol = "text.bubble"
    static let populatedSymbol = "text.bubble.fill"
    static let badgeSymbol = "plus.circle.fill"

    let hasNote: Bool

    var body: some View {
        Image(systemName: hasNote ? Self.populatedSymbol : Self.emptySymbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.primary)
            .overlay(alignment: .bottomTrailing) {
                if !hasNote {
                    Image(systemName: Self.badgeSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, Color(uiColor: .secondarySystemBackground))
                        .offset(x: 5, y: 4)
                }
            }
            .accessibilityHidden(true)
    }
}
