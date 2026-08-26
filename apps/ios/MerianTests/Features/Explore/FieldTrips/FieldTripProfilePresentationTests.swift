import Foundation
@testable import Merian
import Testing

struct ActiveFieldTripProfilePresentationTests {
    @Test func activeProfileOrdersOldestStartedFirstAndFiltersUnavailableOrCompletedTrips() {
        let templates = [
            makeTemplate(id: "pollinators", startedAt: "2026-07-18T20:00:00Z"),
            makeTemplate(id: "locked", viewerHasAccess: false),
            makeTemplate(id: "backyard", startedAt: "2026-07-18T18:00:00Z"),
            makeTemplate(id: "completed", isComplete: true),
            makeTemplate(id: "fungi", startedAt: "2026-07-18T22:00:00Z")
        ]

        let items = ActiveFieldTripProfilePresentation.items(
            templates: templates
        )

        #expect(items.map(\.id) == ["backyard", "pollinators", "fungi"])
        #expect(
            ActiveFieldTripProfilePresentation.previewItems(from: items).map(\.id) ==
                ["backyard"]
        )
        #expect(ActiveFieldTripProfilePresentation.shouldShowViewAll(for: items))
        #expect(!ActiveFieldTripProfilePresentation.shouldShowViewAll(for: Array(items.prefix(1))))
    }

    @Test func activeProfileUsesTheCurrentLevelItemsIncludingCompletedScanLinks() throws {
        let template = makeTemplate(
            id: "recent",
            levelNumber: 2,
            completedScanId: "scan-1"
        )

        let item = try #require(
            ActiveFieldTripProfilePresentation.items(
                templates: [template]
            ).first
        )

        #expect(item.currentLevelItems.map(\.prompt) == ["Bird"])
        #expect(item.currentLevelItems.first?.completedScanId == "scan-1")
    }

    @Test func activeCatalogProgressProducesCardsInStartedOrder() {
        let templates = [
            makeTemplate(id: "older", startedAt: "2026-07-18T18:00:00Z"),
            makeTemplate(id: "recent", startedAt: "2026-07-18T20:00:00Z")
        ]

        let items = ActiveFieldTripProfilePresentation.items(
            templates: templates
        )

        #expect(items.map(\.id) == ["older", "recent"])
        #expect(items.first?.completedCount == 1)
        #expect(items.first?.targetCount == 4)
        #expect(items.first?.currentLevelItems.map(\.prompt) == ["Bird"])
    }

    @Test func completedThumbnailFallsBackToTripWhenTheScanIsNotAvailableLocally() {
        #expect(
            FieldTripScanPreviewAction.resolve(
                completedScanId: "scan-1",
                hasLocalScan: false
            ) == .openTemplate
        )
        #expect(
            FieldTripScanPreviewAction.resolve(
                completedScanId: "scan-1",
                hasLocalScan: true
            ) == .openCompletedScan("scan-1")
        )
        #expect(
            FieldTripScanPreviewAction.resolve(
                completedScanId: nil,
                hasLocalScan: true
            ) == .openTemplate
        )
    }

    private func makeTemplate(
        id: String,
        viewerHasAccess: Bool = true,
        isComplete: Bool = false,
        levelNumber: Int = 1,
        completedScanId: String? = nil,
        startedAt: String = "2026-07-18T19:00:00Z"
    ) -> FieldTripTemplate {
        let outingId = id
        return FieldTripTemplate(
            templateId: "template-\(id)",
            slug: id,
            title: id.capitalized,
            subtitle: nil,
            description: nil,
            coverImageUrl: nil,
            estimatedDurationMinutes: nil,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: [],
            seasonTags: [],
            habitatTags: [],
            difficulty: "starter",
            isProOnly: false,
            isRotatingFree: false,
            viewerHasAccess: viewerHasAccess,
            accessKind: viewerHasAccess ? "free" : "locked",
            activeProgress: FieldTripProgress(
                userFieldTripId: outingId,
                startedAt: startedAt,
                currentLevelNumber: levelNumber,
                completedAt: isComplete ? "2026-07-18T20:00:00Z" : nil,
                isProfileVisible: true,
                completedCount: isComplete ? 4 : 1,
                targetCount: 4,
                publicationId: nil,
                publishedAt: nil,
                stoppedAt: nil
            ),
            stoppedProgress: nil,
            levels: [
                FieldTripLevel(
                    levelId: "level-\(levelNumber)",
                    levelNumber: levelNumber,
                    title: "Level \(levelNumber)",
                    description: nil,
                    items: [
                        FieldTripChecklistItem(
                            itemId: "item-bird",
                            prompt: "Bird",
                            matchType: "taxonomy",
                            guideTip: nil,
                            guide: nil,
                            referenceSpecies: nil,
                            isCompleted: completedScanId != nil,
                            completedAt: completedScanId == nil ? nil : "2026-07-18T19:30:00Z",
                            completedCommonName: completedScanId == nil ? nil : "Northern Cardinal",
                            completedScientificName: completedScanId == nil ? nil : "Cardinalis cardinalis",
                            completedScanId: completedScanId
                        )
                    ]
                )
            ]
        )
    }
}

