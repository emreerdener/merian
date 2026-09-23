#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct CaptureDebugReplayMenu: View {
    @Bindable var viewModel: CaptureWorkspaceViewModel
    let isAvailable: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Menu(viewModel.hasFixedContextDebugReplay ? "Replay: fixed context" : "Debug replay",
             systemImage: "play.rectangle") {
            Button("Stage audio sample") { viewModel.startDebugReplay(.audio) }
                .accessibilityIdentifier("debugReplayAudio")
            Button("Stage audio with fixed context") {
                viewModel.startDebugReplay(.audio, profile: .audioMinimalV1)
            }
            .accessibilityIdentifier("debugReplayAudioFixedContext")
            Button("Stage video sample") { viewModel.startDebugReplay(.video) }
                .disabled(!viewModel.dependencies.scan.canStartProScan())
                .accessibilityIdentifier("debugReplayVideo")
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .disabled(!isAvailable || !viewModel.canStartDebugReplay || scenePhase != .active)
        .accessibilityIdentifier("debugReplayMenu")
        .onChange(of: isAvailable) { _, available in
            if !available { viewModel.cancelDebugReplay() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { viewModel.cancelDebugReplay() }
        }
        .onDisappear { viewModel.cancelDebugReplay() }
    }
}
#endif
