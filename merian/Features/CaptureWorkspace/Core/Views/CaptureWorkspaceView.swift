import AVFoundation
import AVKit
import PhotosUI
import SwiftData
import SwiftUI

struct CaptureWorkspaceView: View {
    // MARK: - Environment & Dependencies
    @Environment(CameraManager.self) var cameraManager
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(ViewfinderIntelligence.self) var vui
    @Environment(PhotoLibraryManager.self) var photoLibraryManager
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(AudioCaptureManager.self) var audioCaptureManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - View Model & State
    @State private var viewModel = CaptureWorkspaceViewModel()

    @State private var coordinator = CaptureActionCoordinator()
    @State private var captureMode: CaptureMode
    @State private var observationContext = ObservationContext()
    @AppStorage("isMultiCaptureEnabled") private var isMultiCaptureEnabled: Bool = false
    
    /// The user-defined order for the capture tabs, physically defining the underlying ScrollView layout.
    @AppStorage(UserDefaultsKeys.captureModeOrder) private var captureModeOrderRaw: String = "visual,audio,describe"
    @State private var isKeyboardVisible: Bool = false
    @State private var controlBarHeight: CGFloat = 250
    
    /// The safely deserialized sequence of capture modes governing the ScrollView array.
    private var orderedModes: [CaptureMode] { CaptureMode.userOrder(from: captureModeOrderRaw) }

    // MARK: - Zoom Drag Lock
    @State private var isVerticalZooming: Bool = false
    @State private var isToggleDragging: Bool = false

    // MARK: - Staged Description Sheet
    @State private var isStagedDescriptionSheetPresented: Bool = false

    /// Dedicated scroll-position state for the pager. Decoupled from captureMode so that
    /// scrollPosition(id:) never writes captureMode directly — eliminating the "onChange(of:
    /// CaptureMode) tried to update multiple times per frame" warning that occurs when the
    /// ScrollView's UIKit pan fires its binding setter multiple times per frame during a
    /// simultaneous toggle drag. Two onChange handlers keep the two variables in sync:
    ///   scrollPageMode → captureMode  (user paging, guarded by !isToggleDragging)
    ///   captureMode    → scrollProxy.scrollTo  (programmatic, e.g. toggle tap/drag end)
    @State private var scrollPageMode: CaptureMode?
    
