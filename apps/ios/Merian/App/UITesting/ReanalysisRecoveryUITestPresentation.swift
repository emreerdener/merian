#if DEBUG
import SwiftUI

struct ReanalysisRecoveryUITestPresentation: ViewModifier {
    @State private var fixture: ReanalysisRecoveryUIFixture?
    @State private var stage = "not started"
    @State private var failure = ""
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let fixture, !fixture.presented {
                VStack {
                    diagnostics(fixture)
                    if fixture.isCompleted {
                        Button("Open recovered History") { fixture.openHistory() }.accessibilityIdentifier("ReanalysisFixtureHistory")
                    } else {
                        Button("Open saved reanalysis") { fixture.open() }.accessibilityIdentifier("ReanalysisFixtureOpen")
                        if let boundary = fixture.historyBoundary, !boundary.ledger.available {
                            Button("Make synthetic original result available") { fixture.makeResultAvailable() }
                                .disabled(fixture.charge != 30_000).accessibilityIdentifier("ReanalysisFixtureReleaseResult")
                        }
                    }
                }.padding().background(.regularMaterial)
            } else if !failure.isEmpty { Text(failure).accessibilityIdentifier("ReanalysisFixtureError") }
        }
        .task {
            guard UITestSeedCoordinator.reanalysisRecoveryRestartEnabled, fixture == nil else { return }
            do { fixture = try await ReanalysisRecoveryUIFixture { stage = $0 } } catch { failure = "Reanalysis fixture could not open: " + stage }
        }
        .fullScreenCover(isPresented: Binding(get: { fixture?.presented == true }, set: { shown in
            if !shown { Task { await fixture?.close() } }
        })) {
            if let fixture {
                VStack {
                    diagnostics(fixture)
                    if let model = fixture.history { IdentificationHistorySheet(model: model) } else if let model = fixture.photo { ReanalysisStatusSheet(model: model) } else if let model = fixture.audio { CaptureAudioSavedRequestsSheet(model: model) } else if let model = fixture.video { CaptureVideoSavedRequestsSheet(model: model) }
                }.modelContainer(fixture.container)
            }
        }
    }
    private func diagnostics(_ fixture: ReanalysisRecoveryUIFixture) -> some View {
        VStack(spacing: 0) {
            Text(fixture.reopened ? "reopened" : "created").accessibilityIdentifier("ReanalysisFixtureStore")
            Text(String(ProcessInfo.processInfo.processIdentifier)).accessibilityIdentifier("ReanalysisFixtureProcess")
            Text(fixture.identity.analysisID.uuidString.lowercased()).accessibilityIdentifier("ReanalysisFixtureChild")
            // History exposes acknowledged selection; closed recovery uses persisted fixture facts.
            Text(fixture.history.map { $0.selected?.uuidString.lowercased() ?? "none" } ?? fixture.selection)
                .accessibilityIdentifier("ReanalysisFixtureSelection")
            Text(fixture.requestDigest).accessibilityIdentifier("ReanalysisFixtureRequest")
            Text(fixture.fingerprint).accessibilityIdentifier("ReanalysisFixtureFingerprint")
            Text(String(fixture.charge)).accessibilityIdentifier("ReanalysisFixtureCharge")
            Text(String(fixture.checks)).accessibilityIdentifier("ReanalysisFixtureChecks")
            Text(String(fixture.forbidden)).accessibilityIdentifier("ReanalysisFixtureForbidden")
            if let history = fixture.history {
                Text(String(history.rows.count)).accessibilityIdentifier("ReanalysisFixtureHistoryRowCount")
                Text(history.nextBeforeOrdinal.map(String.init) ?? "none").accessibilityIdentifier("ReanalysisFixtureHistoryNextPage")
            }
            if fixture.historyBoundary != nil {
                Text(fixture.isCompleted ? "complete" : "pending").accessibilityIdentifier("ReanalysisFixtureCompletion")
                Text(fixture.historyBoundary?.ledger.available == true ? "available" : "held").accessibilityIdentifier("ReanalysisFixtureServer")
                Text(String(fixture.completionNotifications)).accessibilityIdentifier("ReanalysisFixtureCompletionNotifications")
            }
            if !fixture.failure.isEmpty { Text(fixture.failure).accessibilityIdentifier("ReanalysisFixtureError") }
            if let boundary = fixture.historyBoundary, !boundary.failure.isEmpty { Text(boundary.failure).accessibilityIdentifier("ReanalysisFixtureError") }
        }.font(.caption2)
        // Test witnesses must not consume the product viewport at accessibility sizes.
        // The sibling production sheet retains the simulator's requested text size.
        .dynamicTypeSize(.medium)
    }
}
#endif