struct EarnedFieldTripPatchPresentationTests {
    @Test func profilePatchesIncludeFinishedLevelsAndTheFinalCompletedLevel() {
        let templates = [
            makeTemplate(
                id: "unstarted",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: nil
            ),
            makeTemplate(
                id: "level-one-in-progress",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 1
            ),
            makeTemplate(
                id: "backyard",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: 2
            ),
            makeTemplate(
                id: "park",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 2,
                isComplete: true
            ),
            makeTemplate(
                id: "unbundled",
                slug: "forest_edges",
                currentLevelNumber: 2,
                isComplete: true
            )
        ]

        let patches = EarnedFieldTripPatchPresentation.items(templates: templates)

        #expect(
            patches.map(\.imageName) == [
                "fieldtrip-backyard-level-1-patch",
                "fieldtrip-park-level-1-patch",
                "fieldtrip-park-level-2-patch"
            ]
        )
        #expect(
            patches.map(\.title) == [
                "Backyard Safari · Level 1",
                "Park Pollinators · Level 1",
                "Park Pollinators · Level 2"
            ]
        )
        #expect(
            patches.map(\.templateId) == [
                "template-backyard",
                "template-park",
                "template-park"
            ]
        )
        #expect(patches.map(\.galleryItem.id) == patches.map(\.id))
    }

    @Test func stoppedOutingRetainsPatchesForLevelsItAlreadyFinished() {
        let template = makeTemplate(
            id: "stopped-backyard",
            slug: FieldTripTemplatePresentation.backyardSafariSlug,
            currentLevelNumber: 2,
            usesStoppedProgress: true
        )

        let patches = EarnedFieldTripPatchPresentation.items(templates: [template])

        #expect(patches.map(\.imageName) == ["fieldtrip-backyard-level-1-patch"])
    }

    @Test func publicProfileSummariesIncludeOnlyLevelsTheAuthorFinished() {
        let summaries = [
            makeProfileSummary(
                id: "level-one-in-progress",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 1
            ),
            makeProfileSummary(
                id: "backyard",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: 2
            ),
            makeProfileSummary(
                id: "park",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 2,
                isComplete: true
            ),
            makeProfileSummary(
                id: "unbundled",
                slug: "forest_edges",
                currentLevelNumber: 2,
                isComplete: true
            )
        ]

        let patches = EarnedFieldTripPatchPresentation.items(profileSummaries: summaries)

        #expect(
            patches.map(\.imageName) == [
                "fieldtrip-backyard-level-1-patch",
                "fieldtrip-park-level-1-patch",
                "fieldtrip-park-level-2-patch"
            ]
        )
        #expect(
            patches.map(\.title) == [
                "Backyard Safari · Level 1",
                "Park Pollinators · Level 1",
                "Park Pollinators · Level 2"
            ]
        )
        #expect(
            patches.map(\.templateId) == [
                "template-backyard",
                "template-park",
                "template-park"
            ]
        )
    }

    @Test func completedThreeLevelOutingsIncludeTheirFinalPatches() {
        let templates = [
            makeTemplate(
                id: "backyard-complete-three",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: 3,
                isComplete: true
            ),
            makeTemplate(
                id: "park-complete-three",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 3,
                isComplete: true
            )
        ]

        #expect(
            EarnedFieldTripPatchPresentation.items(templates: templates).map(\.imageName) == [
                "fieldtrip-backyard-level-1-patch",
                "fieldtrip-backyard-level-2-patch",
                "fieldtrip-backyard-level-3-patch",
                "fieldtrip-park-level-1-patch",
                "fieldtrip-park-level-2-patch",
                "fieldtrip-park-level-3-patch"
            ]
        )

        let summaries = [
            makeProfileSummary(
                id: "backyard-complete-three",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: 3,
                isComplete: true
            ),
            makeProfileSummary(
                id: "park-complete-three",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 3,
                isComplete: true
            )
        ]

        #expect(
            EarnedFieldTripPatchPresentation.items(profileSummaries: summaries).map(\.imageName) == [
                "fieldtrip-backyard-level-1-patch",
                "fieldtrip-backyard-level-2-patch",
                "fieldtrip-backyard-level-3-patch",
                "fieldtrip-park-level-1-patch",
                "fieldtrip-park-level-2-patch",
                "fieldtrip-park-level-3-patch"
            ]
        )
    }

    private func makeProfileSummary(
        id: String,
        slug: String,
        currentLevelNumber: Int,
        isComplete: Bool = false
    ) -> FieldTripProfileActiveSummary {
        FieldTripProfileActiveSummary(
            userFieldTripId: "outing-\(id)",
            templateId: "template-\(id)",
            slug: slug,
            title: slug == FieldTripTemplatePresentation.parkPollinatorsSlug
                ? "Park Pollinators"
                : "Backyard Safari",
            startedAt: "2026-07-18T19:00:00Z",
            currentLevelNumber: currentLevelNumber,
            currentLevelTitle: "Level \(currentLevelNumber)",
            completedCount: isComplete ? 6 : 0,
            targetCount: isComplete ? 6 : 4,
            isComplete: isComplete
        )
    }

    private func makeTemplate(
        id: String,
        slug: String,
        currentLevelNumber: Int?,
        isComplete: Bool = false,
        usesStoppedProgress: Bool = false
    ) -> FieldTripTemplate {
        let progress = currentLevelNumber.map { levelNumber in
            FieldTripProgress(
                userFieldTripId: "outing-\(id)",
                startedAt: "2026-07-18T19:00:00Z",
                currentLevelNumber: levelNumber,
                completedAt: isComplete ? "2026-07-18T20:00:00Z" : nil,
                isProfileVisible: true,
                completedCount: isComplete ? 6 : 0,
                targetCount: isComplete ? 6 : 4,
                publicationId: nil,
                publishedAt: nil,
                stoppedAt: usesStoppedProgress ? "2026-07-18T20:30:00Z" : nil
            )
        }

        return FieldTripTemplate(
            templateId: "template-\(id)",
            slug: slug,
            title: slug == FieldTripTemplatePresentation.parkPollinatorsSlug
                ? "Park Pollinators"
                : "Backyard Safari",
            subtitle: nil,
            description: nil,
            coverImageUrl: nil,
            estimatedDurationMinutes: nil,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: [],
            seasonTags: [],
            habitatTags: [],
            difficulty: "starter",
            isProOnly: false,
            isRotatingFree: false,
            viewerHasAccess: true,
            accessKind: "free",
            activeProgress: usesStoppedProgress ? nil : progress,
            stoppedProgress: usesStoppedProgress ? progress : nil,
            levels: [1, 2, 3].map { levelNumber in
                FieldTripLevel(
                    levelId: "level-\(id)-\(levelNumber)",
                    levelNumber: levelNumber,
                    title: "Level \(levelNumber)",
                    description: nil,
                    items: []
                )
            }
        )
    }
}