    /// Instantiates the CaptureWorkspaceView by immediately checking `UserDefaults`
    /// to retrieve the user's preferred first tab (default view).
    /// This strictly sidesteps lifecycle events like `.onAppear`, which would
    /// improperly re-snap the UI to the primary tab every time the view remounts.
    init() {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.captureModeOrder) ?? "visual,audio,describe"
        let mode = CaptureMode.userOrder(from: raw).first ?? .visual
        _captureMode = State(initialValue: mode)
        _scrollPageMode = State(initialValue: mode)
    }

    // MARK: - View Hierarchy
    var body: some View {
        ZStack {
                // Paged capture mode switcher.
                // CameraPreviewView lives inside page 1 so the outer horizontal UIScrollView
                // naturally defers vertical pan gestures to the inner camera pan recognizer
                // (zoom), while claiming horizontal ones (paging).
                // GeometryReader captures the true full-screen dimensions (after the outer
                // ZStack's .ignoresSafeArea() expands it) and hands them to each page via
                // explicit .frame(), bypassing any ambiguity in containerRelativeFrame's
                // safe-area-vs-full-screen reference resolution.
                GeometryReader { proxy in
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(orderedModes, id: \.self) { mode in
                                    switch mode {
                                    case .visual:
                                        // MARK: Page 1 — Camera
                                        VisualCaptureView(
                                            viewModel: viewModel,
                                            isVerticalZooming: $isVerticalZooming
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .clipped()
                                        .id(CaptureMode.visual)

                                    case .audio:
                                        // MARK: Page 2 — Audio Recording
                                        AudioRecordingView()
                                            .frame(width: proxy.size.width, height: proxy.size.height)
                                            .clipped()
                                            .id(CaptureMode.audio)

                                    case .describe:
                                        // MARK: Page 3 — Describe Input
                                        DescribeInputView(
                                            captureMode: captureMode,
                                            context: $observationContext,
                                            coordinator: coordinator
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .clipped()
                                        .id(CaptureMode.describe)
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $scrollPageMode)
                        .scrollDisabled(isVerticalZooming || isToggleDragging)
                        .scrollDismissesKeyboard(.interactively)
                        .background(ScrollBounceDisabler())
                        .onChange(of: captureModeOrderRaw, initial: true) { _, raw in
                            let decoded = CaptureMode.userOrder(from: raw)
                            let healedRaw = decoded.map(\.rawValue).joined(separator: ",")
                            if raw != healedRaw {
                                captureModeOrderRaw = healedRaw
                            }
                            // Re-anchor the ScrollView securely onto the active capture mode 
                            // whenever the physical sequence changes underneath it.
                            DispatchQueue.main.async {
                                scrollProxy.scrollTo(captureMode, anchor: .center)
                            }
                        }
                        // Pager → captureMode: when the user swipes to a new page, sync
                        // captureMode. Guarded by !isToggleDragging so simultaneous toggle
                        // drag events that pan the scroll don't write captureMode mid-drag.
                        .onChange(of: scrollPageMode) { _, newPage in
                            if newPage != .describe {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                            guard let newPage, newPage != captureMode, !isToggleDragging else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                captureMode = newPage
                            }
                        }
                        // captureMode → pager: when the toggle commits a mode (tap or drag end),
                        // programmatically scroll the pager to match.
                        .onChange(of: captureMode) { _, newMode in
                            if newMode != .describe {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                            guard newMode != scrollPageMode else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                scrollPageMode = newMode
                            }
                        }
                        .onAppear {
                            // Measure the composing zone: the open area between the mode toggle
                            // (top overlay, 16pt padding + ~48pt height) and the capture button row
                            // (bottom overlay, 140pt padding + 80pt button height).
                            // proxy uses the full-screen frame (.ignoresSafeArea on the GeometryReader)
                            // so safe-area insets must be accounted for explicitly.
                            let toggleBottom     = proxy.safeAreaInsets.top + 16 + 48
                            let captureButtonTop = proxy.size.height - proxy.safeAreaInsets.bottom - 140 - 80
                            viewModel.composingZoneVerticalCenter = ((toggleBottom + captureButtonTop) / 2) / proxy.size.height
                        }
                    }
                }
                .ignoresSafeArea()

                // MARK: Fixed Overlay — Mode Toggle (top)
                if viewModel.stagedCapture.images.count < stagedImageCapacity {
                    VStack {
                        MediaModeToggle(
                            activeMode: $captureMode, 
                            isDragging: $isToggleDragging, 
                            orderedModes: orderedModes, 
                            onModeChange: {}
                        )
                            .padding(.top, 16)
                            .opacity(viewModel.offlineToastMessage != nil ? 0 : 1)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.stagedCapture.images.count)
                }

                // MARK: Fixed Overlay — Capture Controls (bottom, independent of toolbar)
                // Pinned to a fixed absolute bottom offset so toolbar height changes
                // (MainTabBar vs ActiveScanToolbar) never shift the shutter row.
                if viewModel.stagedCapture.images.count < stagedImageCapacity {
                    CaptureControlBar(
                        viewModel: viewModel,
                        captureMode: captureMode,
                        observationContext: $observationContext,
                        isKeyboardVisible: isKeyboardVisible,
                        coordinator: coordinator
                    )
                }

                // MARK: Fixed Overlay — Navigation / scan toolbar (bottom, independent of capture bar)
                VStack {
                    Spacer()

                    if viewModel.stagedCapture.isEmpty {
                        MainTabBar(
                            isScansOpen: $viewModel.activeSheet.mapped(to: .scans),
                            isUserProfileOpen: $viewModel.activeSheet.mapped(to: .profile)
                        )
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        ActiveScanToolbar(
                            stagedCapture: viewModel.stagedCapture,
                            isRefining: viewModel.baseRefinementRecord != nil,
                            selectedPhotoItems: $viewModel.selectedPhotoItems,
                            onThumbnailTap: { index in viewModel.presentCrop(for: index) },
                            onCancel: {
                                viewModel.stagedCapture.clearAll()
                                viewModel.cancelRefinementStaging()
                            },
                            onSubmit: { viewModel.submitStagedCapture(modelContext: modelContext) },
                            onDescriptionTap: { isStagedDescriptionSheetPresented = true }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.stagedCapture.isEmpty)
                .opacity(isKeyboardVisible ? 0 : 1)
                .allowsHitTesting(!isKeyboardVisible)

        } // ZStack
        .merianSystemFeedback(
            toastMessage: Binding(
                get: { viewModel.offlineToastMessage },
                set: { viewModel.offlineToastMessage = $0 }
            ),
            toastAlignment: .top
        )
        .environment(\.controlBarHeight, controlBarHeight)
        .environment(\.composingCenter, viewModel.composingZoneVerticalCenter)
        .onPreferenceChange(CaptureBarHeightPreferenceKey.self) { newHeight in
            if newHeight > 0 { // Avoid zeroing out if the bar temporarily mounts/unmounts
                controlBarHeight = newHeight
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .sheet(isPresented: $isStagedDescriptionSheetPresented) {
            StagedDescriptionSheet(
                initialText: viewModel.stagedCapture.observationContexts.first?.context.freeText ?? "",
                onSave: { newText in
                    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        viewModel.stagedCapture.observationContexts.removeAll()
                    } else {
                        var updatedContext = viewModel.stagedCapture.observationContexts.first?.context ?? ObservationContext()
                        updatedContext.freeText = trimmed
                        if viewModel.stagedCapture.observationContexts.isEmpty {
                            viewModel.stagedCapture.observationContexts.append(StagedObservationContext(context: updatedContext))
                        } else {
                            viewModel.stagedCapture.observationContexts[0] = StagedObservationContext(context: updatedContext, addedAt: viewModel.stagedCapture.observationContexts[0].addedAt)
                        }
                    }
                },
                onRemove: {
                    viewModel.stagedCapture.observationContexts.removeAll()
                }
            )
        }

        // MARK: - View Modifiers
        .cameraSheetRouter(viewModel: viewModel)
        .modifier(CropSheetModifier(
            isPresented: Binding(
                get: { viewModel.imageToCrop != nil },
                set: { if !$0 { viewModel.imageToCrop = nil } }
            ),
            viewModel: viewModel
        ))
        .onAppear {
            viewModel.updateNotificationSuppression()
            if captureMode == .visual {
                cameraManager.startSession()
            }
            photoLibraryManager.startObservingAndFetch()
            AppDIContainer.shared.environmentContextManager.validatePermissions()
            AppDIContainer.shared.environmentContextManager.startLiveLocationTracking()
        }
        .onDisappear {
            cameraManager.stopSession()
            AppDIContainer.shared.environmentContextManager.stopLiveLocationTracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = false }
        }
        .onChange(of: viewModel.selectedPhotoItems) { _, newItems in
            viewModel.handlePhotoPickerSelection(newItems: newItems, modelContext: modelContext)
        }
        .onChange(of: viewModel.stagedCapture.images.count) { _, count in
            // If the user explicitly wants to confirm all submissions, never auto-submit
            guard !UserDefaults.standard.bool(forKey: "requiresScanConfirmation") else { return }

            // If we are in multi-capture or refinement mode, NEVER auto-submit.
            // The user must manually tap "Identify" in the ActiveScanToolbar.
            let isMultiCapture = UserDefaults.standard.bool(forKey: "isMultiCaptureEnabled") || viewModel.baseRefinementRecord != nil
            guard !isMultiCapture else { return }

            // If there were already other modalities staged (audio or describe), do not auto-submit.
            // The user is explicitly composing a scan in the ActiveScanToolbar.
            let hasOtherModalities = !viewModel.stagedCapture.observationContexts.isEmpty || !viewModel.stagedCapture.audios.isEmpty
            guard !hasOtherModalities else { return }

            // For single-capture mode, auto-submit when we have exactly 1 image
            guard count == 1 else { return }

            viewModel.submitStagedCapture(modelContext: modelContext)
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(
                newPhase,
                captureMode: captureMode,
                cameraManager: cameraManager,
                audioCaptureManager: audioCaptureManager
            )
        }
        .onChange(of: captureMode) { _, newMode in
            viewModel.handleCaptureModeChange(
                newMode,
                scenePhase: scenePhase,
                cameraManager: cameraManager,
                audioCaptureManager: audioCaptureManager
            )
        }

        .onChange(of: viewModel.activeSheet) { _, newSheet in
            viewModel.updateNotificationSuppression()

            if newSheet != nil {
                cameraManager.stopSession()
            } else if captureMode == .visual && scenePhase == .active {
                // Strictly guard the un-pause with `scenePhase == .active`, ensuring the
                // startSession() hardware call can never fire indiscriminately during
                // backgrounding transitions when the UI naturally dismisses sheets.
                cameraManager.startSession()
            }
        }
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            viewModel.handleInferenceProcessingChange(isStillProcessing: isStillProcessing)
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .devPreviewAnalyzing)) { _ in
            viewModel.activeSheet = .insight
        }
        #endif
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .requestIdentifyNatureIntent:
                // Close any open modals and shift pager strictly to visual scanning
                viewModel.activeSheet = nil
                captureMode = .visual
            case .requestRecallLastFindIntent:
                // If there's an active or historical cache for a scan, open the modal natively
                if inferenceEngine.historicHydrationTask != nil || inferenceEngine.speciesData != nil {
                    viewModel.activeSheet = .insight
                }
            default: break
            }
        }
        .onChange(of: viewModel.requestedCaptureMode) { _, requested in
            guard let requested else { return }
            captureMode = requested
            viewModel.requestedCaptureMode = nil
            observationContext = ObservationContext()
        }
        .onChange(of: audioCaptureManager.audioFilePath) { _, fileName in
            guard let fileName else { return }
            
            let willStageOnly = !viewModel.stagedCapture.images.isEmpty
                || isMultiCaptureEnabled
                || UserDefaults.standard.bool(forKey: "requiresScanConfirmation")
                || !viewModel.stagedCapture.observationContexts.isEmpty
                
            if willStageOnly {
                viewModel.stagedCapture.audios.append(StagedAudio(filePath: fileName))
            } else {
                viewModel.submitAudio(audioFileName: fileName, modelContext: modelContext)
            }
            audioCaptureManager.reset()
        }
        .onPhysicalCameraShutter(
            isEnabled: viewModel.activeSheet == nil &&
                       viewModel.imageToCrop == nil &&
                       !viewModel.isStagingRefinement
        ) {
            viewModel.executeCapture()
        }
    }
}

// SwiftUI has no native API for disabling pager bounce. This probe walks up the UIKit
// hierarchy from inside the ScrollView's content to find the backing UIScrollView
// and hard-disables bounce so neither edge rubber-bands.

private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { _ProbeView() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private class _ProbeView: UIView {
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            DispatchQueue.main.async { [weak self] in
                var current: UIView? = self?.superview
                while let view = current {
                    if let sv = view as? UIScrollView {
                        sv.bounces = false
                        return
                    }
                    current = view.superview
                }
            }
        }
    }
}

// MARK: - Safe Area Synchronization
struct CaptureBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 250
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension EnvironmentValues {
    var controlBarHeight: CGFloat {
        get { self[ControlBarHeightKey.self] }
        set { self[ControlBarHeightKey.self] = newValue }
    }
}

private struct ControlBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 250
}

extension EnvironmentValues {
    var composingCenter: CGFloat {
        get { self[ComposingCenterKey.self] }
        set { self[ComposingCenterKey.self] = newValue }
    }
}

private struct ComposingCenterKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0.5
}

// End of CaptureWorkspaceView.swift
