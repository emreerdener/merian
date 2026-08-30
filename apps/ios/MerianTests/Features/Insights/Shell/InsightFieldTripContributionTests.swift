import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightFieldTripContributionTests {
    @Test func fieldTripContributionsLoadEveryCreditedExperience() async {
        let standard = InsightSheetTestSupport.contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )
        let event = InsightSheetTestSupport.contribution(
            kind: .event,
            sourceId: "participation-1",
            title: "Summer Bird Count"
        )
        let dependencies = InsightShellDependencies(
            authenticationSnapshot: {
                InsightAuthenticationSnapshot(
                    isAuthenticated: true,
                    accountID: "account-1"
                )
            },
            loadFieldTripContributions: { scanId in
                #expect(scanId == "saved-scan")
                return [standard, event]
            },
            isFieldTripsAvailable: { true }
        )
        let viewModel = InsightSheetViewModel(
            inferenceEngine: InsightSheetTestSupport.biologicalEngine(
                scanId: "saved-scan"
            ),
            dependencies: dependencies
        )

        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")

        #expect(viewModel.fieldTripScanContributions == [standard, event])
        #expect(viewModel.isLoadingFieldTripScanContributions == false)
    }

    @Test func fieldTripContributionsExposeLoadingStateUntilRequestCompletes() async {
        let standard = InsightSheetTestSupport.contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )
        let loaderGate = FieldTripContributionLoaderGate()
        let viewModel = InsightSheetViewModel(
            inferenceEngine: InsightSheetTestSupport.biologicalEngine(scanId: "saved-scan"),
            fieldTripContributionLoader: { _ in
                await loaderGate.load()
            },
            fieldTripAuthenticationResolver: { true },
            fieldTripAvailabilityResolver: { true }
        )

        let loadTask = Task {
            await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")
        }
        await loaderGate.waitUntilStarted()

        #expect(viewModel.isLoadingFieldTripScanContributions)
        #expect(viewModel.fieldTripScanContributions.isEmpty)

        await loaderGate.finish(with: [standard])
        await loadTask.value

        #expect(viewModel.isLoadingFieldTripScanContributions == false)
        #expect(viewModel.fieldTripScanContributions == [standard])
    }

    @Test func fieldTripContributionsHideSilentlyOnNetworkFailure() async {
        struct ExpectedFailure: Error {}
        let viewModel = InsightSheetViewModel(
            inferenceEngine: InsightSheetTestSupport.biologicalEngine(scanId: "saved-scan"),
            fieldTripContributionLoader: { _ in throw ExpectedFailure() },
            fieldTripAuthenticationResolver: { true },
            fieldTripAvailabilityResolver: { true }
        )

        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")

        #expect(viewModel.fieldTripScanContributions.isEmpty)
        #expect(viewModel.isLoadingFieldTripScanContributions == false)
    }

    @Test func fieldTripContributionsLoadAfterAuthenticationRestores() async {
        let standard = InsightSheetTestSupport.contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )
        var isAuthenticated = false
        var loaderCalls = 0
        let viewModel = InsightSheetViewModel(
            inferenceEngine: InsightSheetTestSupport.biologicalEngine(scanId: "saved-scan"),
            fieldTripContributionLoader: { _ in
                loaderCalls += 1
                return [standard]
            },
            fieldTripAuthenticationResolver: { isAuthenticated },
            fieldTripAvailabilityResolver: { true }
        )

        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")
        #expect(loaderCalls == 0)
        #expect(viewModel.fieldTripScanContributions.isEmpty)

        isAuthenticated = true
        await viewModel.loadFieldTripScanContributions(scanId: "saved-scan")

        #expect(loaderCalls == 1)
        #expect(viewModel.fieldTripScanContributions == [standard])
    }

    @Test func fieldTripContributionLoadKeyChangesWhenAuthenticationRestores() {
        let signedOut = InsightFieldTripContributionLoadKey(
            scanId: "saved-scan",
            isAuthenticated: false,
            accountId: nil
        )
        let restored = InsightFieldTripContributionLoadKey(
            scanId: "saved-scan",
            isAuthenticated: true,
            accountId: "account-1"
        )

        #expect(signedOut != restored)
    }

    @Test func standardFieldTripInsightContributionRoutesToGoalsOverview() {
        let standard = InsightSheetTestSupport.contribution(
            kind: .standardOuting,
            sourceId: "trip-1",
            title: "Park Pollinators"
        )

        let destination = InsightFieldTripOverviewDestination(contribution: standard)

        #expect(destination == .standardOuting(templateId: "template-trip-1"))
    }

    @Test func eventFieldTripInsightContributionRoutesToChallengeOverview() {
        let event = InsightSheetTestSupport.contribution(
            kind: .event,
            sourceId: "participation-1",
            title: "Summer Bird Count"
        )

        let destination = InsightFieldTripOverviewDestination(contribution: event)

        #expect(destination == .event(challengeId: "challenge-participation-1"))
    }

}

private actor FieldTripContributionLoaderGate {
    private var continuation: CheckedContinuation<[FieldTripScanContribution], Never>?

    func load() async -> [FieldTripScanContribution] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func finish(with contributions: [FieldTripScanContribution]) {
        continuation?.resume(returning: contributions)
        continuation = nil
    }
}
