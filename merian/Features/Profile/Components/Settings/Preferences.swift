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

            // MARK: - Multi-Image Scans
            SettingsToggleRow(
                title: "Multi-image scans",
                description: "Attach up to 2 images before submitting. By default a single capture is sent to AI immediately.",
                isOn: $multiImageScanMode
            )
            
            // MARK: - Geoprivacy
            Picker("Geoprivacy", selection: $defaultGeoprivacy) {
                Text("Open").tag("open")
                Text("Obscured").tag("obscured")
                Text("Private").tag("private")
            }
            .padding(.vertical, 4)
            .onChange(of: defaultGeoprivacy) { _, newValue in
                // Natively overrides local view model states immediately writing directly back 
                // to the PostgreSQL `.users` table without requiring explicit "Save" buttons.
                Task {
                    guard let userId = supabase.currentUser?.id else { return }
                    do {
                        try await supabase.client.from("users")
                            .update(["default_geoprivacy": newValue])
                            .eq("id", value: userId)
                            .execute()
                    } catch {
                        print("🚨 Failed to mutate PostgreSQL geoprivacy table natively: \(error)")
                    }
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
