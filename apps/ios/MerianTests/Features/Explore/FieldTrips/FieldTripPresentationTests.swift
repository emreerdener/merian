import Foundation
@testable import Merian
import Testing

struct FieldTripPresentationTests {
    @Test func difficultyNormalizesKnownValuesAndPreservesUnknownValues() {
        #expect(FieldTripDifficulty(apiValue: "starter") == .starter)
        #expect(FieldTripDifficulty(apiValue: " EASY ") == .easy)
        #expect(FieldTripDifficulty(apiValue: "Moderate") == .moderate)
        #expect(FieldTripDifficulty(apiValue: "HARD\n") == .hard)
        #expect(FieldTripDifficulty(apiValue: "expert") == nil)

        let unknownTemplate = makeTemplate(id: "expert", difficulty: "expert_level")
        #expect(unknownTemplate.resolvedDifficulty == nil)
        #expect(unknownTemplate.difficultyTitle == "Expert Level")
    }

    @Test func backyardSafariPresentationUsesCanonicalCopyAndBundledCover() {
        #expect(
            FieldTripTemplatePresentation.title(
                "Backyard Safari",
                slug: "backyard_safari"
            ) == "Backyard Safari"
        )
        #expect(
            FieldTripTemplatePresentation.title(
                "Backyard safari",
                slug: "backyard_safari"
            ) == "Backyard Safari"
        )
        #expect(
            FieldTripTemplatePresentation.title(
                "Park Pollinators",
                slug: "park_pollinators"
            ) == "Park Pollinators"
        )
        #expect(
            FieldTripTemplatePresentation.bundledCoverImageName(for: "backyard_safari")
                == "fieldtrip-backyard-safari"
        )
        #expect(FieldTripTemplatePresentation.bundledCoverImageName(for: "park_pollinators") == nil)
    }

    @Test func backyardSafariCardPresentationTracksCurrentLevelProgress() {
        let unstarted = makeCardTemplate()
        let activeLevelTwo = makeCardTemplate(
            activeProgress: makeCardProgress(
                currentLevelNumber: 2,
                completedCount: 2,
                targetCount: 6
            ),
            secondLevelPrompts: ["Flower", "Fungus", "Dog", "Bee", "Squirrel", "Moss"]
        )
        let stoppedLevelTwo = makeCardTemplate(
            stoppedProgress: makeCardProgress(
                currentLevelNumber: 2,
                completedCount: 3,
                targetCount: 6,
                stoppedAt: "2026-07-18T12:30:00Z"
            ),
            secondLevelPrompts: ["Flower", "Fungus", "Dog", "Bee", "Squirrel", "Moss"]
        )

        #expect(FieldTripTemplatePresentation.completedCount(for: unstarted) == 0)
        #expect(FieldTripTemplatePresentation.targetCount(for: unstarted) == 4)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: unstarted) == "Level 1")
        #expect(
            FieldTripTemplatePresentation.subtitle(for: unstarted) ==
                "Observe 4 local species often found in your own backyard."
        )

        #expect(FieldTripTemplatePresentation.completedCount(for: activeLevelTwo) == 2)
        #expect(FieldTripTemplatePresentation.targetCount(for: activeLevelTwo) == 6)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: activeLevelTwo) == "Level 2")
        #expect(
            FieldTripTemplatePresentation.subtitle(for: activeLevelTwo) ==
                "Observe 6 local species often found in your own backyard."
        )

        #expect(FieldTripTemplatePresentation.completedCount(for: stoppedLevelTwo) == 3)
        #expect(FieldTripTemplatePresentation.targetCount(for: stoppedLevelTwo) == 6)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: stoppedLevelTwo) == "Level 2")
    }

    @Test func fieldTripCardPresentationHandlesCompletionAndMissingLevels() {
        let completed = makeCardTemplate(
            activeProgress: makeCardProgress(
                isComplete: true,
                currentLevelNumber: 2,
                completedCount: 6,
                targetCount: 6
            ),
            secondLevelPrompts: ["Flower", "Fungus", "Dog", "Bee", "Squirrel", "Moss"]
        )
        let missingLevels = makeCardTemplate(
            activeProgress: makeCardProgress(
                currentLevelNumber: 2,
                completedCount: 1,
                targetCount: 6
            ),
            prompts: []
        )
        let empty = makeCardTemplate(prompts: [])
        let other = makeTemplate(
            id: "park_pollinators",
            difficulty: "easy",
            subtitle: "Flowers and their pollinators."
        )

        #expect(FieldTripTemplatePresentation.completedCount(for: completed) == 6)
        #expect(FieldTripTemplatePresentation.targetCount(for: completed) == 6)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: completed) == "Level 2")
        #expect(FieldTripTemplatePresentation.targetCount(for: missingLevels) == 6)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: missingLevels) == "Level 2")
        #expect(FieldTripTemplatePresentation.targetCount(for: empty) == 0)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: empty) == "Level 1")
        #expect(
            FieldTripTemplatePresentation.subtitle(for: empty) ==
                FieldTripTemplatePresentation.backyardSafariSubtitle
        )
        #expect(
            FieldTripTemplatePresentation.subtitle(for: other) ==
                "Flowers and their pollinators."
        )
    }

    @Test func fieldTripStatusAndDetailTagsPreserveLifecycleAndMetadata() {
        let locked = makeCardTemplate(viewerHasAccess: false, isProOnly: true)
        let privateActive = makeCardTemplate(
            activeProgress: makeCardProgress(completedCount: 0, targetCount: 4)
        )
        let stopped = makeCardTemplate(
            stoppedProgress: makeCardProgress(
                completedCount: 0,
                targetCount: 4,
                stoppedAt: "2026-07-18T12:30:00Z"
            )
        )
        let completed = makeCardTemplate(
            activeProgress: makeCardProgress(
                isComplete: true,
                completedCount: 4,
                targetCount: 4
            )
        )
        let published = makeCardTemplate(
            activeProgress: makeCardProgress(
                isComplete: true,
                completedCount: 4,
                targetCount: 4,
                publicationId: "publication-backyard"
            )
        )

        #expect(
            FieldTripTemplatePresentation.status(for: locked) ==
                FieldTripTemplateStatusPresentation(kind: .notStarted, title: "Not started")
        )
        #expect(
            FieldTripTemplatePresentation.status(for: privateActive) ==
                FieldTripTemplateStatusPresentation(kind: .active, title: "Active")
        )
        #expect(
            FieldTripTemplatePresentation.status(for: stopped) ==
                FieldTripTemplateStatusPresentation(kind: .stopped, title: "Stopped")
        )
        #expect(
            FieldTripTemplatePresentation.status(for: completed) ==
                FieldTripTemplateStatusPresentation(kind: .completed, title: "Completed")
        )

        let locatedTags = FieldTripTemplatePresentation.detailTags(
            for: locked,
            locationLabel: " Austin, TX "
        )
        let unlocatedTags = FieldTripTemplatePresentation.detailTags(
            for: locked,
            locationLabel: "   "
        )

        let expectedLocatedKinds: [FieldTripTemplateTagPresentation.Kind] = [
            .access, .difficulty, .level, .location
        ]
        let expectedUnlocatedKinds: [FieldTripTemplateTagPresentation.Kind] = [
            .access, .difficulty, .level
        ]

        #expect(locatedTags.map(\.kind) == expectedLocatedKinds)
        #expect(
            locatedTags.map(\.title) == [
                "Pro", "Starter", "Level 1", "Austin, TX"
            ]
        )
        #expect(
            locatedTags.first(where: { $0.kind == .access })?.systemImage ==
                "lock.fill"
        )
        #expect(unlocatedTags.map(\.kind) == expectedUnlocatedKinds)
        #expect(unlocatedTags.allSatisfy { $0.kind != .visibility })
        let privateActiveTags = FieldTripTemplatePresentation.detailTags(
            for: privateActive,
            locationLabel: nil
        )
        #expect(
            privateActiveTags.map(\.title) == [
                "Starter", "Level 1"
            ]
        )
        #expect(privateActiveTags.allSatisfy { $0.kind != .visibility })
        let stoppedTags = FieldTripTemplatePresentation.detailTags(
            for: stopped,
            locationLabel: nil
        )
        #expect(
            stoppedTags.map(\.title) == [
                "Starter", "Level 1"
            ]
        )
        #expect(stoppedTags.allSatisfy { $0.kind != .visibility })
        let completedTags = FieldTripTemplatePresentation.detailTags(
            for: completed,
            locationLabel: nil
        )
        #expect(
            completedTags.map(\.title) == [
                "Starter", "Level 1"
            ]
        )
        #expect(completedTags.allSatisfy { $0.kind != .visibility })
        let publishedTags = FieldTripTemplatePresentation.detailTags(
            for: published,
            locationLabel: nil
        )
        #expect(
            publishedTags.map(\.title) == [
                "Starter", "Level 1"
            ]
        )
        #expect(publishedTags.allSatisfy { $0.kind != .visibility })

        let sharingEnabledPrivateTags = FieldTripTemplatePresentation.detailTags(
            for: privateActive,
            locationLabel: nil,
            sharingEnabled: true
        )
        #expect(
            sharingEnabledPrivateTags.map(\.title) == [
                "Private", "Starter", "Level 1"
            ]
        )
        #expect(
            sharingEnabledPrivateTags.first(where: { $0.kind == .visibility })?.systemImage ==
                "eye.slash.fill"
        )

        let sharingEnabledPublishedTags = FieldTripTemplatePresentation.detailTags(
            for: published,
            locationLabel: nil,
            sharingEnabled: true
        )
        #expect(
            sharingEnabledPublishedTags.map(\.title) == [
                "Published", "Starter", "Level 1"
            ]
        )
        #expect(
            sharingEnabledPublishedTags.first(where: { $0.kind == .visibility })?.systemImage ==
                "eye.fill"
        )
    }

    @Test func fieldTripCatalogActionInvitesOnlyNotStartedOutingsToGetStarted() {
        let notStarted = FieldTripTemplateStatusPresentation(
            kind: .notStarted,
            title: "Not started"
        )
        #expect(notStarted.catalogActionTitle == "Get started")

        let viewingKinds: [FieldTripTemplateStatusPresentation.Kind] = [
            .active,
            .stopped,
            .completed,
            .locked
        ]
        for kind in viewingKinds {
            let status = FieldTripTemplateStatusPresentation(kind: kind, title: "Status")
            #expect(status.catalogActionTitle == "View field trip")
        }
    }

    @Test func fieldTripCatalogPreviewUsesTwoUpLayoutOnlyForTwoTargets() {
        #expect(
            FieldTripScanPreviewPresentationMode.compactScrollable
                .resolvedLayout(forTargetCount: 2) == .fixedScrollable
        )
        #expect(
            FieldTripScanPreviewPresentationMode.responsiveCatalog
                .resolvedLayout(forTargetCount: -1) == .fixedScrollable
        )
        #expect(
            FieldTripScanPreviewPresentationMode.responsiveCatalog
                .resolvedLayout(forTargetCount: 1) == .fixedScrollable
        )
        #expect(
            FieldTripScanPreviewPresentationMode.responsiveCatalog
                .resolvedLayout(forTargetCount: 2) == .equalWidthTwoUp
        )
        #expect(
            FieldTripScanPreviewPresentationMode.responsiveCatalog
                .resolvedLayout(forTargetCount: 3) == .fixedScrollable
        )
    }

    @Test func difficultyFilteringPreservesCatalogOrderAndKeepsUnknownValuesInAll() {
        let templates = [
            makeTemplate(id: "starter", difficulty: " STARTER "),
            makeTemplate(id: "unknown", difficulty: "expert"),
            makeTemplate(id: "easy", difficulty: "easy"),
            makeTemplate(id: "moderate", difficulty: "moderate"),
            makeTemplate(id: "hard", difficulty: "hard")
        ]

        #expect(templates.filtering(by: nil).map(\.templateId) == [
            "starter",
            "unknown",
            "easy",
            "moderate",
            "hard"
        ])
        #expect(templates.filtering(by: .starter).map(\.templateId) == ["starter"])
        #expect(templates.filtering(by: .easy).map(\.templateId) == ["easy"])
        #expect(templates.filtering(by: .moderate).map(\.templateId) == ["moderate"])
        #expect(templates.filtering(by: .hard).map(\.templateId) == ["hard"])
    }

    @Test func catalogStateDistinguishesUnstartedInProgressAndCompletedOutings() {
        let unstarted = makeTemplate(id: "unstarted", difficulty: "starter")
        let startedAtZero = makeTemplate(
            id: "started-zero",
            difficulty: "easy",
            activeProgress: makeProgress(id: "progress-zero", completedCount: 0)
        )
        let partiallyCompleted = makeTemplate(
            id: "partial",
            difficulty: "moderate",
            activeProgress: makeProgress(id: "progress-partial", completedCount: 2)
        )
        let completed = makeTemplate(
            id: "completed",
            difficulty: "hard",
            activeProgress: makeProgress(
                id: "progress-completed",
                completedCount: 4,
                completedAt: "2026-07-18T20:00:00Z"
            )
        )

        #expect(unstarted.catalogState == .incomplete)
        #expect(startedAtZero.catalogState == .inProgress)
        #expect(partiallyCompleted.catalogState == .inProgress)
        #expect(completed.catalogState == .completed)
    }

    @Test func lifecyclePresentationDistinguishesActiveStoppedAndTerminalOutings() {
        let unstarted = makeTemplate(id: "unstarted", difficulty: "starter")
        let activeProgress = makeProgress(id: "active", completedCount: 1)
        let active = makeTemplate(
            id: "active",
            difficulty: "starter",
            activeProgress: activeProgress
        )
        let stopped = makeTemplate(
            id: "stopped",
            difficulty: "starter",
            stoppedProgress: FieldTripProgress(
                userFieldTripId: "stopped",
                startedAt: activeProgress.startedAt,
                currentLevelNumber: activeProgress.currentLevelNumber,
                completedAt: nil,
                isProfileVisible: true,
                completedCount: 1,
                targetCount: 4,
                publicationId: nil,
                publishedAt: nil,
                stoppedAt: "2026-07-19T10:00:00Z"
            )
        )
        let completed = makeTemplate(
            id: "completed",
            difficulty: "starter",
            activeProgress: makeProgress(
                id: "completed",
                completedCount: 4,
                completedAt: "2026-07-19T10:00:00Z"
            )
        )

        #expect(FieldTripDetailLifecyclePresentation.primaryAction(for: unstarted) == .start)
        #expect(!FieldTripDetailLifecyclePresentation.showsOptionsMenu(unstarted))
        #expect(FieldTripDetailLifecyclePresentation.primaryAction(for: active) == .scan)
        #expect(FieldTripDetailLifecyclePresentation.canStop(active))
        #expect(FieldTripDetailLifecyclePresentation.canReset(active))
        #expect(FieldTripDetailLifecyclePresentation.primaryAction(for: stopped) == .resume)
        #expect(!FieldTripDetailLifecyclePresentation.canStop(stopped))
        #expect(FieldTripDetailLifecyclePresentation.canReset(stopped))
        #expect(FieldTripDetailLifecyclePresentation.primaryAction(for: completed) == nil)
        #expect(
            FieldTripDetailLifecyclePresentation.primaryAction(
                for: completed,
                sharingEnabled: true
            ) == .publish
        )
        #expect(!FieldTripDetailLifecyclePresentation.showsOptionsMenu(completed))
    }

    @Test func stateFilteringIsSingleSelectAndPreservesCatalogOrder() {
        let templates = [
            makeTemplate(id: "unstarted-1", difficulty: "starter"),
            makeTemplate(
                id: "started-zero",
                difficulty: "easy",
                activeProgress: makeProgress(id: "progress-zero", completedCount: 0)
            ),
            makeTemplate(
                id: "completed-1",
                difficulty: "moderate",
                activeProgress: makeProgress(
                    id: "progress-completed-1",
                    completedCount: 4,
                    completedAt: "2026-07-18T20:00:00Z"
                )
            ),
            makeTemplate(id: "unstarted-2", difficulty: "hard"),
            makeTemplate(
                id: "partial",
                difficulty: "starter",
                activeProgress: makeProgress(id: "progress-partial", completedCount: 2)
            ),
            makeTemplate(
                id: "completed-2",
                difficulty: "easy",
                activeProgress: makeProgress(
                    id: "progress-completed-2",
                    completedCount: 4,
                    completedAt: "2026-07-18T21:00:00Z"
                )
            )
        ]
        var filters = FieldTripCatalogFilters()

        #expect(templates.filtering(by: filters).map(\.templateId) == [
            "unstarted-1",
            "started-zero",
            "completed-1",
            "unstarted-2",
            "partial",
            "completed-2"
        ])

        filters.state = .incomplete
        #expect(templates.filtering(by: filters).map(\.templateId) == ["unstarted-1", "unstarted-2"])

        filters.state = .inProgress
        #expect(templates.filtering(by: filters).map(\.templateId) == ["started-zero", "partial"])

        filters.state = .completed
        #expect(templates.filtering(by: filters).map(\.templateId) == ["completed-1", "completed-2"])
    }

    @Test func catalogFiltersCombineWithAndSemanticsCountGroupsAndReset() {
        let templates = [
            makeTemplate(
                id: "starter-progress",
                difficulty: "starter",
                activeProgress: makeProgress(id: "starter-progress", completedCount: 1)
            ),
            makeTemplate(
                id: "easy-progress",
                difficulty: "easy",
                activeProgress: makeProgress(id: "easy-progress", completedCount: 0)
            ),
            makeTemplate(
                id: "easy-completed",
                difficulty: "easy",
                activeProgress: makeProgress(
                    id: "easy-completed",
                    completedCount: 4,
                    completedAt: "2026-07-18T22:00:00Z"
                )
            ),
            makeTemplate(id: "unknown-unstarted", difficulty: "expert")
        ]
        var filters = FieldTripCatalogFilters()

        #expect(filters.activeFilterCount == 0)
        #expect(!filters.hasActiveFilters)

        filters.difficulty = .easy
        #expect(filters.activeFilterCount == 1)
        #expect(filters.hasActiveFilters)

        filters.state = .inProgress
        #expect(filters.activeFilterCount == 2)
        #expect(templates.filtering(by: filters).map(\.templateId) == ["easy-progress"])

        filters.reset()
        #expect(filters == FieldTripCatalogFilters())
        #expect(filters.activeFilterCount == 0)
        #expect(templates.filtering(by: filters).map(\.templateId) == [
            "starter-progress",
            "easy-progress",
            "easy-completed",
            "unknown-unstarted"
        ])
    }

    private func makeCardTemplate(
        viewerHasAccess: Bool = true,
        isProOnly: Bool = false,
        activeProgress: FieldTripProgress? = nil,
        stoppedProgress: FieldTripProgress? = nil,
        prompts: [String] = ["Butterfly", "Bird", "Cat", "Spider"],
        secondLevelPrompts: [String] = []
    ) -> FieldTripTemplate {
        var levels: [FieldTripLevel] = []
        if !prompts.isEmpty {
            levels.append(makeCardLevel(number: 1, prompts: prompts))
        }
        if !secondLevelPrompts.isEmpty {
            levels.append(makeCardLevel(number: 2, prompts: secondLevelPrompts))
        }

        return FieldTripTemplate(
            templateId: "template-backyard-card",
            slug: "backyard_safari",
            title: "Backyard Safari",
            subtitle: FieldTripTemplatePresentation.backyardSafariSubtitle,
            description: "Find familiar animals and small wild neighbors.",
            coverImageUrl: nil,
            estimatedDurationMinutes: 30,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: ["global"],
            seasonTags: ["spring", "summer", "fall"],
            habitatTags: ["urban", "yard"],
            difficulty: "starter",
            isProOnly: isProOnly,
            isRotatingFree: !isProOnly,
            viewerHasAccess: viewerHasAccess,
            accessKind: viewerHasAccess ? "free" : (isProOnly ? "pro" : "locked"),
            activeProgress: activeProgress,
            stoppedProgress: stoppedProgress,
            levels: levels
        )
    }

    private func makeCardProgress(
        isComplete: Bool = false,
        currentLevelNumber: Int = 1,
        completedCount: Int,
        targetCount: Int,
        publicationId: String? = nil,
        stoppedAt: String? = nil
    ) -> FieldTripProgress {
        FieldTripProgress(
            userFieldTripId: "outing-backyard-card",
            startedAt: "2026-07-18T12:00:00Z",
            currentLevelNumber: currentLevelNumber,
            completedAt: isComplete ? "2026-07-18T13:00:00Z" : nil,
            isProfileVisible: false,
            completedCount: completedCount,
            targetCount: targetCount,
            publicationId: publicationId,
            publishedAt: publicationId == nil ? nil : "2026-07-18T13:00:00Z",
            stoppedAt: stoppedAt
        )
    }

    private func makeCardLevel(
        number: Int,
        prompts: [String]
    ) -> FieldTripLevel {
        FieldTripLevel(
            levelId: "card-level-\(number)",
            levelNumber: number,
            title: "Level \(number)",
            description: nil,
            items: prompts.enumerated().map { index, prompt in
                FieldTripChecklistItem(
                    itemId: "card-item-\(number)-\(index)",
                    prompt: prompt,
                    matchType: "taxonomy",
                    guideTip: nil,
                    guide: nil,
                    referenceSpecies: nil,
                    isCompleted: false,
                    completedAt: nil,
                    completedCommonName: nil,
                    completedScientificName: nil,
                    completedScanId: nil
                )
            }
        )
    }

    private func makeTemplate(
        id: String,
        difficulty: String,
        subtitle: String? = nil,
        activeProgress: FieldTripProgress? = nil,
        stoppedProgress: FieldTripProgress? = nil
    ) -> FieldTripTemplate {
        return FieldTripTemplate(
            templateId: id,
            slug: id,
            title: id.capitalized,
            subtitle: subtitle,
            description: nil,
            coverImageUrl: nil,
            estimatedDurationMinutes: nil,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: [],
            seasonTags: [],
            habitatTags: [],
            difficulty: difficulty,
            isProOnly: false,
            isRotatingFree: false,
            viewerHasAccess: true,
            accessKind: "free",
            activeProgress: activeProgress,
            stoppedProgress: stoppedProgress,
            levels: []
        )
    }

    private func makeProgress(
        id: String,
        completedCount: Int,
        targetCount: Int = 4,
        completedAt: String? = nil
    ) -> FieldTripProgress {
        FieldTripProgress(
            userFieldTripId: id,
            startedAt: "2026-07-18T19:00:00Z",
            currentLevelNumber: 1,
            completedAt: completedAt,
            isProfileVisible: true,
            completedCount: completedCount,
            targetCount: targetCount,
            publicationId: nil,
            publishedAt: nil,
            stoppedAt: nil
        )
    }

}
