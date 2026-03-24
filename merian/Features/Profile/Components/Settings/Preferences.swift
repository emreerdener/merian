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

            // MARK: - Manage Plan
            VStack(alignment: .leading, spacing: 8) {
                Button(action: {
                    showPaywall = true
                }) {
                    HStack {
                        Text("Manage plan")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                
                Text("Upgrade or manage your active subscription tier.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)

                 // MARK: - Push Notifications
            NavigationLink {
                NotificationSettingsView()
            } label: {
                HStack {
                    Text("Notifications")
                        .foregroundColor(.primary)
                }
            }
            
             // MARK: - Multi-Image Scans
            SettingsToggleRow(
                title: "Multi-image scans",
                description: "Attach up to 2 images before submitting. By default a single capture is sent to AI immediately.",
                isOn: $multiImageScanMode
            )
            
            // MARK: - Expedition Mode  
            SettingsToggleRow(
                title: "Expedition mode",
                description: "Maximizes battery life off-grid by capping camera frame rates and disabling heavy visual effects.",
                isOn: $hwOrchestrator.isExpeditionModeActive
            )
            .onChange(of: hwOrchestrator.isExpeditionModeActive) { _, _ in
                hardwareOrchestrator.evaluateConstraints()
            }
            
            // MARK: - Live Viewfinder Hints
            SettingsToggleRow(
                title: "Live viewfinder hints",
                description: "Provides real-time AI scanning suggestions before you press the shutter. Turn off to reduce thermal load or battery drain.",
                isOn: hintsDisabled
            )
           
            // MARK: - System Haptics
            Toggle("System haptics", isOn: $isHapticsEnabled)

            // MARK: - Save to Camera Roll
            Toggle("Save to camera roll", isOn: $saveToCameraRoll)
            
            // MARK: - Geoprivacy
            NavigationLink {
                GeoprivacyPickerView(defaultGeoprivacy: $defaultGeoprivacy)
            } label: {
                HStack {
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

/// A reusable generic primitives extracting duplicate VStack, Toggle, and Caption architectures globally.
struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(title, isOn: $isOn)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
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
