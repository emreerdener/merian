import Foundation
import Testing

@Suite("Field Trips Network Model Architecture")
struct FieldTripNetworkModelArchitectureTests {
    @Test func focusedOwnersRetireTheAggregateAndStayBounded() throws {
        let root = try repositoryRoot()
        let networkRoot = root.appendingPathComponent("apps/ios/Merian/Core/Network")
        let modelsRoot = networkRoot.appendingPathComponent("Models/FieldTrips")
        let aggregate = networkRoot.appendingPathComponent("FieldTripAPIModels.swift")

        #expect(!FileManager.default.fileExists(atPath: aggregate.path))

        let files = try swiftFiles(in: modelsRoot)
        #expect(Set(files.map(\.lastPathComponent)) == Self.expectedModelFilenames)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                lineCount(source) <= 600,
                "\(file.lastPathComponent) exceeded the model review ceiling"
            )
            for forbiddenToken in Self.forbiddenModelTokens {
                #expect(
                    !source.contains(forbiddenToken),
                    "\(file.lastPathComponent) must not own \(forbiddenToken)"
                )
            }
        }
    }

    @Test func networkModelDeclarationsHaveExactlyOneFocusedOwner() throws {
        let root = try repositoryRoot()
        let productionRoot = root.appendingPathComponent(
            "apps/ios/Merian"
        )
        let sources = try Dictionary(uniqueKeysWithValues: swiftFiles(below: productionRoot).map {
            (
                $0.path.replacingOccurrences(
                    of: productionRoot.path + "/",
                    with: ""
                ),
                try String(contentsOf: $0, encoding: .utf8)
            )
        })

        for (declaration, expectedFilename) in Self.declarationOwners {
            let owners = Set(sources.compactMap { path, source in
                source.contains(declaration) ? path : nil
            })
            #expect(
                owners == Set([
                    "Core/Network/Models/FieldTrips/\(expectedFilename)"
                ]),
                "Unexpected owner for \(declaration)"
            )
        }
    }

    @Test func presentationPersistenceAndCrossFeatureRoutesHaveFocusedOwners() throws {
        let root = try repositoryRoot()
        let lifecycle = try source(
            "apps/ios/Merian/Features/Explore/FieldTrips/Models/FieldTripLifecyclePresentation.swift",
            below: root
        )
        let guide = try source(
            "apps/ios/Merian/Features/Explore/FieldTrips/Models/FieldTripGuidePresentation.swift",
            below: root
        )
        let publication = try source(
            "apps/ios/Merian/Features/Explore/FieldTrips/Models/FieldTripPublicationPresentation.swift",
            below: root
        )
        let insight = try source(
            "apps/ios/Merian/Features/Insights/Shell/Models/FieldTripScanContributionPresentation.swift",
            below: root
        )
        let preferenceStore = try source(
            "apps/ios/Merian/Core/Preferences/Stores/FirstFieldTripAchievementProgressStore.swift",
            below: root
        )
        let achievementPolicy = try source(
            "apps/ios/Merian/Core/UI/Feedback/Policies/FirstFieldTripAchievementPolicy.swift",
            below: root
        )
        let communityQuery = try source(
            "apps/ios/Merian/Core/Network/Models/FieldTrips/FieldTripCommunityQueryModels.swift",
            below: root
        )
        let communityPresentation = try source(
            "apps/ios/Merian/Features/Explore/FieldTrips/Models/FieldTripCommunityModePresentation.swift",
            below: root
        )
        let profilePresentation = try source(
            "apps/ios/Merian/Features/Explore/FieldTrips/Models/FieldTripProfilePresentation.swift",
            below: root
        )
        let progressPresentation = try source(
            "apps/ios/Merian/Core/UI/Feedback/Policies/FieldTripProgressPresentation.swift",
            below: root
        )
        let wireTests = try source(
            "apps/ios/MerianTests/Core/Network/FieldTripAPIModelsTests.swift",
            below: root
        )
        let featurePresentationTests = try source(
            "apps/ios/MerianTests/Features/Explore/FieldTrips/FieldTripModelPresentationTests.swift",
            below: root
        )
        let insightTests = try source(
            "apps/ios/MerianTests/Features/Insights/Shell/InsightFieldTripContributionTests.swift",
            below: root
        )
        let milestoneTests = try source(
            "apps/ios/MerianTests/Core/UI/MilestoneAchievementPolicyTests.swift",
            below: root
        )
        let preferenceTests = try source(
            "apps/ios/MerianTests/Core/Preferences/FirstFieldTripProgressStoreTests.swift",
            below: root
        )
        let authorProfileTests = try source(
            "apps/ios/MerianTests/Features/Explore/AuthorProfile/ExploreAuthorProfilePresentationTests.swift",
            below: root
        )

        #expect(lifecycle.contains("extension FieldTripTemplate"))
        #expect(lifecycle.contains("extension FieldTripProgress"))
        #expect(lifecycle.contains("extension FieldTripChallenge"))
        #expect(guide.contains("extension FieldTripChecklistItem"))
        #expect(publication.contains("extension FieldTripRecentPublication"))
        #expect(publication.contains("var communityReasonLabel: String?"))
        #expect(!communityQuery.contains("var title: String"))
        #expect(communityPresentation.contains("extension FieldTripCommunityMode"))
        #expect(communityPresentation.contains("var title: String"))
        #expect(profilePresentation.contains("extension FieldTripProfileSummaries"))
        #expect(progressPresentation.contains("enum FieldTripProgressPresentation"))
        #expect(progressPresentation.contains("var toastCompletedCount: Int"))
        #expect(insight.contains("extension FieldTripScanContribution"))
        #expect(insight.contains("var destination: CaptureGoalDestination?"))
        #expect(preferenceStore.contains("enum FirstFieldTripAchievementProgressStore"))
        #expect(achievementPolicy.contains("enum FirstFieldTripAchievementPolicy"))
        #expect(achievementPolicy.contains("extension FirstFieldTripAchievementProgress"))
        #expect(achievementPolicy.contains("extension Array where Element == AwardPayload"))
        for forbiddenToken in Self.forbiddenWireTestTokens {
            #expect(
                !wireTests.contains(forbiddenToken),
                "FieldTripAPIModelsTests must not assert \(forbiddenToken)"
            )
        }
        #expect(featurePresentationTests.contains("struct FieldTripModelPresentationTests"))
        #expect(featurePresentationTests.contains("communityModesRetainVisibleTitles"))
        #expect(featurePresentationTests.contains("guidePresentationPrefersStructuredContent"))
        #expect(featurePresentationTests.contains("lifecyclePresentationRetainsProgress"))
        #expect(featurePresentationTests.contains("publicationPresentationRetainsAuthor"))
        #expect(insightTests.contains("standard.destination == .fieldTrip"))
        #expect(milestoneTests.contains("fieldTripProgressPresentationPrefersCreditedLevelCounts"))
        #expect(!milestoneTests.contains("FirstFieldTripAchievementProgressStore."))
        #expect(preferenceTests.contains("roundTripsWithinTheNormalizedAccountBoundary"))
        #expect(preferenceTests.contains("rejectsProgressWithoutAValidAwardProjection"))
        #expect(authorProfileTests.contains("testPublicFirstFieldTripAwardDoesNotExposePrivateDestination"))
    }

    private static let expectedModelFilenames: Set<String> = [
        "FieldTripAchievementAPIModels.swift",
        "FieldTripCaptureAPIModels.swift",
        "FieldTripCatalogAPIModels.swift",
        "FieldTripChallengeAPIModels.swift",
        "FieldTripCommunityQueryModels.swift",
        "FieldTripProfileAPIModels.swift",
        "FieldTripProgressAPIModels.swift",
        "FieldTripPublicationAPIModels.swift"
    ]

    private static let declarationOwners: [String: String] = [
        "struct FirstFieldTripAchievementProgress:": "FieldTripAchievementAPIModels.swift",
        "struct FirstFieldTripAwardResponse:": "FieldTripAchievementAPIModels.swift",
        "struct FieldTripCaptureContextResponse:": "FieldTripCaptureAPIModels.swift",
        "struct FieldTripCaptureOuting:": "FieldTripCaptureAPIModels.swift",
        "struct FieldTripCaptureTarget:": "FieldTripCaptureAPIModels.swift",
        "struct FieldTripPreferredGoal:": "FieldTripCaptureAPIModels.swift",
        "struct FieldTripScanContribution:": "FieldTripCaptureAPIModels.swift",
        "struct FieldTripScanContributionsResponse:": "FieldTripCaptureAPIModels.swift",
        "struct FieldTripsCatalogResponse:": "FieldTripCatalogAPIModels.swift",
        "struct FieldTripTemplateDetailResponse:": "FieldTripCatalogAPIModels.swift",
        "struct FieldTripStartResponse:": "FieldTripCatalogAPIModels.swift",
        "struct FieldTripTemplate:": "FieldTripCatalogAPIModels.swift",
        "struct FieldTripLevel:": "FieldTripCatalogAPIModels.swift",
        "struct FieldTripChecklistItem:": "FieldTripCatalogAPIModels.swift",
        "struct FieldTripReferenceSpecies:": "FieldTripCatalogAPIModels.swift",
        "struct FieldTripChecklistItemGuide:": "FieldTripCatalogAPIModels.swift",
        "struct FieldTripChallengesCatalogResponse:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengeDetailResponse:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengePublicationsResponse:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengeEntryDetailResponse:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengeEntryLikeResponse:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengeHashtagsResponse:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallenge:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengeParticipation:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengeEntry:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengeEntryDetail:": "FieldTripChallengeAPIModels.swift",
        "struct FieldTripChallengeEntryItem:": "FieldTripChallengeAPIModels.swift",
        "enum FieldTripCommunityMode:": "FieldTripCommunityQueryModels.swift",
        "struct FieldTripProfileSummariesResponse:": "FieldTripProfileAPIModels.swift",
        "struct FieldTripSetPinnedPublicationsResponse:": "FieldTripProfileAPIModels.swift",
        "struct FieldTripProfileSummaries:": "FieldTripProfileAPIModels.swift",
        "struct FieldTripChallengeBadge:": "FieldTripProfileAPIModels.swift",
        "struct FieldTripProfileActiveSummary:": "FieldTripProfileAPIModels.swift",
        "struct FieldTripProfilePublishedSummary:": "FieldTripProfileAPIModels.swift",
        "struct FieldTripProgressUpdatesResponse:": "FieldTripProgressAPIModels.swift",
        "struct FieldTripProgressResult:": "FieldTripProgressAPIModels.swift",
        "struct FieldTripProgress:": "FieldTripProgressAPIModels.swift",
        "struct FieldTripProgressUpdate:": "FieldTripProgressAPIModels.swift",
        "struct FieldTripProgressCompletedItem:": "FieldTripProgressAPIModels.swift",
        "struct FieldTripChallengeProgressUpdate:": "FieldTripProgressAPIModels.swift",
        "struct FieldTripRecentPublicationsResponse:": "FieldTripPublicationAPIModels.swift",
        "struct FieldTripCommunityPublicationsResponse:": "FieldTripPublicationAPIModels.swift",
        "struct FieldTripPublicationDetailResponse:": "FieldTripPublicationAPIModels.swift",
        "struct FieldTripCommentsResponse:": "FieldTripPublicationAPIModels.swift",
        "struct FieldTripCreateCommentResponse:": "FieldTripPublicationAPIModels.swift",
        "struct FieldTripLikeResponse:": "FieldTripPublicationAPIModels.swift",
        "struct FieldTripRecentPublication:": "FieldTripPublicationAPIModels.swift",
        "struct FieldTripPublicationDetail:": "FieldTripPublicationAPIModels.swift",
        "struct FieldTripPublicationItem:": "FieldTripPublicationAPIModels.swift"
    ]

    private static let forbiddenModelTokens = [
        "@Observable",
        "AwardPayload",
        "CaptureGoalDestination",
        "MerianNetworkClient",
        "ModelContext(",
        "SupabaseManager",
        "Task {",
        "Task.detached",
        "URLSession",
        "UserDefaults",
        "communityReasonLabel",
        "var completionDate:",
        "var destination: CaptureGoalDestination",
        "var fractionComplete:",
        "var isComplete:",
        "var isEmpty:",
        "var isPublished:",
        "var isStopped:",
        "var toastCompletedCount:",
        "var toastTargetCount:",
        "guidePreview",
        "import Observation",
        "import Supabase",
        "import SwiftData",
        "import SwiftUI",
        "publicAuthorDisplayName",
        "static let shared"
    ]

    private static let forbiddenWireTestTokens = [
        ".awardPayload",
        ".catalogState",
        ".communityReasonLabel",
        ".destination ==",
        ".fractionComplete",
        ".guidePreview",
        ".isPublished",
        ".isStopped",
        ".publicAuthorDisplayName",
        ".toastCompletedCount",
        ".toastTargetCount",
        ".viewerProgress",
        "ExploreAuthorProfileAward"
    ]

    private func swiftFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func swiftFiles(below directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        return try enumerator.compactMap { element in
            guard let file = element as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(
                      forKeys: [.isRegularFileKey]
                  ).isRegularFile == true else {
                return nil
            }
            return file
        }
        .sorted { $0.path < $1.path }
    }

    private func source(_ path: String, below root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func lineCount(_ source: String) -> Int {
        guard !source.isEmpty else { return 0 }
        let count = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        return count - (source.hasSuffix("\n") ? 1 : 0)
    }

    private func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("project.yml").path
            ) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
