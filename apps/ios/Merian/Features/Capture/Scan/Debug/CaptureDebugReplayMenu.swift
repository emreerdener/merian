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
            Menu("Stage comparison slot") {
                ForEach(0..<3, id: \.self) { group in
                    Menu("Slots \(group * 4 + 1)–\(group * 4 + 4)") {
                        ForEach(DebugAudioComparisonSlot.allCases.filter {
                            ($0.rawValue - 1) / 4 == group
                        }, id: \.rawValue) { slot in
                            Button("\(slot.rawValue) · \(slot.assignment.caseId)") {
                                viewModel.startDebugReplay(.audio, profile: .audioComparison(slot: slot))
                            }
                            .accessibilityIdentifier("debugReplayAudioComparison\(slot.rawValue)")
                        }
                    }
                }
            }
            Menu("Stage prompt comparison") {
                ForEach(1...3, id: \.self) { block in
                    Menu("Block \(block)") {
                        ForEach(0..<3, id: \.self) { group in
                            Menu("Slots \((block - 1) * 12 + group * 4 + 1)–\((block - 1) * 12 + group * 4 + 4)") {
                                ForEach(DebugAudioPromptComparisonSlot.allCases.filter {
                                    $0.assignment.block == block && (($0.rawValue - 1) % 12) / 4 == group
                                }, id: \.rawValue) { slot in
                                    Button("\(slot.rawValue) · \(slot.assignment.caseId) · \(slot.assignment.arm)") {
                                        viewModel.startDebugReplay(.audio, profile: .audioPromptComparison(slot: slot))
                                    }
                                    .accessibilityIdentifier("debugReplayAudioPromptComparison\(slot.rawValue)")
                                }
                            }
                        }
                    }
                }
            }
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
