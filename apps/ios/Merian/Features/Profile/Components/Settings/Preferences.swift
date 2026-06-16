import Photos
import SwiftUI

/// Abstracted Settings component bridging the massive divide between User Layout Toggles and Backend/Hardware Singletons.
struct Preferences: View {
    @Environment(HardwareOrchestrator.self) private var hardwareOrchestrator
    @Environment(SupabaseManager.self) private var supabase
    @Environment(AppSettings.self) private var appSettings
    @Environment(RevenueCatManager.self) private var revenueCatManager

    @Binding var defaultGeoprivacy: String
    @Binding var managePlanActive: Bool
    @Binding var notificationSettingsActive: Bool
    @Binding var cameraSettingsActive: Bool
    @Binding var audioRecordingSettingsActive: Bool
    @Binding var captureModeOrderSettingsActive: Bool
    @Binding var showPaywall: Bool
    @Binding var showTestExploreOnboarding: Bool

    var body: some View {
        @Bindable var hwOrchestrator = hardwareOrchestrator
        @Bindable var appSettings = appSettings

        // MARK: - PRO SUBSCRIPTION BANNER
        Section {
            Button {
                if revenueCatManager.isProActive {
                    managePlanActive = true
                } else {
                    showPaywall = true
                }
            } label: {
                ProSettingsBanner(isProActive: revenueCatManager.isProActive)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        // MARK: - Account & App
        Section {
            // MARK: - Theme
            VStack(alignment: .leading, spacing: 8) {                   
                Picker("Theme", selection: $appSettings.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.rawValue)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            // MARK: - Push Notifications
            Button { notificationSettingsActive = true } label: {
                SettingsNavigationRow(
                    title: "Notifications",
                    description: "Configure alerts for new discoveries and achievement milestones.",
                    icon: "bell.fill",
                    iconColor: .orange
                )
            }

            // MARK: - System Haptics
            SettingsToggleRow(
                title: "System haptics",
                description: "Tactile feedback on zoom ticks, captures, and key interactions.",
                isOn: $appSettings.isHapticsEnabled,
                icon: "waveform",
                iconColor: .purple
            )

            // MARK: - Geoprivacy
            NavigationLink {
                GeoprivacyPickerView(defaultGeoprivacy: $defaultGeoprivacy)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)
                        Text("Geoprivacy")
                            .foregroundColor(.primary)
                        Spacer()
                        Text(defaultGeoprivacy.capitalized)
                            .foregroundColor(.secondary)
                    }
                    Text("Control how precisely your location is recorded on each scan.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 36)
                }
                .padding(.vertical, 4)
            }
        }

        // MARK: - PRO FEATURES
        Section {
            ProFeatureToggleRow(
                title: "Multi-capture mode",
                description: "Attach up to 2 items (photos, audio clips, or descriptions) before submitting.",
                isOn: $appSettings.isMultiCaptureEnabled,
                icon: "square.stack.fill",
                iconColor: ProSettingsStyle.accent,
                isProActive: revenueCatManager.isProActive,
                onUpgrade: { showPaywall = true }
            )
        } header: {
            Text("Pro")
        }
        .listRowBackground(ProSettingsStyle.accent.opacity(0.08))

        // MARK: - Capture setup
        Section {
            // MARK: - Capture Modes
            Button { captureModeOrderSettingsActive = true } label: {
                SettingsNavigationRow(
                    title: "Capture modes",
                    description: "Choose your default mode and reorder Scan, Record, and Describe.",
                    icon: "rectangle.split.3x1.fill",
                    iconColor: .yellow
                )
            }

            // MARK: - Camera
            Button { cameraSettingsActive = true } label: {
                SettingsNavigationRow(
                    title: "Camera",
                    description: "Zoom controls, viewfinder hints, and capture preferences.",
                    icon: "camera.fill",
                    iconColor: .gray
                )
            }
            
            // MARK: - Audio Recording
            Button { audioRecordingSettingsActive = true } label: {
                SettingsNavigationRow(
                    title: "Audio",
                    description: "Microphone hints and tuning preferences.",
                    icon: "mic.fill",
                    iconColor: .red
                )
            }
            // MARK: - Confirm Submissions
            SettingsToggleRow(
                title: "Confirm scan submission",
                description: "Present the 'Identify' button after capturing to physically confirm the scan. When disabled, single captures are sent to AI immediately.",
                isOn: $appSettings.requiresScanConfirmation,
                icon: "hand.tap.fill",
                iconColor: .blue
            )

            // MARK: - Expedition Mode
            SettingsToggleRow(
                title: "Expedition mode",
                description: "Maximizes battery life off-grid by capping camera frame rates, disabling heavy visual effects, and suppressing haptics.",
                isOn: Binding(
                    get: { appSettings.isExpeditionModeActive },
                    set: { newValue in
                        appSettings.isExpeditionModeActive = newValue
                        hwOrchestrator.isExpeditionModeActive = newValue
                        hardwareOrchestrator.evaluateConstraints()
                    }
                ),
                icon: "map.fill",
                iconColor: .green
            )

        } header: {
            Text("Capture")
        }

        #if DEBUG
        Section {
            Button {
                let engine = AppDIContainer.shared.inferenceEngine
                engine.simulateAnalyzing()
                NotificationCenter.default.post(name: .devPreviewAnalyzing, object: nil)
            } label: {
                Label("Preview analyzing state", systemImage: "play.circle")
            }
            
            #if targetEnvironment(simulator)
            Button {
                appSettings.hasCompletedOnboarding = false
            } label: {
                Label("View onboarding", systemImage: "arrow.counterclockwise.circle")
            }
            #endif
            
            Button {
                showTestExploreOnboarding = true
            } label: {
                Label("Test Explore Onboarding", systemImage: "safari")
            }
        } header: {
            Text("Developer")
        }
        #endif
    }

}

#if DEBUG
extension Notification.Name {
    static let devPreviewAnalyzing = Notification.Name("dev.merian.previewAnalyzing")
}
#endif

// MARK: - Pro Settings

private enum ProSettingsStyle {
    static let accent = Color(red: 0.12, green: 0.65, blue: 0.45)
}

private struct ProSettingsBanner: View {
    let isProActive: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image("bird_tree")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .scaleEffect(x: -1, y: 1)
                .offset(x: -14)
                .padding(.leading, 14)
                .padding(.vertical, -18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Merian")
                        .font(.system(.title2).weight(.bold))
                        .foregroundStyle(.white)
                    Text("PRO")
                        .font(.system(.title3).weight(.black))
                        .foregroundStyle(ProSettingsStyle.accent)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.78)

