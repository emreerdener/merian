import Photos
import SwiftUI

struct CameraSettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.scenePhase) private var scenePhase

    @State private var showPermissionPrompt = false
    @State private var addOnlyAuthorizationStatus: PHAuthorizationStatus

    private let dependencies: CameraSettingsDependencies

    init(dependencies: CameraSettingsDependencies? = nil) {
        let dependencies = dependencies ?? .live
        self.dependencies = dependencies
        _addOnlyAuthorizationStatus = State(
            initialValue: dependencies.photoLibraryAuthorizationStatus()
        )
    }

    var body: some View {
        @Bindable var appSettings = appSettings

        List {
            Section {
                SettingsToggleRow(
                    title: "Live viewfinder hints",
                    description: "Provides real-time AI scanning suggestions before you press the shutter. Turn off to reduce thermal load or battery drain.",
                    isOn: hintsEnabled,
                    icon: "sparkles",
                    iconColor: .indigo
                )
            } header: {
                Text("Viewfinder")
            }

            Section {
                SettingsToggleRow(
                    title: "Save to camera roll",
                    description: "Automatically save captured photos and videos to your iPhone's Photos library.",
                    isOn: saveToCameraRoll,
                    icon: "square.and.arrow.down",
                    iconColor: .teal
                )
            } header: {
                Text("Capture")
            }

            Section {
                SettingsToggleRow(
                    title: "Show zoom slider",
                    description: "Display the zoom meter overlay on the camera viewfinder.",
                    isOn: $appSettings.zoomSliderVisible,
                    icon: "slider.vertical.3",
                    iconColor: .blue
                )
                SettingsToggleRow(
                    title: "Right-side zoom slider",
                    description: "Move the zoom meter to the right edge of the viewfinder. Default is on the left edge.",
                    isOn: Binding(
                        get: { !appSettings.zoomSideLeft },
                        set: { appSettings.zoomSideLeft = !$0 }
                    ),
                    icon: "arrow.left.and.right",
                    iconColor: .blue
                )
                SettingsToggleRow(
                    title: "Invert zoom direction",
                    description: "Swipe down to zoom in, swipe up to zoom out.",
                    isOn: $appSettings.invertZoomDirection,
                    icon: "arrow.up.arrow.down",
                    iconColor: .blue
                )
            } header: {
                Text("Zoom")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPermissionPrompt) {
            PhotoLibraryPermissionSheetView(kind: .saveToCameraRoll) {
                refreshPhotoLibraryAuthorization()
                if canSaveToPhotos {
                    appSettings.saveToCameraRoll = true
                }
                showPermissionPrompt = false
            }
            .presentationDetents([.height(350)])
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPhotoLibraryAuthorization()
        }
    }

    private var hintsEnabled: Binding<Bool> {
        Binding(
            get: { !appSettings.isLiveInferencePaused },
            set: { isEnabled in
                let isPaused = !isEnabled
                appSettings.isLiveInferencePaused = isPaused
                dependencies.setLiveInferencePaused(isPaused)
            }
        )
    }

    private var saveToCameraRoll: Binding<Bool> {
        Binding(
            get: { appSettings.saveToCameraRoll },
            set: { newValue in
                if newValue {
                    if canSaveToPhotos {
                        appSettings.saveToCameraRoll = true
                    } else {
                        showPermissionPrompt = true
                    }
                } else {
                    appSettings.saveToCameraRoll = false
                }
            }
        )
    }

    private var canSaveToPhotos: Bool {
        addOnlyAuthorizationStatus == .authorized ||
            addOnlyAuthorizationStatus == .limited
    }

    private func refreshPhotoLibraryAuthorization() {
        addOnlyAuthorizationStatus =
            dependencies.photoLibraryAuthorizationStatus()
    }
}
