#if DEBUG
import SwiftUI

struct NativeRecoveryUITestPresentation: ViewModifier {
    @State private var fixture: NativeRecoveryUIFixture?
    @State private var failure = ""
    @State private var setupStage = "not started"
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let fixture, !fixture.presented {
                VStack {
                    diagnostics(fixture)
                    Button("Open pending photo") { Task { await fixture.open() } }.accessibilityIdentifier("NativeFixtureOpen")
                }.padding().background(.regularMaterial)
            } else if !failure.isEmpty { Text(failure).accessibilityIdentifier("NativeFixtureError") }
        }
        .task {
            guard UITestSeedCoordinator.nativeRecoveryEnabled, fixture == nil else { return }
            do { fixture = try await NativeRecoveryUIFixture { setupStage = $0 } } catch { failure = "Native fixture could not open: " + setupStage }
        }
        .fullScreenCover(isPresented: Binding(get: { fixture?.presented == true }, set: { _ in })) {
            if let fixture, let model = fixture.model {
                VStack {
                    diagnostics(fixture)
                    CaptureNativeRecoverySheet(model: model) { Task { await fixture.close() } }
                }.modelContainer(fixture.container)
            }
        }
    }
    private func diagnostics(_ fixture: NativeRecoveryUIFixture) -> some View {
        VStack {
            Text(fixture.reopened ? "reopened" : "created").accessibilityIdentifier("NativeFixtureStore")
            Text(String(ProcessInfo.processInfo.processIdentifier)).accessibilityIdentifier("NativeFixtureProcess")
            Text(fixture.fingerprint).accessibilityIdentifier("NativeFixtureIdentity")
            Text(String(fixture.checks)).accessibilityIdentifier("NativeFixtureChecks")
            Text(String(fixture.chargedMilliseconds)).accessibilityIdentifier("NativeFixtureCharge")
            if let history = fixture.history {
                Text(String(history.enrollments)).accessibilityIdentifier("NativeFixtureEnrollments")
                Text(fixture.selection).accessibilityIdentifier("NativeFixtureSelection")
                Text(fixture.opened ? "requested" : "none").accessibilityIdentifier("NativeFixtureRoute")
            }
            if !fixture.failure.isEmpty { Text(fixture.failure).accessibilityIdentifier("NativeFixtureError") }
        }.font(.caption2)
        // Test witnesses must not consume the product viewport at accessibility sizes.
        // The sibling production sheet retains the simulator's requested text size.
        .dynamicTypeSize(.medium)
    }
}
#endif
