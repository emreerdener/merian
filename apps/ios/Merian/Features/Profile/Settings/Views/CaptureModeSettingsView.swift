import SwiftUI

/// Configures the order and default launch view of the capture tabs.
struct CaptureModeSettingsView: View {
    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        let orderedModes = CaptureMode.userOrder(
            from: appSettings.captureModeOrderRaw
        )

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
        .navigationTitle("Reorder modes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