                Text(isProActive ? "Your advanced field kit is active" : "Unlock richer captures and advanced AI analysis")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(.trailing, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.11, blue: 0.08),
                    Color(red: 0.04, green: 0.31, blue: 0.20),
                    Color(red: 0.05, green: 0.20, blue: 0.16)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isProActive ? "Merian Pro active" : "Merian Pro")
    }
}

private struct ProFeatureToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    let icon: String
    let iconColor: Color
    let isProActive: Bool
    let onUpgrade: () -> Void

    var body: some View {
        if isProActive {
            SettingsToggleRow(
                title: title,
                description: description,
                isOn: $isOn,
                icon: icon,
                iconColor: iconColor
            )
        } else {
            Button(action: onUpgrade) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .foregroundStyle(iconColor)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)

                        Text(title)
                            .foregroundColor(.primary)

                        Spacer()

                        Text("Upgrade")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(ProSettingsStyle.accent)

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16, weight: .semibold))
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 36)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Reusable Row Primitives

/// A reusable row for settings items that navigate or trigger an action.
/// Renders an optional icon badge, title, optional description caption, and a trailing chevron.
/// Use as the label of a `Button` (with `.navigationDestination`) rather than
/// `NavigationLink`, which would add a second system disclosure indicator.
struct SettingsNavigationRow: View {
    let title: String
    var description: String?
    var icon: String?
    var iconColor: Color = .gray

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 24)
                }
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .semibold))
            }
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, icon != nil ? 36 : 0)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A reusable row wrapping a Toggle with an optional icon badge and caption.
struct SettingsToggleRow: View {
    let title: String
    var description: String?
    @Binding var isOn: Bool
    var icon: String?
    var iconColor: Color = .gray

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 12) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(iconColor)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24)
                    }
                    Text(title)
                }
            }
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, icon != nil ? 36 : 0)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Camera Settings

