import SwiftUI

/// The Settings list composition. Child routes own their detailed state.
struct Preferences: View {
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
    let geoprivacyDependencies: GeoprivacySettingsDependencies
    let preferenceActions: SettingsPreferenceActions

    var body: some View {
        @Bindable var appSettings = appSettings

        Section {
            Button {
                if revenueCatManager.isProActive {
                    managePlanActive = true
                } else {
                    showPaywall = true
                }
            } label: {
                ProSettingsBanner(
                    isProActive: revenueCatManager.isProActive
                )
            }
            .buttonStyle(.plain)
            .listRowInsets(
                EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        Section {
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

            SettingsToggleRow(
                title: "Open Explore on launch",
                description: "Show Explore when you launch Naturebook. Close it to return to Scan, Record, or Describe.",
                isOn: $appSettings.opensExploreOnLaunch,
                icon: "safari.fill",
                iconColor: .green
            )

            Button {
                notificationSettingsActive = true
            } label: {
                SettingsNavigationRow(
                    title: "Notifications",
                    description: "Configure alerts for new discoveries and achievement milestones.",
                    icon: "bell.fill",
                    iconColor: .orange
                )
            }

            SettingsToggleRow(
                title: "System haptics",
                description: "Tactile feedback on zoom ticks, captures, and key interactions.",
                isOn: $appSettings.isHapticsEnabled,
                icon: "waveform",
                iconColor: .purple
            )

            NavigationLink {
                GeoprivacyPickerView(
                    defaultGeoprivacy: $defaultGeoprivacy,
                    dependencies: geoprivacyDependencies
                )
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

            ProFeatureToggleRow(
                title: "Expedition mode",
                description: "Maximizes battery life off-grid by capping camera frame rates, disabling heavy visual effects, and suppressing haptics.",
                isOn: Binding(
                    get: { appSettings.isExpeditionModeActive },
                    set: { newValue in
                        preferenceActions.updateExpeditionMode(
                            newValue,
                            persist: {
                                appSettings.isExpeditionModeActive = $0
                            }
                        )
                    }
                ),
                icon: "map.fill",
                iconColor: ProSettingsStyle.accent,
                isProActive: revenueCatManager.isProActive,
                onUpgrade: { showPaywall = true }
            )
        } header: {
            Text("Pro")
        }
        .listRowBackground(ProSettingsStyle.accent.opacity(0.08))

        Section {
            Button {
                cameraSettingsActive = true
            } label: {
                SettingsNavigationRow(
                    title: "Camera",
                    description: "Zoom controls, viewfinder hints, and capture preferences.",
                    icon: "camera.fill",
                    iconColor: .gray
                )
            }

            Button {
                audioRecordingSettingsActive = true
            } label: {
                SettingsNavigationRow(
                    title: "Audio",
                    description: "Microphone hints and tuning preferences.",
                    icon: "mic.fill",
                    iconColor: .red
                )
            }

            Button {
                captureModeOrderSettingsActive = true
            } label: {
                SettingsNavigationRow(
                    title: "Reorder modes",
                    description: "Choose which mode opens first and arrange Scan, Record, and Describe.",
                    icon: "rectangle.split.3x1.fill",
                    iconColor: .yellow
                )
            }

            if FeatureFlags.isEnabled(.fieldTrips) {
                SettingsToggleRow(
                    title: "Show field trip goals",
                    description: "Show your current outing target and progress on the Scan camera.",
                    isOn: $appSettings.showsCaptureGoalProgress,
                    icon: "binoculars.fill",
                    iconColor: .indigo
                )
            }

            SettingsToggleRow(
                title: "Confirm scan submission",
                description: "Present the 'Identify' button after capturing to physically confirm the scan. When disabled, single captures are sent to AI immediately.",
                isOn: $appSettings.requiresScanConfirmation,
                icon: "hand.tap.fill",
                iconColor: .blue
            )
        } header: {
            Text("Workspace")
        }

        #if DEBUG
        SettingsDeveloperSection(
            showPaywall: $showPaywall,
            showTestExploreOnboarding: $showTestExploreOnboarding
        )
        #endif
    }
}
