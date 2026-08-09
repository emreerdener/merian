import Foundation
@testable import Merian
import Testing

struct FieldTripFeaturedMediaTests {
    @Test func builderUsesReferenceUntilCompletedUserVisualReplacesTheSameGoalSlot() throws {
        let scan = makeScan(
            id: "photo",
            media: [.image(.remoteURL("https://media.merian.app/user-photo.webp"))]
        )
        let template = makeTemplate(levels: [
            makeLevel(number: 1, items: [
                makeChecklistItem(id: "bird", scanId: nil, isCompleted: false),
                makeChecklistItem(id: "cat", scanId: scan.id)
            ])
        ])

        let candidates = FieldTripFeaturedMediaBuilder.candidates(
            for: template,
            localScansById: [scan.id: scan]
        )

        #expect(candidates.map(\.id) == [
            "field-trip-featured-goal:bird",
            "field-trip-featured-goal:cat"
        ])
        #expect(candidates[0].scanId == nil)
        #expect(candidates[0].source == .reference(referenceImage(source: .merian)))
        #expect(candidates[1].scanId == scan.id)
        #expect(candidates[1].source == .userImage(
            path: "https://media.merian.app/user-photo.webp"
        ))
    }

    @Test func builderFallsBackFromUnavailableUserMediaThroughNaturebookWikipediaAndGBIF() throws {
        let userPath = "https://media.merian.app/user-photo.webp"
        let scan = makeScan(
            id: "photo",
            media: [.image(.remoteURL(userPath))]
        )
        let template = makeTemplate(levels: [
            makeLevel(number: 1, items: [makeChecklistItem(id: "bird", scanId: scan.id)])
        ])

        let naturebookFallback = try #require(FieldTripFeaturedMediaBuilder.candidates(
            for: template,
            localScansById: [scan.id: scan],
            excluding: [userPath]
        ).first)
        let wikipediaFallback = try #require(FieldTripFeaturedMediaBuilder.candidates(
            for: template,
            localScansById: [scan.id: scan],
            excluding: [userPath, referenceURL(source: .merian)]
        ).first)
        let gbifFallback = try #require(FieldTripFeaturedMediaBuilder.candidates(
            for: template,
            localScansById: [scan.id: scan],
            excluding: [
                userPath,
                referenceURL(source: .merian),
                referenceURL(source: .wikipedia)
            ]
        ).first)
        let exhausted = FieldTripFeaturedMediaBuilder.candidates(
            for: template,
            localScansById: [scan.id: scan],
            excluding: [
                userPath,
                referenceURL(source: .merian),
                referenceURL(source: .wikipedia),
                referenceURL(source: .gbif)
            ]
        )

        #expect(naturebookFallback.source == .reference(referenceImage(source: .merian)))
        #expect(wikipediaFallback.source == .reference(referenceImage(source: .wikipedia)))
        #expect(gbifFallback.source == .reference(referenceImage(source: .gbif)))
        #expect(exhausted.isEmpty)
    }

    @Test func builderMapsVideoAndLegacyCoverThenUsesReferencesForUnusableCompletedScans() {
        let video = makeScan(
            id: "video",
            media: [
                .video(StoredVideoMediaReference(
                    .remoteURL("https://media.merian.app/video.mp4"),
                    thumbnail: .remoteURL("https://media.merian.app/video-poster.webp")
                ))
            ]
        )
        let legacy = makeScan(id: "legacy", media: [], coverImagePath: "legacy.webp")
        let audio = makeScan(
            id: "audio",
            media: [.audio(.remoteURL("https://media.merian.app/audio.wav"))]
        )
        let posterlessVideo = makeScan(
            id: "posterless",
            media: [.video(StoredVideoMediaReference(.remoteURL("https://media.merian.app/video.mp4")))]
        )
        let archived = makeScan(
            id: "archived",
            media: [.image(.documents("archived.webp"))],
            isLocallyArchived: true
        )
        let referenceURL = referenceURL(source: .merian)
        let referenceOnly = makeScan(
            id: "reference-only",
            media: [],
            coverImagePath: referenceURL,
            referenceImageUrl: referenceURL
        )
        let template = makeTemplate(levels: [
            makeLevel(number: 1, items: [
                makeChecklistItem(id: "video", scanId: video.id),
                makeChecklistItem(id: "legacy", scanId: legacy.id),
                makeChecklistItem(id: "audio", scanId: audio.id),
                makeChecklistItem(id: "posterless", scanId: posterlessVideo.id),
                makeChecklistItem(id: "archived", scanId: archived.id),
                makeChecklistItem(id: "missing", scanId: "missing"),
                makeChecklistItem(id: "reference-only", scanId: referenceOnly.id)
            ])
        ])
        let scans = [video, legacy, audio, posterlessVideo, archived, referenceOnly]

        let candidates = FieldTripFeaturedMediaBuilder.candidates(
            for: template,
            localScansById: Dictionary(uniqueKeysWithValues: scans.map { ($0.id, $0) })
        )

        #expect(candidates[0].source == .userVideo(
            path: "https://media.merian.app/video.mp4",
            posterPath: "https://media.merian.app/video-poster.webp"
        ))
        #expect(candidates[1].source == .userImage(path: "legacy.webp"))
        #expect(candidates.dropFirst(2).allSatisfy { $0.source.isReference })
    }

    @Test func repeatedScanUsesUserMediaOnceAndRetainsReferenceForTheOtherGoal() {
        let scan = makeScan(
            id: "shared",
            media: [.image(.remoteURL("https://media.merian.app/shared.webp"))]
        )
        let template = makeTemplate(levels: [
            makeLevel(number: 1, items: [
                makeChecklistItem(id: "first", scanId: scan.id),
                makeChecklistItem(id: "second", scanId: scan.id)
            ])
        ])

        let candidates = FieldTripFeaturedMediaBuilder.candidates(
            for: template,
            localScansById: [scan.id: scan]
        )

        #expect(candidates[0].source == .userImage(path: "https://media.merian.app/shared.webp"))
        #expect(candidates[1].source.isReference)
    }

    @Test func selectionUsesOnlyTheActiveLevelInStableChecklistOrderAndCapsAtSix() {
        let candidates = [
            makeFeaturedItem(id: "l1-1", level: 1, order: 0),
            makeFeaturedItem(id: "l2-3", level: 2, order: 2),
            makeFeaturedItem(id: "l2-1", level: 2, order: 0),
            makeFeaturedItem(id: "l2-7", level: 2, order: 6),
            makeFeaturedItem(id: "l3-1", level: 3, order: 0),
            makeFeaturedItem(id: "l2-2", level: 2, order: 1),
            makeFeaturedItem(id: "l2-5", level: 2, order: 4),
            makeFeaturedItem(id: "l2-4", level: 2, order: 3),
            makeFeaturedItem(id: "l2-6", level: 2, order: 5)
        ]

        let selected = FieldTripFeaturedMediaSelection.items(
            from: candidates,
            activeLevelId: "level-2"
        )

        #expect(selected.map(\.id) == [
            "l2-1", "l2-2", "l2-3", "l2-4", "l2-5", "l2-6"
        ])
    }

    @Test func missingGoalSourceLetsTheNextActiveLevelReserveRefillTheCarousel() {
        let candidates = [
            makeFeaturedItem(id: "l1-primary", level: 1, order: 0),
            makeFeaturedItem(id: "l1-reserve", level: 1, order: 1),
            makeFeaturedItem(id: "l2-primary", level: 2, order: 0)
        ]

        let selected = FieldTripFeaturedMediaSelection.items(
            from: candidates.filter { $0.id != "l1-primary" },
            activeLevelId: "level-1",
            maximumCount: 2
        )

        #expect(selected.map(\.id) == ["l1-reserve"])
        #expect(FieldTripFeaturedMediaSelection.items(
            from: candidates,
            activeLevelId: nil
        ).isEmpty)
    }

    @Test func presentationPreservesGoalIdentityAndBuildsMixedReferencePhotoVideoGallery() throws {
        let reference = makeFeaturedItem(
            id: "reference",
            level: 1,
            order: 0,
            source: .reference(referenceImage(source: .wikipedia))
        )
        let photo = makeFeaturedItem(
            id: "photo",
            level: 2,
            order: 0,
            source: .userImage(path: "photo.webp")
        )
        let video = makeFeaturedItem(
            id: "video",
            level: 3,
            order: 0,
            source: .userVideo(path: "video.mp4", posterPath: "poster.webp")
        )
        let items = [reference, photo, video]

        let presentation = try #require(
            FieldTripFeaturedMediaPresentation.galleryPresentation(
                for: items,
                selectedItemId: video.id
            )
        )

        #expect(presentation.items.map(\.id) == items.map(\.id))
        #expect(presentation.items.map(\.source) == [
            .referenceURL(referenceURL(source: .wikipedia)),
            .imagePath("photo.webp"),
            .videoPath("video.mp4")
        ])
        #expect(presentation.items[0].referenceAttributionLabel?.contains("Wikipedia") == true)
        #expect(presentation.items.map(\.accessibilityLabel) == items.map(\.accessibilityLabel))
        #expect(presentation.initialSelectedIndex == 2)
        #expect(presentation.initialVideoMuted)
    }

    @Test func selectedIndexPreservesStableGoalIDAcrossSourceReplacementAndRemoval() {
        let reference = makeFeaturedItem(
            id: "same-goal",
            level: 1,
            order: 0,
            source: .reference(referenceImage(source: .merian))
        )
        let replacement = makeFeaturedItem(
            id: "same-goal",
            level: 1,
            order: 0,
            source: .userImage(path: "user.webp")
        )
        let other = makeFeaturedItem(id: "other", level: 2, order: 0)

        #expect(FieldTripFeaturedMediaPresentation.selectedIndex(
            preserving: reference.id,
            previousSelectedIndex: 0,
            in: [other, replacement]
        ) == 1)
        #expect(FieldTripFeaturedMediaPresentation.selectedIndex(
            preserving: "removed",
            previousSelectedIndex: 1,
            in: [other]
        ) == 0)
        #expect(FieldTripFeaturedMediaPresentation.selectedIndex(
            preserving: nil,
            previousSelectedIndex: 1,
            in: [other, replacement]
        ) == 1)
    }

    @Test func heroUnderlapsNavigationBarOnlyWhenFeaturedMediaExists() {
        #expect(FieldTripFeaturedMediaLayout.underlapsNavigationBar(
            featuredItemCount: 1
        ))
        #expect(!FieldTripFeaturedMediaLayout.underlapsNavigationBar(
            featuredItemCount: 0
        ))
    }

    @Test func inlineAttributionSeparatesNaturebookContributorFromSource() {
        let naturebook = FieldTripFeaturedMediaSource.reference(
            referenceImage(source: .merian, authorUsername: "field_author")
        )
        let naturebookWithoutUsername = FieldTripFeaturedMediaSource.reference(
            referenceImage(source: .merian)
        )
        let wikipedia = FieldTripFeaturedMediaSource.reference(
            referenceImage(source: .wikipedia)
        )
        let gbif = FieldTripFeaturedMediaSource.reference(
            referenceImage(source: .gbif)
        )
        let userImage = FieldTripFeaturedMediaSource.userImage(path: "user.webp")

        #expect(naturebook.inlineContributorAttributionLabel == "@field_author")
        #expect(naturebook.inlineAttributionLabel == "Naturebook")
        #expect(naturebookWithoutUsername.inlineContributorAttributionLabel == nil)
        #expect(naturebookWithoutUsername.inlineAttributionLabel == "Naturebook")
        #expect(wikipedia.inlineContributorAttributionLabel == nil)
        #expect(wikipedia.inlineAttributionLabel == "Wikipedia")
        #expect(gbif.inlineContributorAttributionLabel == nil)
        #expect(gbif.inlineAttributionLabel == "GBIF")
        #expect(userImage.inlineContributorAttributionLabel == nil)
        #expect(userImage.inlineAttributionLabel == nil)
    }

    @Test func loadingSkeletonUsesTheFeaturedHeroUntilTemplateContentArrives() {
        #expect(FieldTripDetailLoadingPresentation.showsFeaturedMediaHero(
            isLoading: true,
            hasTemplate: false
        ))
        #expect(!FieldTripDetailLoadingPresentation.showsFeaturedMediaHero(
            isLoading: true,
            hasTemplate: true
        ))
        #expect(!FieldTripDetailLoadingPresentation.showsFeaturedMediaHero(
            isLoading: false,
            hasTemplate: false
        ))
    }

    private func makeTemplate(levels: [FieldTripLevel]) -> FieldTripTemplate {
        FieldTripTemplate(
            templateId: "template",
            slug: "test_trip",
            title: "Test Trip",
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
            activeProgress: nil,
            stoppedProgress: nil,
            levels: levels
        )
    }

    private func makeLevel(number: Int, items: [FieldTripChecklistItem]) -> FieldTripLevel {
        FieldTripLevel(
            levelId: "level-\(number)",
            levelNumber: number,
            title: "Level \(number)",
            description: nil,
            items: items
        )
    }

    private func makeChecklistItem(
        id: String,
        scanId: String?,
        isCompleted: Bool = true,
        referenceSpecies: FieldTripReferenceSpecies? = nil
    ) -> FieldTripChecklistItem {
        FieldTripChecklistItem(
            itemId: id,
            prompt: "Goal \(id)",
            matchType: "taxonomy",
            guideTip: nil,
            guide: nil,
            referenceSpecies: referenceSpecies ?? makeReferenceSpecies(),
            isCompleted: isCompleted,
            completedAt: isCompleted ? "2026-08-07T12:00:00Z" : nil,
            completedCommonName: isCompleted ? "Observed \(id)" : nil,
            completedScientificName: isCompleted ? "Species scientificus" : nil,
            completedScanId: scanId
        )
    }

    private func makeReferenceSpecies() -> FieldTripReferenceSpecies {
        FieldTripReferenceSpecies(
            scientificName: "Passer domesticus",
            commonName: "House Sparrow",
            referenceImages: [
                referenceImage(source: .gbif),
                referenceImage(source: .wikipedia),
                referenceImage(source: .merian)
            ]
        )
    }

    private func referenceImage(
        source: SpeciesDictionaryReferenceImage.Source,
        authorUsername: String? = nil
    ) -> SpeciesDictionaryReferenceImage {
        SpeciesDictionaryReferenceImage(
            url: referenceURL(source: source),
            source: source,
            license: source == .wikipedia ? "CC BY-SA 4.0" : nil,
            attribution: source == .wikipedia ? "Example Photographer" : nil,
            authorUsername: authorUsername,
            width: 1200,
            height: 800
        )
    }

    private func referenceURL(
        source: SpeciesDictionaryReferenceImage.Source
    ) -> String {
        switch source {
        case .merian:
            "https://media.merian.app/reference.webp"
        case .wikipedia:
            "https://upload.wikimedia.org/reference.jpg"
        case .gbif:
            "https://api.gbif.org/reference.jpg"
        case .unknown(let value):
            "https://example.com/\(value).jpg"
        }
    }

    private func makeScan(
        id: String,
        media: [SerializedMediaItem],
        coverImagePath: String? = nil,
        referenceImageUrl: String? = nil,
        isLocallyArchived: Bool = false
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: "species-\(id)",
            scientificName: "Species scientificus",
            commonName: "Species \(id)",
            timestamp: Date(timeIntervalSince1970: 100),
            captureDate: Date(timeIntervalSince1970: 100),
            capturedMediaJSON: MediaJSONParser.jsonString(from: media),
            coverImagePath: coverImagePath,
            referenceImageUrl: referenceImageUrl,
            isLocallyArchived: isLocallyArchived,
            imageQualityScore: 80
        )
    }

    private func makeFeaturedItem(
        id: String,
        level: Int,
        order: Int,
        source: FieldTripFeaturedMediaSource = .userImage(path: "image.webp")
    ) -> FieldTripFeaturedMediaItem {
        FieldTripFeaturedMediaItem(
            id: id,
            scanId: source.isReference ? nil : "scan-\(id)",
            levelId: "level-\(level)",
            levelNumber: level,
            levelTitle: "Level \(level)",
            checklistOrder: order,
            goalTitle: "Goal \(id)",
            completedCommonName: source.isReference ? nil : "Species \(id)",
            referenceSpecies: makeReferenceSpecies(),
            source: source
        )
    }
}
