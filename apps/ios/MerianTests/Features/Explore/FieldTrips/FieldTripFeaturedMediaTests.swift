import Foundation
@testable import Merian
import Testing

struct FieldTripFeaturedMediaTests {
    @Test func builderUsesOnlyCompletedUserVisualsAndDefensivelyDeduplicatesScans() throws {
        let photo = makeScan(
            id: "photo",
            media: [.image(.remoteURL("https://media.merian.app/photo.webp"))]
        )
        let video = makeScan(
            id: "video",
            media: [
                .video(StoredVideoMediaReference(
                    .remoteURL("https://media.merian.app/video.mp4"),
                    thumbnail: .remoteURL("https://media.merian.app/video-poster.webp")
                ))
            ]
        )
        let audio = makeScan(
            id: "audio",
            media: [.audio(.remoteURL("https://media.merian.app/audio.wav"))]
        )
        let videoWithoutPoster = makeScan(
            id: "video-without-poster",
            media: [
                .video(StoredVideoMediaReference(
                    .remoteURL("https://media.merian.app/no-poster.mp4")
                ))
            ]
        )
        let legacyCover = makeScan(
            id: "legacy-cover",
            media: [],
            coverImagePath: "legacy-cover.webp"
        )
        let referenceOnly = makeScan(
            id: "reference-only",
            media: [],
            coverImagePath: "https://example.com/reference.jpg",
            referenceImageUrl: "https://example.com/reference.jpg"
        )
        let archived = makeScan(
            id: "archived",
            media: [.image(.documents("archived.webp"))],
            isLocallyArchived: true
        )
        let incomplete = makeScan(
            id: "incomplete",
            media: [.image(.documents("incomplete.webp"))]
        )

        let template = makeTemplate(levels: [
            makeLevel(number: 1, items: [
                makeChecklistItem(id: "photo-goal", scanId: photo.id),
                makeChecklistItem(id: "video-goal", scanId: video.id),
                makeChecklistItem(id: "duplicate-photo-goal", scanId: photo.id),
                makeChecklistItem(id: "audio-goal", scanId: audio.id),
                makeChecklistItem(id: "posterless-video-goal", scanId: videoWithoutPoster.id),
                makeChecklistItem(id: "legacy-goal", scanId: legacyCover.id),
                makeChecklistItem(id: "reference-goal", scanId: referenceOnly.id),
                makeChecklistItem(id: "archived-goal", scanId: archived.id),
                makeChecklistItem(id: "no-scan-id-goal", scanId: nil),
                makeChecklistItem(id: "missing-goal", scanId: "missing"),
                makeChecklistItem(id: "incomplete-goal", scanId: incomplete.id, isCompleted: false)
            ])
        ])
        let scans = [
            photo,
            video,
            audio,
            videoWithoutPoster,
            legacyCover,
            referenceOnly,
            archived,
            incomplete
        ]

        let candidates = FieldTripFeaturedMediaBuilder.candidates(
            for: template,
            localScansById: Dictionary(uniqueKeysWithValues: scans.map { ($0.id, $0) })
        )

        #expect(candidates.map(\.scanId) == ["photo", "video", "legacy-cover"])
        #expect(candidates[0].source == .image(path: "https://media.merian.app/photo.webp"))
        #expect(candidates[1].source == .video(
            path: "https://media.merian.app/video.mp4",
            posterPath: "https://media.merian.app/video-poster.webp"
        ))
        #expect(candidates[2].source == .image(path: "legacy-cover.webp"))
    }

    @Test func selectionBalancesLevelsWhileRankingQualityBeforeRecency() {
        let candidates = [
            makeFeaturedItem(id: "l1-70", level: 1, quality: 70, timestamp: 90),
            makeFeaturedItem(id: "l1-90", level: 1, quality: 90, timestamp: 10),
            makeFeaturedItem(id: "l1-80", level: 1, quality: 80, timestamp: 80),
            makeFeaturedItem(id: "l2-75", level: 2, quality: 75, timestamp: 70),
            makeFeaturedItem(id: "l2-95", level: 2, quality: 95, timestamp: 20),
            makeFeaturedItem(id: "l2-85", level: 2, quality: 85, timestamp: 60),
            makeFeaturedItem(id: "l3-68", level: 3, quality: 68, timestamp: 50),
            makeFeaturedItem(id: "l3-88", level: 3, quality: 88, timestamp: 30),
            makeFeaturedItem(id: "l3-78", level: 3, quality: 78, timestamp: 40)
        ]

        let selected = FieldTripFeaturedMediaSelection.items(from: candidates)

        #expect(selected.map(\.id) == [
            "l1-90", "l2-95", "l3-88",
            "l1-80", "l2-85", "l3-78"
        ])
    }

    @Test func selectionUsesNewestFallbackAndStableChecklistOrderForQualityTies() {
        let candidates = [
            makeFeaturedItem(id: "unscored-old", level: 1, quality: nil, timestamp: 10, order: 0),
            makeFeaturedItem(id: "unscored-new", level: 1, quality: nil, timestamp: 30, order: 1),
            makeFeaturedItem(id: "scored-zero", level: 1, quality: 0, timestamp: 5, order: 2),
            makeFeaturedItem(id: "tie-second", level: 2, quality: 80, timestamp: 20, order: 2),
            makeFeaturedItem(id: "tie-first", level: 2, quality: 80, timestamp: 20, order: 1)
        ]

        let selected = FieldTripFeaturedMediaSelection.items(
            from: candidates,
            maximumCount: 5
        )

        #expect(selected.map(\.id) == [
            "scored-zero", "tie-first",
            "unscored-new", "tie-second",
            "unscored-old"
        ])
    }

    @Test func selectionUsesStableIDForOtherwiseIdenticalCandidates() {
        let candidates = [
            makeFeaturedItem(id: "stable-z", level: 1, quality: 80, timestamp: 20),
            makeFeaturedItem(id: "stable-a", level: 1, quality: 80, timestamp: 20)
        ]

        let selected = FieldTripFeaturedMediaSelection.items(from: candidates)

        #expect(selected.map(\.id) == ["stable-a", "stable-z"])
    }

    @Test func failedFeaturedMediaRefillsFromTheSameLevelAndCanCollapseCompletely() {
        let levelOnePrimary = makeFeaturedItem(id: "l1-primary", level: 1, quality: 90, timestamp: 30)
        let levelOneReserve = makeFeaturedItem(id: "l1-reserve", level: 1, quality: 80, timestamp: 20)
        let levelTwoPrimary = makeFeaturedItem(id: "l2-primary", level: 2, quality: 90, timestamp: 30)
        let candidates = [levelOnePrimary, levelOneReserve, levelTwoPrimary]

        let refilled = FieldTripFeaturedMediaSelection.items(
            from: candidates,
            excluding: [levelOnePrimary.id],
            maximumCount: 2
        )
        let collapsed = FieldTripFeaturedMediaSelection.items(
            from: candidates,
            excluding: Set(candidates.map(\.id))
        )

        #expect(refilled.map(\.id) == [levelOneReserve.id, levelTwoPrimary.id])
        #expect(collapsed.isEmpty)
    }

    @Test func presentationPreservesSelectionAndBuildsPhotoVideoGalleryInFeaturedOrder() throws {
        let photo = makeFeaturedItem(
            id: "photo",
            level: 1,
            quality: 80,
            timestamp: 10,
            source: .image(path: "photo.webp")
        )
        let video = makeFeaturedItem(
            id: "video",
            level: 2,
            quality: 90,
            timestamp: 20,
            source: .video(path: "video.mp4", posterPath: "poster.webp")
        )
        let items = [photo, video]

        let presentation = try #require(
            FieldTripFeaturedMediaPresentation.galleryPresentation(
                for: items,
                selectedItemId: video.id
            )
        )

        #expect(FieldTripFeaturedMediaPresentation.selectedItemId(
            preserving: video.id,
            in: items
        ) == video.id)
        #expect(FieldTripFeaturedMediaPresentation.selectedItemId(
            preserving: "removed",
            in: items
        ) == photo.id)
        #expect(presentation.items.map(\.id) == [photo.id, video.id])
        #expect(presentation.items.map(\.source) == [
            .imagePath("photo.webp"),
            .videoPath("video.mp4")
        ])
        #expect(presentation.items.map(\.accessibilityLabel) == [
            photo.accessibilityLabel,
            video.accessibilityLabel
        ])
        #expect(presentation.initialSelectedIndex == 1)
        #expect(presentation.initialVideoMuted)
        #expect(FieldTripFeaturedMediaPresentation.galleryPresentation(
            for: [],
            selectedItemId: nil
        ) == nil)
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

    private func makeLevel(
        number: Int,
        items: [FieldTripChecklistItem]
    ) -> FieldTripLevel {
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
        isCompleted: Bool = true
    ) -> FieldTripChecklistItem {
        FieldTripChecklistItem(
            itemId: id,
            prompt: "Goal \(id)",
            matchType: "taxonomy",
            guideTip: nil,
            guide: nil,
            isCompleted: isCompleted,
            completedAt: isCompleted ? "2026-08-07T12:00:00Z" : nil,
            completedCommonName: isCompleted ? "Species \(id)" : nil,
            completedScientificName: isCompleted ? "Species scientificus" : nil,
            completedScanId: scanId
        )
    }

    private func makeScan(
        id: String,
        media: [SerializedMediaItem],
        coverImagePath: String? = nil,
        referenceImageUrl: String? = nil,
        isLocallyArchived: Bool = false,
        quality: Int? = 80,
        timestamp: TimeInterval = 100
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: "species-\(id)",
            scientificName: "Species scientificus",
            commonName: "Species \(id)",
            timestamp: Date(timeIntervalSince1970: timestamp),
            captureDate: Date(timeIntervalSince1970: timestamp),
            capturedMediaJSON: MediaJSONParser.jsonString(from: media),
            coverImagePath: coverImagePath,
            referenceImageUrl: referenceImageUrl,
            isLocallyArchived: isLocallyArchived,
            imageQualityScore: quality
        )
    }

    private func makeFeaturedItem(
        id: String,
        level: Int,
        quality: Int?,
        timestamp: TimeInterval,
        order: Int = 0,
        source: FieldTripFeaturedMediaSource = .image(path: "image.webp")
    ) -> FieldTripFeaturedMediaItem {
        FieldTripFeaturedMediaItem(
            id: id,
            scanId: "scan-\(id)",
            levelId: "level-\(level)",
            levelNumber: level,
            levelTitle: "Level \(level)",
            checklistOrder: order,
            goalTitle: "Goal \(id)",
            completedCommonName: "Species \(id)",
            source: source,
            imageQualityScore: quality,
            capturedAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}
