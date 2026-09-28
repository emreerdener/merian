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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTooltip: Bool
    @State private var showSubmitTooltip = false
    @State private var isPhotoPickerPresented = false
    @State private var photoPickerSelectionLimit = 1
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                discardButton
                HStack(spacing: 8) { mediaNodes }
                .padding(8)
                .modifier(CaptureTrayGlass())
                .disabled(isCheckingPhotoImportAdmission)
                submitButton
                    .disabled(isCheckingPhotoImportAdmission)
            }
            // Report the complete ideal width; never accept a compressed media row.
            .fixedSize(horizontal: true, vertical: false)

            VStack(spacing: 8) {
                CaptureStagingMediaFlowLayout {
                    mediaNodes
                }
                .padding(8)
                .modifier(CaptureTrayGlass(isExpanded: true))
                .disabled(isCheckingPhotoImportAdmission)

                HStack(spacing: 16) {
                    discardButton
                    Spacer(minLength: 0)
                    submitButton
                        .disabled(isCheckingPhotoImportAdmission)
                }
            }
        }
        .overlay(alignment: .top) {
            if showTooltip {
                Text("Add a note about what you noticed")
                    .font(.caption).padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
                    .alignmentGuide(.top) { $0[.bottom] + 8 }
                    .allowsHitTesting(false)
            }
        }
        // Keep the picker owner stable when width or Dynamic Type changes the layout.
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItems,
            maxSelectionCount: photoPickerSelectionLimit,
            matching: .images,
            photoLibrary: dependencies.photoLibrary
        )
        .disabled(isMutationLocked)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: CaptureToolbarHeightKey.self, value: proxy.size.height)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75),
            value: stagedCapture.images.count
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75),
            value: stagedCapture.observationContexts.count
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75),
            value: stagedCapture.audios.count
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75),
            value: stagedCapture.videos.count
        )
        .task {
            guard showTooltip else { return }
            dependencies.markTooltipShown()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .default) { showTooltip = false }
        }
        .onDisappear {
            photoImportAdmissionTask?.cancel()
        }
        .task(id: canShowSubmitTooltip) {
            guard canShowSubmitTooltip, !dependencies.hasShownSubmitTooltip() else { return }
            showSubmitTooltip = true
            dependencies.markSubmitTooltipShown()
            defer { showSubmitTooltip = false }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private var discardButton: some View {
        CaptureStagingCancelButton {
            dependencies.performCancelFeedback()
            onCancel()
        }
    }

    private var submitButton: some View {
        CaptureStagingSubmitButton(
            title: presentation.submitTitle,
            isDisabled: presentation.isSubmitDisabled || !isSubmissionReady,
            onSubmit: onSubmit
        )
        .overlay(alignment: .bottomTrailing) {
            if showSubmitTooltip && canShowSubmitTooltip {
                Text(isRefining ? "Submit to analyze" : "Submit to identify")
                    .font(.caption)
                    .padding(8)
                    .frame(width: 140)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
                    // Anchor the bubble's bottom above the 48 pt action plus an 8 pt gap.
                    .offset(y: -56)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("CaptureSubmitTooltip")
            }
        }
    }

    private var canShowSubmitTooltip: Bool {
        stagedCapture.physicalItemCount >= stagedCaptureLimit
            && stagedCaptureLimit > 0 && !presentation.isSubmitDisabled
            && isSubmissionReady && !isMutationLocked
            && !isCheckingPhotoImportAdmission && !showTooltip
    }

    @ViewBuilder
    private var mediaNodes: some View {
        CaptureStagingToolbarMediaRow(
            presentation: presentation,
            isCheckingPhotoImportAdmission:
                isCheckingPhotoImportAdmission,
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
                .modifier(CaptureStagingNodeSurface(isEmpty: !hasSharedNote))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasSharedNote ? "Edit note" : "Add note")
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
            photoPickerSelectionLimit = selectionCount
            isPhotoPickerPresented = true
        }
    }

}

/// Note state uses supported outlined/filled symbols and the node's border treatment.
struct CaptureStagingNoteIcon: View {
    static let emptySymbol = "bubble.left"
    static let populatedSymbol = "text.bubble.fill"

    let hasNote: Bool

    var body: some View {
        Image(systemName: hasNote ? Self.populatedSymbol : Self.emptySymbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
    }
}