struct CameraSettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    
    @State private var showPermissionPrompt = false
    @State private var addOnlyAuthStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)

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
                    description: "Automatically save each captured photo to your iPhone's Photos library.",
                    isOn: Binding(
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
                    ),
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
                    isOn: Binding(get: { !appSettings.zoomSideLeft }, set: { appSettings.zoomSideLeft = !$0 }),
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
                let updatedStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
                addOnlyAuthStatus = updatedStatus
                if updatedStatus == .authorized || updatedStatus == .limited {
                    appSettings.saveToCameraRoll = true
                }
                showPermissionPrompt = false
            }
            .presentationDetents([.height(350)])
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            addOnlyAuthStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        }
    }

    private var hintsEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { !appSettings.isLiveInferencePaused },
            set: { newValue in
                appSettings.isLiveInferencePaused = !newValue
                CameraManager.shared.isLiveInferencePaused = !newValue
            }
        )
    }

    private var canSaveToPhotos: Bool {
        addOnlyAuthStatus == .authorized || addOnlyAuthStatus == .limited
    }
}

// MARK: - Audio Recording Settings

struct AudioRecordingSettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings

        List {
            Section {
                SettingsToggleRow(
                    title: "Live audio hints",
                    description: "Provides real-time mic placement suggestions while recording.",
                    isOn: $appSettings.audioHintsEnabled,
                    icon: "waveform",
                    iconColor: .purple
                )
            } header: {
                Text("Feedback")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Audio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Geoprivacy Picker

/// Full-screen picker pushed from the Preferences row. Displays each option with a
/// plain-language descriptor so users understand the privacy implications before choosing.
struct GeoprivacyPickerView: View {
    @Environment(SupabaseManager.self) private var supabase
    @Binding var defaultGeoprivacy: String

    private struct GeoprivacyOption {
        let id: String
        let title: String
        let descriptor: String
    }

    private let options: [GeoprivacyOption] = [
        GeoprivacyOption(
            id: "open",
            title: "Open",
            descriptor: "Your exact GPS coordinates are recorded and attached to each scan."
        ),
        GeoprivacyOption(
            id: "obscured",
            title: "Obscured",
            descriptor: "Coordinates are rounded to approximately a 10 km area, preserving regional context without exposing your precise location."
        ),
        GeoprivacyOption(
            id: "private",
            title: "Private",
            descriptor: "No location data is attached to your scans — your whereabouts remain entirely hidden."
        )
    ]

    var body: some View {
        List {
            ForEach(options, id: \.id) { option in
                Button {
                    guard defaultGeoprivacy != option.id else { return }
                    defaultGeoprivacy = option.id
                    Task {
                        guard let userId = supabase.currentUser?.id else { return }
                        do {
                            try await supabase.client.from("users")
                                .update(["default_geoprivacy": option.id])
                                .eq("id", value: userId)
                                .execute()
                        } catch {
                            MerianLog.network.error("Failed to update geoprivacy preference: \(error, privacy: .private)")
                        }
                    }
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .foregroundColor(.primary)
                            Text(option.descriptor)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if defaultGeoprivacy == option.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Geoprivacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Capture Mode Settings

/// Dedicated settings sheet for configuring the order and default launch view of the core capture tabs.
struct CaptureModeSettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        let orderedModes = CaptureMode.userOrder(from: appSettings.captureModeOrderRaw)

        List {
            Section {
                ForEach(orderedModes, id: \.self) { mode in
                    Text(mode.title)
                        .foregroundColor(.primary)
                }
                .onMove { indices, newOffset in
                    var modes = orderedModes
                    modes.move(fromOffsets: indices, toOffset: newOffset)
                    appSettings.applyCaptureModeOrder(modes)
                }
            } header: {
                Text("Default order")
            } footer: {
                Text("Drag to reorder. The first mode opens by default.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Capture Modes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
