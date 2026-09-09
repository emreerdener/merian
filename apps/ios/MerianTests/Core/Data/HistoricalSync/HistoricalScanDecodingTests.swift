import Foundation
import Supabase
import Testing

@testable import Merian

extension ScanRepositoryTests {
    @Test func testHistoricalObservationContextIgnoresRetiredOrderingTimestamp() throws {
        let payload = Data(
            #"{"free_text":"  Heard beside the creek  ","added_at":"2026-08-15T05:30:00.000Z"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(HistoricalObservationContext.self, from: payload)
        let context = try #require(decoded.observationContext)

        #expect(context.freeText == "Heard beside the creek")
    }

    @Test func testPostgrestHistoricalDecoderAcceptsEveryLegacyDescriptionTimestamp() throws {
        let payload = Data(
            """
            [
              {"id":"numeric","explore_posts":null,"captured_media":[{"description":{"_0":{"freeText":"Numeric","addedAt":807000000}}}]},
              {"id":"iso","explore_posts":null,"captured_media":[{"description":{"_0":{"freeText":"ISO","added_at":"2026-08-22T12:00:00.000Z"}}}]},
              {"id":"missing","explore_posts":null,"captured_media":[{"description":{"_0":{"free_text":"Missing"}}}]},
              {"id":"malformed","explore_posts":null,"captured_media":[{"description":{"_0":{"freeText":"Malformed","addedAt":{"unexpected":true}}}}]}
            ]
            """.utf8
        )

        let decoded = try HistoricalScanPageDecoder.decode(
            payload,
            using: PostgrestClient.Configuration.jsonDecoder
        )

        #expect(decoded.remoteRowCount == 4)
        #expect(decoded.rejectedRowCount == 0)
        #expect(decoded.responses.map(\.id) == [
            "numeric", "iso", "missing", "malformed"
        ])
        #expect(decoded.responses.compactMap(\.capturedMediaItems) == [
            [.description(ObservationContext(freeText: "Numeric"))],
            [.description(ObservationContext(freeText: "ISO"))],
            [.description(ObservationContext(freeText: "Missing"))],
            [.description(ObservationContext(freeText: "Malformed"))]
        ])
    }

    @Test func testHistoricalPageDecoderQuarantinesMalformedRowsIndividually() throws {
        let payload = Data(
            """
            [
              {"id":"valid-image","explore_posts":null,"captured_media":[{"image":{"_0":{"storage":"remoteURL","path":"https://cdn.example.com/image.webp"}}}]},
              {"id":"unknown-wrapper","explore_posts":null,"captured_media":[{"document":{"_0":{}}}]},
              {"id":"multiple-wrappers","explore_posts":null,"captured_media":[{"image":{"_0":{"storage":"remoteURL","path":"https://cdn.example.com/a.webp"}},"audio":{"_0":{"storage":"remoteURL","path":"https://cdn.example.com/a.wav"}}}]},
              {"id":"valid-description","explore_posts":null,"captured_media":[{"description":{"_0":{"freeText":"Still recoverable"}}}]}
            ]
            """.utf8
        )

        let decoded = try HistoricalScanPageDecoder.decode(payload)

        #expect(decoded.remoteRowCount == 4)
        #expect(decoded.rejectedRowCount == 2)
        #expect(decoded.responses.map(\.id) == [
            "valid-image", "valid-description"
        ])
        #expect(decoded.firstRejectedCodingPath != nil)
    }

    @Test func testHistoricalDecoderProjectsActiveExploreShareState() throws {
        let payload = Data(
            """
            [
              {
                "id":"active-scan",
                "explore_posts":{
                  "id":"active-post",
                  "unshared_at":null
                }
              },
              {
                "id":"unshared-scan",
                "explore_posts":{
                  "id":"unshared-post",
                  "unshared_at":"2026-08-30T12:00:00.000Z"
                }
              },
              {
                "id":"private-scan",
                "explore_posts":null
              }
            ]
            """.utf8
        )

        let decoded = try HistoricalScanPageDecoder.decode(
            payload,
            using: PostgrestClient.Configuration.jsonDecoder
        )

        #expect(decoded.rejectedRowCount == 0)
        #expect(decoded.responses.map(\.activeExplorePostId) == [
            "active-post", nil, nil
        ])
    }

    @Test func testHistoricalDecoderRejectsRowsMissingExploreProjection() throws {
        let payload = Data(#"[{"id":"missing-relation"}]"#.utf8)

        let decoded = try HistoricalScanPageDecoder.decode(payload)

        #expect(decoded.remoteRowCount == 1)
        #expect(decoded.responses.isEmpty)
        #expect(decoded.rejectedRowCount == 1)
        #expect(decoded.firstRejectedCodingPath == "explore_posts")
    }

    @Test func testHistoricalDecoderIgnoresLegacyLocalFileReferencesAndUsesCloudMedia() throws {
        let remoteImage = "https://cdn.example.com/durable.webp"
        let payload = Data(
            """
            [
              {
                "id":"legacy-local-file",
                "explore_posts":null,
                "image_storage_urls":["\(remoteImage)"],
                "video_storage_urls":[],
                "captured_media":[
                  {"image":{"_0":{"storage":"localFile","path":"legacy.webp"}}},
                  {"description":{"_0":{"freeText":"Still recoverable","addedAt":807000000}}}
                ]
              }
            ]
            """.utf8
        )

        let decoded = try HistoricalScanPageDecoder.decode(
            payload,
            using: PostgrestClient.Configuration.jsonDecoder
        )
        let response = try #require(decoded.responses.first)

        #expect(decoded.rejectedRowCount == 0)
        #expect(response.capturedMediaItems == [
            .description(ObservationContext(freeText: "Still recoverable"))
        ])
        #expect(CapturedMediaSnapshot.cloudHydratedItems(
            capturedMediaItems: response.capturedMediaItems,
            imageStorageURLs: response.image_storage_urls,
            videoStorageURLs: response.video_storage_urls
        ) == [
            .image(.remoteURL(remoteImage)),
            .description(ObservationContext(freeText: "Still recoverable"))
        ])
    }
}
