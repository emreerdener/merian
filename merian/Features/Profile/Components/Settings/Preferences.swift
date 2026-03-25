import SwiftUI

/// Abstracted Settings component bridging the massive divide between User Layout Toggles and Backend/Hardware Singletons.
struct Preferences: View {
    @Environment(HardwareOrchestrator.self) private var hardwareOrchestrator
    @Environment(SupabaseManager.self) private var supabase

    @Binding var isLiveInferencePaused: Bool
    @Binding var isHapticsEnabled: Bool
    @Binding var saveToCameraRoll: Bool
    @Binding var defaultGeoprivacy: String
    @Binding var showPaywall: Bool

    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    @AppStorage("multiImageScanMode") private var multiImageScanMode: Bool = false

    @Binding var notificationSettingsActive: Bool
    @Binding var cameraSettingsActive: Bool

    var body: some View {
        @Bindable var hwOrchestrator = hardwareOrchestrator
        Section {

            // MARK: - Theme
            VStack(alignment: .leading, spacing: 8) {                   
                    Picker("Theme", selection: $themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.rawValue)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            // MARK: - Camera
            Button { cameraSettingsActive = true } label: {
                SettingsNavigationRow(title: "Camera", icon: "camera.fill", iconColor: .gray)
            }

            // MARK: - Manage Plan
            Button { showPaywall = true } label: {
                SettingsNavigationRow(
                    title: "Manage plan",
                    description: "Upgrade or manage your active subscription tier.",
                    icon: "crown.fill",
                    iconColor: .orange
                )
            }

            // MARK: - Push Notifications
            Button { notificationSettingsActive = true } label: {
                SettingsNavigationRow(title: "Notifications", icon: "bell.fill", iconColor: .red)
            }

            // MARK: - Multi-Image Scans
            SettingsToggleRow(
                title: "Multi-image scans",
                description: "Attach up to 2 images before submitting. By default a single capture is sent to AI immediately.",
                isOn: $multiImageScanMode,
                icon: "photo.stack.fill",
                iconColor: .blue
            )

            // MARK: - Expedition Mode
            SettingsToggleRow(
                title: "Expedition mode",
                description: "Maximizes battery life off-grid by capping camera frame rates and disabling heavy visual effects.",
                isOn: $hwOrchestrator.isExpeditionModeActive,
                icon: "leaf.fill",
                iconColor: .green
            )
            .onChange(of: hwOrchestrator.isExpeditionModeActive) { _, _ in
                hardwareOrchestrator.evaluateConstraints()
            }

            // MARK: - Live Viewfinder Hints
            SettingsToggleRow(
                title: "Live viewfinder hints",
                description: "Provides real-time AI scanning suggestions before you press the shutter. Turn off to reduce thermal load or battery drain.",
                isOn: hintsDisabled,
                icon: "sparkles",
                iconColor: .indigo
            )

            // MARK: - System Haptics
            SettingsToggleRow(
                title: "System haptics",
                isOn: $isHapticsEnabled,
                icon: "waveform",
                iconColor: .pink
            )

            // MARK: - Save to Camera Roll
            SettingsToggleRow(
                title: "Save to camera roll",
                isOn: $saveToCameraRoll,
                icon: "photo.fill",
                iconColor: .teal
            )

            // MARK: - Geoprivacy
            NavigationLink {
                GeoprivacyPickerView(defaultGeoprivacy: $defaultGeoprivacy)
            } label: {
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
            }
        } header: {
            Text("Preferences")
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
    var description: String? = nil
    var icon: String? = nil
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
    var description: String? = nil
    @Binding var isOn: Bool
    var icon: String? = nil
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

// MARK: - Computed Boundaries
private extension Preferences {
    var hintsDisabled: Binding<Bool> {
        Binding<Bool>(
            get: { !self.isLiveInferencePaused },
            set: { newValue in
                self.isLiveInferencePaused = !newValue
                CameraManager.shared.isLiveInferencePaused = !newValue
            }
        )
    }
}

// MARK: - Camera Settings

struct CameraSettingsView: View {
    @AppStorage(UserDefaultsKeys.invertZoomDirection) private var invertZoomDirection: Bool = false
    @AppStorage(UserDefaultsKeys.zoomSideLeft) private var zoomSideLeft: Bool = false

    var body: some View {
        List {
            Section {
                SettingsToggleRow(
                    title: "Left-side zoom slider",
                    description: "Move the zoom meter to the left edge of the viewfinder.",
                    isOn: $zoomSideLeft,
                    icon: "arrow.left.and.right",
                    iconColor: .blue
                )
                SettingsToggleRow(
                    title: "Invert zoom direction",
                    description: "Swipe down to zoom in, swipe up to zoom out.",
                    isOn: $invertZoomDirection,
                    icon: "arrow.up.arrow.down",
                    iconColor: .blue
                )
            } header: {
                Text("Zoom")
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Geoprivacy Picker

/// Full-screen picker pushed from the Preferences row. Displays each option with a
/// plain-language descriptor so users understand the privacy implications before choosing.
struct GeoprivacyPickerView: View {
    @Environment(SupabaseManager.self) private var supabase
    @Binding var defaultGeoprivacy: String

    private let options: [(id: String, title: String, descriptor: String)] = [
        (
            "open",
            "Open",
            "Your exact GPS coordinates are recorded and attached to each scan."
        ),
        (
            "obscured",
            "Obscured",
            "Coordinates are rounded to approximately a 10 km area, preserving regional context without exposing your precise location."
        ),
        (
            "private",
            "Private",
            "No location data is attached to your scans — your whereabouts remain entirely hidden."
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
