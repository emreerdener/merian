import PhotosUI
import SwiftUI

struct ActiveScanToolbar: View {
    let stagedCapture: StagedCapture
    let isRefining: Bool
    let stagedCaptureLimit: Int
    let isSubmissionReady: Bool
    let isMutationLocked: Bool
    let isNotesPresented: Bool
    let allowsFrozenRequestActions: Bool
    let selectedNodeID: String?
    let primaryActionTitle: String?
    let onAddMore: (() -> Void)?
    let onNoteTap: () -> Void
    let onUpgradeTap: () -> Void
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    let onRequestPhotoPickerPresentation: @MainActor (Int) async -> Bool

    let onThumbnailTap: (Int) -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void
    let onDescriptionTap: (Int) -> Void
    let onAudioTap: (Int) -> Void
    let onVideoTap: (Int) -> Void

    private let dependencies: CaptureStagingToolbarDependencies

    @Environment(\.captureNotesVisible) private var notesVisibility
    @Environment(\.captureNotesOwnsGrabber) private var ownsGrabber
    private var notesAreVisible: Bool { notesVisibility ?? isNotesPresented }

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
        isNotesPresented: Bool = false,
        allowsFrozenRequestActions: Bool = false,
        selectedNodeID: String? = nil,
        primaryActionTitle: String? = nil,
        onAddMore: (() -> Void)? = nil,
        onNoteTap: @escaping () -> Void = {},
        onUpgradeTap: @escaping () -> Void,
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
        self.isNotesPresented = isNotesPresented
        self.allowsFrozenRequestActions = allowsFrozenRequestActions
        self.selectedNodeID = selectedNodeID
        self.primaryActionTitle = primaryActionTitle
        self.onAddMore = onAddMore
        self.onNoteTap = onNoteTap
        self.onUpgradeTap = onUpgradeTap
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
            HStack(spacing: CaptureStagingToolbarMetrics.spacing) {
                mediaNodes
                submitButton
                    .disabled(isCheckingPhotoImportAdmission)
            }
            .padding(.horizontal, 13)
            .padding(.top, 17)
            .padding(.bottom, 11)
            .modifier(CaptureTrayGlass())
            // Report the complete ideal width; never accept a compressed media row.
            .fixedSize(horizontal: true, vertical: false)

            VStack(spacing: CaptureStagingToolbarMetrics.spacing) {
                CaptureStagingMediaFlowLayout {
                    mediaNodes
                }
                .disabled(isCheckingPhotoImportAdmission || isMutationLocked)
                submitButton.disabled(isCheckingPhotoImportAdmission)
            }
            .padding(.horizontal, 13)
            .padding(.top, 17)
            .padding(.bottom, 11)
            .modifier(CaptureTrayGlass(isExpanded: true))
        }
        .overlay(alignment: .top) {
            if !isNotesPresented, !ownsGrabber {
                CaptureNotesGrabber().padding(.top, 6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("CaptureObservationToolbar")
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            guard !ownsGrabber, !isNotesPresented, !isMutationLocked, value.translation.height < -30,
                  abs(value.translation.height) > abs(value.translation.width) else { return }
            onNoteTap()
        })
        .overlay(alignment: .top) {
            if showTooltip && !isNotesPresented {
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
        .disabled(isMutationLocked && !allowsFrozenRequestActions)
        .padding(.horizontal, 16)
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
            title: primaryActionTitle ?? presentation.submitTitle,
            submitAccessibilityHint: presentation.submitAccessibilityHint,
            isDisabled: (!allowsFrozenRequestActions && presentation.isSubmitDisabled) || !isSubmissionReady,
            onSubmit: onSubmit
        )
        .overlay(alignment: .bottomTrailing) {
            if showSubmitTooltip && canShowSubmitTooltip {
                Text(isRefining ? "Submit to reanalyze" : "Submit to identify")
                    .font(.caption)
                    .padding(8)
                    .frame(width: 140)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
                    // Anchor above the enlarged action with an eight-point gap.
                    .offset(y: -CaptureStagingToolbarMetrics.nodeSize - 8)
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
            selectedNodeID: notesAreVisible ? nil : selectedNodeID,
            addAccessibilityLabel: onAddMore == nil ? "Add photo" : "Add media",
            isReview: onAddMore != nil,
            isAddingMedia: !notesAreVisible && (onAddMore == nil || (isNotesPresented && selectedNodeID == nil)),
            isCheckingPhotoImportAdmission:
                isCheckingPhotoImportAdmission,
            onRequestPhotoPickerPresentation:
                requestPhotoPickerPresentation,
            onUpgradeTap: onUpgradeTap,
            onThumbnailTap: onThumbnailTap,
            onDescriptionTap: onDescriptionTap,
            onAudioTap: onAudioTap,
            onVideoTap: onVideoTap
        )
        .disabled(isCheckingPhotoImportAdmission || isMutationLocked)
        Button(action: onNoteTap) {
            CaptureStagingNoteIcon(hasNote: hasSharedNote)
                .frame(width: CaptureStagingToolbarMetrics.nodeSize, height: CaptureStagingToolbarMetrics.nodeSize)
                .modifier(CaptureStagingNodeSurface(isEmpty: !hasSharedNote, isSelected: notesAreVisible))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasSharedNote ? "Edit field notes" : "Add field notes")
        .accessibilityAddTraits(notesAreVisible ? .isSelected : [])
        .accessibilityIdentifier("CaptureFieldNotes")
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
        if let onAddMore { onAddMore(); return }
        guard !isNotesPresented else { return }

        isCheckingPhotoImportAdmission = true
        photoImportAdmissionTask = Task { @MainActor in
            defer {
                isCheckingPhotoImportAdmission = false
                photoImportAdmissionTask = nil
            }

            let shouldPresent = await onRequestPhotoPickerPresentation(
                selectionCount
            )
            guard shouldPresent, !Task.isCancelled, !isNotesPresented else { return }

            dependencies.dismissKeyboard()
            photoPickerSelectionLimit = selectionCount
            isPhotoPickerPresented = true
        }
    }

}

/// Note state uses supported outlined/filled symbols and the node's border treatment.
struct CaptureStagingNoteIcon: View {
    // Match the Figma SF symbols where available, retaining a drawable note
    // affordance on supported systems whose SF Symbols catalog predates them.
    static let emptySymbol = UIImage(systemName: "long.text.page.and.pencil") != nil
        ? "long.text.page.and.pencil" : "square.and.pencil"
    static let populatedSymbol = UIImage(systemName: "long.text.page.and.pencil.fill") != nil
        ? "long.text.page.and.pencil.fill" : "doc.text.fill"

    let hasNote: Bool

    var body: some View {
        Image(systemName: hasNote ? Self.populatedSymbol : Self.emptySymbol)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(.primary)
            .accessibilityHidden(true)
    }
}
