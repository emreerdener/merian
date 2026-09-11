import PhotosUI
import SwiftUI

struct ActiveScanToolbar: View {
    let stagedCapture: StagedCapture
    let isRefining: Bool
    let stagedCaptureLimit: Int
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
                CaptureStagingToolbarMediaRow(
                    presentation: presentation,
                    selectedPhotoItems: $selectedPhotoItems,
                    isPhotoPickerPresented: $isPhotoPickerPresented,
                    isCheckingPhotoImportAdmission:
                        isCheckingPhotoImportAdmission,
                    showTooltip: showTooltip,
                    photoLibrary: dependencies.photoLibrary,
                    onRequestPhotoPickerPresentation:
                        requestPhotoPickerPresentation,
                    onThumbnailTap: onThumbnailTap,
                    onDescriptionTap: onDescriptionTap,
                    onAudioTap: onAudioTap,
                    onVideoTap: onVideoTap
                )

                CaptureStagingSubmitButton(
                    title: presentation.submitTitle,
                    isDisabled: presentation.isSubmitDisabled,
                    onSubmit: onSubmit
                )
            }
            .padding(8)
            .background(glassBackground)
            .overlay(glassBorder)
            .disabled(isCheckingPhotoImportAdmission)
        }
        .environment(\.colorScheme, .dark)
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

    private var glassBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
    }

    private var glassBorder: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.5),
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.5
            )
    }
}
