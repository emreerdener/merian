import SwiftUI

/// Abstracted Settings component bridging the massive divide between User Layout Toggles and Backend/Hardware Singletons.
struct Preferences: View {
    @Binding var isExpeditionModeActive: Bool
    @Binding var isLiveInferencePaused: Bool
    @Binding var isHapticsEnabled: Bool
    @Binding var saveToCameraRoll: Bool
    @Binding var defaultGeoprivacy: String
    @Binding var showPaywall: Bool
    
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    let supabase: SupabaseManager
    
    var body: some View {
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
                isOn: $isExpeditionModeActive
            )
            .onChange(of: isExpeditionModeActive) { _, newValue in
                // Natively intercepts the toggle layout and radically restricts hardware physical limits instantly.
                HardwareOrchestrator.shared.isExpeditionModeActive = newValue
                HardwareOrchestrator.shared.evaluateConstraints()
            }
            
            // MARK: - Live Viewfinder Hints
            // Synthetically reverses the binding syntax cleanly mapping User-Intent ("Hints ON")
            // directly into the backend logical equivalent (`isLiveInferencePaused == false`)
            SettingsToggleRow(
                title: "Live viewfinder hints",
                description: "Provides real-time AI scanning suggestions before you press the shutter. Turn off to reduce thermal load or battery drain.",
                isOn: Binding(
                    get: { !isLiveInferencePaused },
                    set: { newValue in
                        isLiveInferencePaused = !newValue
                        CameraManager.shared.isLiveInferencePaused = !newValue
                    }
                )
            )

       
            
            // MARK: - System Haptics
            Toggle("System haptics", isOn: $isHapticsEnabled)

            // MARK: - Save to Camera Roll
            Toggle("Save to camera roll", isOn: $saveToCameraRoll)
            
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
