#if DEBUG
import SwiftUI

struct InitialMediaHistoryUITestPresentation: ViewModifier {
    @State private var fixture: InitialMediaHistoryUIFixture?
    @State private var stage = "not started"
    @State private var failure = ""
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let fixture, !fixture.resultPresented, !fixture.historyPresented {
                VStack {
                    diagnostics(fixture)
                    Button("Open completed result") { fixture.openResult() }.accessibilityIdentifier("InitialHistoryResult")
                    if fixture.selected == "none" {
                        Button("Add completed result to History") { Task { await fixture.addHistory() } }
                            .disabled(fixture.busy).accessibilityIdentifier("InitialHistoryEnroll")
                    } else {
                        Button("Open initial History") { fixture.openHistory() }.accessibilityIdentifier("InitialHistoryOpen")
                    }
                }.padding().background(.regularMaterial)
            } else if !failure.isEmpty { Text(failure).accessibilityIdentifier("InitialHistoryError") }
        }
        .task {
            guard UITestSeedCoordinator.initialMediaHistoryEnabled, fixture == nil else { return }
            do { fixture = try await InitialMediaHistoryUIFixture { stage = $0 } } catch {
                let error = error as NSError
                let domain = ["AVFoundationErrorDomain", NSOSStatusErrorDomain, NSCocoaErrorDomain].contains(error.domain) ? error.domain : "other"
                failure = "Initial media fixture failed: \(stage) [\(domain):\(error.code)]"
            }
        }
        .fullScreenCover(isPresented: Binding(get: { fixture?.resultPresented == true }, set: { fixture?.resultPresented = $0 })) {
            if let fixture {
                VStack(spacing: 0) {
                    Button("Close qualification result") { fixture.resultPresented = false }.accessibilityIdentifier("InitialHistoryCloseResult")
                    InsightSheetView(isPresented: Binding(get: { fixture.resultPresented }, set: { fixture.resultPresented = $0 }),
                        queuedScan: fixture.route, inferenceEngine: fixture.di.inferenceEngine, allowsExplorePresentation: false,
                        dependencies: InsightShellDependencies())
                }.injectAppDependencies(container: fixture.di).modelContainer(fixture.container)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { fixture?.historyPresented == true }, set: { fixture?.historyPresented = $0 })) {
            if let fixture, let history = fixture.history {
                IdentificationHistorySheet(model: history).modelContainer(fixture.container)
            }
        }
    }
    private func diagnostics(_ fixture: InitialMediaHistoryUIFixture) -> some View {
        VStack(spacing: 0) {
            Text(fixture.reopened ? "reopened" : "created").accessibilityIdentifier("InitialHistoryStore")
            Text(String(ProcessInfo.processInfo.processIdentifier)).accessibilityIdentifier("InitialHistoryProcess")
            Text(fixture.witness.scan).accessibilityIdentifier("InitialHistoryScan")
            Text(fixture.witness.baseline.uuidString.lowercased()).accessibilityIdentifier("InitialHistoryBaseline")
            Text(fixture.fingerprint).accessibilityIdentifier("InitialHistoryFingerprint")
            Text(fixture.selected).accessibilityIdentifier("InitialHistorySelection")
            Text(String(fixture.enrollments)).accessibilityIdentifier("InitialHistoryEnrollments")
            if !fixture.failure.isEmpty { Text(fixture.failure).accessibilityIdentifier("InitialHistoryError") }
        }.font(.caption2)
    }
}
#endif
