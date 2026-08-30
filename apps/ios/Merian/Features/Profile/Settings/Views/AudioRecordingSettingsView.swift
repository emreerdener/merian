import SwiftUI

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
