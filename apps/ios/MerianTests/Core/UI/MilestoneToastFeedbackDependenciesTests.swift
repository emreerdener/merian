import Testing

@testable import Merian

@MainActor
@Suite("Milestone toast feedback dependencies")
struct MilestoneToastFeedbackDependenciesTests {
    @Test("Semantic feedback routes through injected closures")
    func semanticFeedbackUsesInjectedClosures() {
        var events: [String] = []
        let dependencies = MilestoneToastFeedbackDependencies(
            successPulse: {
                events.append("success")
            },
            lightImpact: { intensity, source in
                events.append("light:\(intensity):\(source)")
            },
            selectionPulse: { source in
                events.append("selection:\(source ?? "none")")
            }
        )

        dependencies.successPulse()
        dependencies.lightImpact(0.45, "dismiss")
        dependencies.selectionPulse("threshold")
        dependencies.selectionPulse(nil)

        #expect(events == [
            "success",
            "light:0.45:dismiss",
            "selection:threshold",
            "selection:none"
        ])
    }
}
