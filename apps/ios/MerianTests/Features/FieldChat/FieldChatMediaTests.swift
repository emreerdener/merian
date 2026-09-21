import Foundation
import Testing

@testable import Merian

struct FieldChatMediaTests {
    @Test func insightPreservesCaptureAndPosterOrderThenAddsReferences() {
        let data = Data([1, 2, 3])
        let media = ActiveScanMedia(
            items: [
                .audio("sound.m4a"), .image("first.jpg"),
                .video("clip.mp4", fallbackImage: .imagePath("poster.jpg")),
                .video("no-poster.mp4"), .liveImage(data), .image("first.jpg")
            ],
            referenceState: .loaded(["first.jpg", "https://upload.wikimedia.org/reference.jpg"])
        )
        let images = InsightFieldChatMedia.images(from: media, wikipediaURL: nil)
        #expect(images.map(\.source) == [
            .path("first.jpg"), .path("poster.jpg"), .liveImage(data),
            .path("https://upload.wikimedia.org/reference.jpg")
        ])
        #expect(images[1].accessibilityLabel == "Observation video still")
        #expect(images.last?.attribution == "Wikipedia")
        #expect(images.first?.attribution == nil)
    }

    @Test func emptyAndNonVisualInsightMediaUseFallback() {
        #expect(InsightFieldChatMedia.images(from: ActiveScanMedia(), wikipediaURL: nil).isEmpty)
        #expect(InsightFieldChatMedia.images(
            from: ActiveScanMedia(items: [.audio("audio.m4a"), .video("video.mp4")], referenceState: .loading),
            wikipediaURL: nil
        ).isEmpty)
        #expect(FieldChatMedia.image(path: "  \n") == nil)
        #expect(FieldChatMedia.liveImage(Data()) == nil)
    }

    @Test func liveVideoPosterIsAStillAndNotAnotherPlaybackItem() {
        let data = Data([3, 2, 1])
        let images = InsightFieldChatMedia.images(
            from: ActiveScanMedia(items: [.video("video.mp4", fallbackImage: .liveImage(data))]),
            wikipediaURL: nil
        )
        #expect(images.map(\.source) == [.liveImage(data)])
    }

    @Test func explorePromotesFeaturedImageAndRetainsOtherMediaOrder() {
        let items: [ExploreMediaItem] = [
            .legacyImage(url: "first.jpg"),
            ExploreMediaItem(
                kind: .video, url: "clip.mp4", thumbnailUrl: "poster.jpg",
                orderIndex: 9, durationSeconds: 2, hasAudio: true
            ),
            .legacyImage(url: "hero.jpg"),
            ExploreMediaItem(
                kind: .audio, url: "audio.m4a", thumbnailUrl: "spectrogram.jpg",
                orderIndex: 0, durationSeconds: 2, hasAudio: true
            )
        ]
        #expect(ExploreFieldChatMedia.images(items: items, heroImageURL: "hero.jpg").map(\.source) == [
            .path("hero.jpg"), .path("first.jpg"), .path("poster.jpg")
        ])
    }

    @Test func exploreUsesExistingHeroWhenVideoHasNoPoster() {
        let video = ExploreMediaItem(
            kind: .video, url: "clip.mp4", thumbnailUrl: nil,
            orderIndex: 0, durationSeconds: 2, hasAudio: false
        )
        #expect(ExploreFieldChatMedia.images(items: [video], heroImageURL: "hero.jpg").map(\.source) == [.path("hero.jpg")])
        #expect(ExploreFieldChatMedia.images(items: [video], heroImageURL: "").isEmpty)
        #expect(ExploreFieldChatMedia.images(items: [.legacyImage(url: "hero.jpg")], heroImageURL: "hero.jpg").count == 1)
    }

    @Test func exploreMatchesSourceCarouselSortAndIncludesSeparateHero() {
        let items = [
            ExploreMediaItem(kind: .image, url: "last.jpg", thumbnailUrl: nil, orderIndex: 3, durationSeconds: nil, hasAudio: false),
            ExploreMediaItem(kind: .image, url: "first.jpg", thumbnailUrl: nil, orderIndex: 1, durationSeconds: nil, hasAudio: false),
            ExploreMediaItem(kind: .image, url: "second.jpg", thumbnailUrl: nil, orderIndex: 1, durationSeconds: nil, hasAudio: false)
        ]
        #expect(ExploreFieldChatMedia.images(items: items, heroImageURL: "hero.jpg").map(\.id) == [
            "hero.jpg", "first.jpg", "second.jpg", "last.jpg"
        ])
        let audio = ExploreMediaItem(
            kind: .audio, url: "audio.m4a", thumbnailUrl: nil, orderIndex: 0, durationSeconds: 2, hasAudio: true
        )
        #expect(ExploreFieldChatMedia.images(items: [audio], heroImageURL: "hero.jpg").map(\.id) == ["hero.jpg"])
    }

    @Test func dictionaryPreservesRightsAndSourceOrder() {
        let images = SpeciesDictionaryFieldChatMedia.images([
            SpeciesDictionaryReferenceImage(
                url: "https://example.com/first.jpg", source: .gbif,
                license: "CC BY 4.0", attribution: "Example photographer", width: nil, height: nil
            ),
            SpeciesDictionaryReferenceImage(
                url: "https://example.com/second.jpg", source: .merian,
                license: "Used with permission via Naturebook", attribution: nil,
                authorUsername: "example", width: nil, height: nil
            )
        ])
        #expect(images.map(\.id) == ["https://example.com/first.jpg", "https://example.com/second.jpg"])
        #expect(images.map(\.attribution) == ["Example photographer · CC BY 4.0 · GBIF", "@example · Naturebook"])
        #expect(SpeciesDictionaryFieldChatMedia.images(for: "missing", species: nil).isEmpty)
    }

    @Test func duplicateSignedMediaURLsAndWhitespaceDoNotAddCards() {
        let paths = [" first.jpg ", "first.jpg", "https://media.merian.app/photo.jpg?x=1", "https://media.merian.app/photo.jpg?x=2"]
        let images = FieldChatMedia.orderedUnique(paths.compactMap { .image(path: $0) })
        #expect(images.count == 2)
        #expect(images.first?.id == "first.jpg")
        let featured = FieldChatMedia.orderedUnique(
            images, featuredPath: "https://media.merian.app/photo.jpg?x=2"
        )
        #expect(featured.first?.id == "https://media.merian.app/photo.jpg?x=1")
    }

    @Test func dictionaryRejectsMediaFromAReplacementSubject() {
        let subjectID = "00000000-0000-4000-8000-000000000001"
        let species = SpeciesDictionaryEntry(
            id: subjectID, scientificName: "Testus floridus", commonName: "Test flower",
            contentQuality: .complete, alternativeCommonNames: [], taxonomy: nil,
            hazardType: "none", iucnRedListStatus: nil, wikipediaUrl: nil,
            wikipediaOverview: nil, habitatDescription: nil, gbifTaxonKey: nil,
            groupTags: [], referenceImages: [
                SpeciesDictionaryReferenceImage(
                    url: "https://example.com/reference.jpg", source: .gbif,
                    license: "CC0", attribution: "Example photographer", width: nil, height: nil
                )
            ], similarSpecies: []
        )
        #expect(SpeciesDictionaryFieldChatMedia.images(for: subjectID, species: species).count == 1)
        #expect(SpeciesDictionaryFieldChatMedia.images(
            for: "00000000-0000-4000-8000-000000000002", species: species
        ).isEmpty)
    }
}
