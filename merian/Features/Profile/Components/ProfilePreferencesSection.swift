import SwiftUI

struct ProfilePreferencesSection: View {
    @Binding var isExpeditionModeActive: Bool
    @Binding var isLiveInferencePaused: Bool
    @Binding var isHapticsEnabled: Bool
    @Binding var saveToCameraRoll: Bool
    @Binding var defaultGeoprivacy: String
    
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    
    let supabase: SupabaseManager
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                 Picker("Theme", selection: $themeMode) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 16)
            
                Toggle("Expedition Mode", isOn: $isExpeditionModeActive)
                    .onChange(of: isExpeditionModeActive) { _, newValue in
                        HardwareOrchestrator.shared.isExpeditionModeActive = newValue
                        HardwareOrchestrator.shared.evaluateConstraints()
                    }
                Text("Maximizes battery life off-grid by capping camera frame rates and disabling heavy visual effects.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Live Viewfinder Hints", isOn: Binding(
                    get: { !isLiveInferencePaused },
                    set: { newValue in
                        isLiveInferencePaused = !newValue
                        CameraManager.shared.isLiveInferencePaused = !newValue
                    }
                ))
                Text("Provides real-time AI scanning suggestions before you press the shutter. Turn off to reduce thermal load or battery drain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            
            Toggle("System Haptics", isOn: $isHapticsEnabled)
            Toggle("Save to Camera Roll", isOn: $saveToCameraRoll)
            
            Picker("Geoprivacy", selection: $defaultGeoprivacy) {
                Text("Open").tag("open")
                Text("Obscured").tag("obscured")
                Text("Private").tag("private")
            }
            .padding(.vertical, 4)
            .onChange(of: defaultGeoprivacy) { _, newValue in
                Task {
                    guard let userId = supabase.currentUser?.id else { return }
                    do {
                        try await supabase.client.from("users")
                            .update(["default_geoprivacy": newValue])
                            .eq("id", value: userId)
                            .execute()
                    } catch {
                        print("Failed to update geoprivacy: \(error)")
                    }
                }
            }
        } header: {
            Text("Preferences")
        }
    }
}
