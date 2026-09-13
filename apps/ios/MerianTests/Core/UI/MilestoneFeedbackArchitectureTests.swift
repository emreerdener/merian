import Foundation
import Testing

@Suite("Milestone Feedback Architecture")
struct MilestoneFeedbackArchitectureTests {
    @Test func declarationsHaveFocusedOwners() throws {
        let sources = try feedbackSources()

        for declaration in Self.declarationOwners {
            let owners = sources.compactMap { source in
                source.contents.contains(declaration.signature)
                    ? source.relativePath
                    : nil
            }.sorted()

            #expect(
                owners == [declaration.owner],
                "\(declaration.name) must have one focused owner"
            )
        }
    }

    @Test func extractedProductionFilesStayBounded() throws {
        for source in try feedbackSources() {
            #expect(
                lineCount(source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line ceiling"
            )
        }
    }

    @Test func presentationAndPolicyLayersRemainEffectFree() throws {
        let effectFreeFiles = Self.modelPaths
            + Self.policyPaths
            + Self.presentationPaths

        for path in effectFreeFiles {
            let contents = try source(path)
            for forbidden in Self.liveEffectTokens {
                #expect(
                    !contents.contains(forbidden),
                    "\(path) must not own \(forbidden)"
                )
            }
            #expect(!contents.contains("import SwiftData"))
        }

        let coordinator = try source(Self.coordinatorPath)
        for forbidden in Self.liveEffectTokens {
            #expect(
                !coordinator.contains(forbidden),
                "The coordinator must consume injected effects, not \(forbidden)"
            )
        }
    }

    @Test func liveEffectsHaveOneServiceOwnerAndExplicitComposition() throws {
        let sources = try feedbackSources()

        for token in Self.liveEffectTokens {
            let owners = sources.compactMap { source in
                source.contents.contains(token) ? source.relativePath : nil
            }.sorted()
            #expect(
                owners == [Self.liveServicesPath],
                "\(token) must remain isolated to the live service boundary"
            )
        }

        let liveServices = try source(Self.liveServicesPath)
        #expect(liveServices.contains("struct Dependencies"))
        #expect(liveServices.contains("static let live = Self("))
        #expect(liveServices.contains("enum ScanMilestoneLiveServices"))

        let composition = try source("apps/ios/Merian/Core/AppDIContainer.swift")
        #expect(composition.contains("self.scanMilestoneCoordinator = ScanMilestoneCoordinator("))
        #expect(composition.contains("dependencies: .live"))
    }

    @Test func toastFeedbackIsInjectedAndExplicitlyComposed() throws {
        let banner = try source(Self.bannerPath)
        #expect(!banner.contains("HapticManager.shared"))
        #expect(banner.contains("feedback.successPulse()"))
        #expect(banner.contains("feedback.lightImpact("))
        #expect(banner.contains("feedback.selectionPulse("))

        let feedbackService = try source(Self.feedbackServicesPath)
        #expect(feedbackService.contains("struct MilestoneToastFeedbackDependencies"))
        #expect(feedbackService.contains("static func live(hapticManager:"))

        let modifier = try source(Self.systemFeedbackModifierPath)
        #expect(modifier.contains("@Environment(\\.milestoneToastFeedback)"))
        #expect(modifier.contains("feedback: milestoneToastFeedback"))

        let composition = try source("apps/ios/Merian/Core/AppDIContainer.swift")
        #expect(composition.contains("\\.milestoneToastFeedback"))
        #expect(composition.contains(".live(hapticManager: container.hapticManager)"))
    }

    @Test func aggregateAndOversizedTestOwnerAreRetired() throws {
        let root = try repositoryRoot()
        for path in Self.retiredPaths {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "\(path) must stay retired"
            )
        }

        for path in Self.focusedTestPaths {
            let contents = try source(path)
            #expect(
                lineCount(contents) <= 600,
                "\(path) exceeds the focused-test ceiling"
            )
        }
    }

    @Test func focusedSuitesRetainBehavioralCoverage() throws {
        let presenterTests = try source(Self.presenterTestsPath)
        let coordinatorTests = try source(Self.coordinatorTestsPath)
        let achievementTests = try source(Self.achievementTestsPath)
        let policyTests = try source(Self.policyTestsPath)

        for testName in Self.presenterTestNames {
            #expect(presenterTests.contains("func \(testName)("))
        }
        for testName in Self.coordinatorTestNames {
            #expect(coordinatorTests.contains("func \(testName)("))
        }
        for testName in Self.achievementTestNames {
            #expect(achievementTests.contains("func \(testName)("))
        }
        for testName in Self.policyTestNames {
            #expect(policyTests.contains("func \(testName)("))
        }
    }

    @Test func coordinatorTestsUseIsolatedDependencies() throws {
        let coordinatorTests = try source(Self.coordinatorTestsPath)
        let fixtures = try source(
            "apps/ios/MerianTests/Core/UI/MilestoneFeedbackTestFixtures.swift"
        )

        #expect(
            coordinatorTests.contains(
                "MilestoneFeedbackTestFixtures.coordinator("
            )
        )
        #expect(
            !coordinatorTests.contains(
                "let coordinator = ScanMilestoneCoordinator("
            )
        )
        #expect(fixtures.contains("isolatedCoordinatorDependencies"))
        #expect(!fixtures.contains("dependencies: .live"))
        #expect(!coordinatorTests.contains(".sharedProcessState("))
        #expect(!coordinatorTests.contains("@Suite(.serialized"))
    }

    private func feedbackSources() throws -> [(
        relativePath: String,
        contents: String
    )] {
        let root = try repositoryRoot()
        let directory = root.appendingPathComponent(Self.feedbackRoot)
        let enumerator = try #require(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        )
        var sources: [(relativePath: String, contents: String)] = []

        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let relativePath = String(file.path.dropFirst(root.path.count + 1))
            sources.append((
                relativePath,
                try String(contentsOf: file, encoding: .utf8)
            ))
        }
        return sources
    }

    private func source(_ path: String) throws -> String {
        let file = try repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private func lineCount(_ source: String) -> Int {
        source.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private static let feedbackRoot =
        "apps/ios/Merian/Core/UI/Feedback"
    private static let coordinatorPath = feedbackRoot
        + "/Coordination/ScanMilestoneCoordinator.swift"
    private static let liveServicesPath = feedbackRoot
        + "/Services/ScanMilestoneDependencies.swift"
    private static let feedbackServicesPath = feedbackRoot
        + "/Services/MilestoneToastFeedbackDependencies.swift"
    private static let bannerPath = feedbackRoot
        + "/AchievementToastBanner.swift"
    private static let systemFeedbackModifierPath =
        "apps/ios/Merian/Core/UI/Modifiers/MerianSystemFeedbackModifier.swift"
    private static let presenterTestsPath =
        "apps/ios/MerianTests/Core/UI/MilestoneToastPresenterTests.swift"
    private static let coordinatorTestsPath =
        "apps/ios/MerianTests/Core/UI/ScanMilestoneCoordinatorTests.swift"
    private static let achievementTestsPath =
        "apps/ios/MerianTests/Core/UI/MilestoneAchievementPolicyTests.swift"
    private static let policyTestsPath =
        "apps/ios/MerianTests/Core/UI/ScanMilestonePolicyTests.swift"
    private static let architectureTestsPath =
        "apps/ios/MerianTests/Core/UI/MilestoneFeedbackArchitectureTests.swift"
    private static let focusedTestPaths = [
        presenterTestsPath,
        coordinatorTestsPath,
        achievementTestsPath,
        policyTestsPath,
        architectureTestsPath,
        "apps/ios/MerianTests/Core/UI/MilestoneToastFeedbackDependenciesTests.swift",
        "apps/ios/MerianTests/Core/UI/MilestoneFeedbackTestFixtures.swift"
    ]
    private static let retiredPaths = [
        feedbackRoot + "/AchievementToastPresenter.swift",
        "apps/ios/MerianTests/Core/UI/AchievementToastPresenterTests.swift"
    ]
    private static let modelPaths = [
        feedbackRoot + "/Models/MilestoneToastModels.swift"
    ]
    private static let policyPaths = [
        feedbackRoot + "/Policies/FirstFieldTripAchievementPolicy.swift",
        feedbackRoot + "/Policies/FieldTripProgressPresentation.swift",
        feedbackRoot + "/Policies/MilestoneToastPolicy.swift",
        feedbackRoot + "/Policies/ScanMilestonePolicy.swift"
    ]
    private static let presentationPaths = [
        feedbackRoot + "/Presentation/MilestoneToastHostRegistry.swift",
        feedbackRoot + "/Presentation/MilestoneToastPresenter.swift"
    ]
    private static let liveEffectTokens = [
        "FeatureFlags.",
        "GamificationManager.shared",
        "MerianNetworkClient.shared",
        "OfflineQueueManager.shared",
        "SupabaseManager.shared"
    ]
    private static let declarationOwners = [
        (
            name: "FirstFieldTripAchievementPolicy",
            signature: "enum FirstFieldTripAchievementPolicy {",
            owner: feedbackRoot
                + "/Policies/FirstFieldTripAchievementPolicy.swift"
        ),
        (
            name: "FieldTripProgressPresentation",
            signature: "enum FieldTripProgressPresentation {",
            owner: feedbackRoot
                + "/Policies/FieldTripProgressPresentation.swift"
        ),
        (
            name: "MilestoneToastPayload",
            signature: "enum MilestoneToastPayload:",
            owner: feedbackRoot + "/Models/MilestoneToastModels.swift"
        ),
        (
            name: "MilestoneToastPolicy",
            signature: "enum MilestoneToastPolicy {",
            owner: feedbackRoot + "/Policies/MilestoneToastPolicy.swift"
        ),
        (
            name: "ScanMilestonePolicy",
            signature: "enum ScanMilestonePolicy {",
            owner: feedbackRoot + "/Policies/ScanMilestonePolicy.swift"
        ),
        (
            name: "MilestoneToastHostRegistry",
            signature: "final class MilestoneToastHostRegistry {",
            owner: feedbackRoot
                + "/Presentation/MilestoneToastHostRegistry.swift"
        ),
        (
            name: "MilestoneToastPresenter",
            signature: "final class MilestoneToastPresenter:",
            owner: feedbackRoot + "/Presentation/MilestoneToastPresenter.swift"
        ),
        (
            name: "ScanMilestoneCoordinator",
            signature: "final class ScanMilestoneCoordinator:",
            owner: coordinatorPath
        )
    ]
    private static let presenterTestNames = [
        "queuedAchievementUnlocksPresentFIFO",
        "visualMilestoneQueueIsBoundedWhileHostIsUnavailable",
        "accountAndSessionTransitionsFenceStaleMilestoneCallbacks",
        "presentationEffectsAndLifetimeAreClaimedOnceAcrossHostRemounts"
    ]
    private static let coordinatorTestNames = [
        "scanMilestonesWaitForProgressThenPresentInRequiredOrder",
        "transientProgressFailureAutomaticallyRetries",
        "accountTransitionPreventsAStaleResolverFromSchedulingRetryWork",
        "liveAndBackgroundCompletionRaceProcessesScanOnce",
        "coordinatorRoutesLiveEffectsThroughInjectedDependencies"
    ]
    private static let achievementTestNames = [
        "completedAchievementUnlockReturnsTypedPresentationPayloadWhenEnabled",
        "legacyDomesticPetAchievementCompletionIsPersistedWithoutToast",
        "firstFieldTripAchievementNotificationIsDeduplicated",
        "firstFieldTripAchievementProgressMergesAward",
        "fieldTripProgressPresentationPrefersCreditedLevelCounts"
    ]
    private static let policyTestNames = [
        "progressMappingKeepsStandardBeforeChallengeAndUsesGoalPrompt",
        "progressMappingIgnoresUpdatesWithoutNewlyCompletedItems",
        "scanIdentityTrimsAndNormalizesForDeduplication"
    ]
}
