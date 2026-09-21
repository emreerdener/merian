import SwiftUI

struct AudioRecordingSettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings

        List {
            Section {
                SettingsToggleRow(
                    title: "Boost recording previews",
                    description: "Make quiet recordings louder during playback. AI analysis uses the original recording.",
                    isOn: $appSettings.boostRecordingPreviewsEnabled,
                    icon: "speaker.wave.3",
                    iconColor: .purple
                )
            } header: {
                Text("Playback")
            }

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
        .transparentTopToolbar()
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Audio")
        .navigationBarTitleDisplayMode(.inline)
    }
}
