import Foundation
import Testing

@testable import Merian

/// Explicit request oracles, including invalid inputs that transport still forwards.
struct ExplorePostManagementEndpointRequestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let function: String
    let expectedJSON: String
    let responseJSON: String
    let requiresIdempotencyKey: Bool
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    init(
        name: String, function: String, expectedJSON: String, responseJSON: String,
        requiresIdempotencyKey: Bool = false,
        invoke: @escaping @MainActor @Sendable (MerianNetworkClient) async throws -> Void
    ) {
        self.name = name
        self.function = function
        self.expectedJSON = expectedJSON
        self.responseJSON = responseJSON
        self.requiresIdempotencyKey = requiresIdempotencyKey
        self.invoke = invoke
    }

    var testDescription: String { name }
    var path: String { "/\(function)" }

    static var operations: [Self] { [composer, shareState, incidents, unshare, notesEdit, contentEdit] }
    static var rawDecodingOperations: [Self] { [composer, notesEdit, contentEdit] }
    static var mappedDecodingOperations: [Self] { [shareState, incidents] }
    static var replayableOperations: [Self] { [composer, shareState, incidents, contentEdit] }
    static var nonReplayableMutations: [Self] { [unshare, notesEdit] }
    static var all: [Self] {
        operations + composerVariants + rawIdentifierVariants + notesVariants + contentVariants
    }

    static let composer = Self(
        name: "composer defaults omit both IDs", function: "get-explore-composer-media",
        expectedJSON: "{}", responseJSON: ExplorePostManagementEndpointResponses.composer
    ) { client in
        _ = try await client.getExploreComposerMedia()
    }

    static let shareState = Self(
        name: "share-state lookup", function: "get-scan-explore-share-state",
        expectedJSON: #"{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}"#,
        responseJSON: ExplorePostManagementEndpointResponses.shared
    ) { client in
        _ = try await client.getExploreShareState(scanId: ExplorePostManagementEndpointResponses.scanID)
    }

    static let incidents = Self(
        name: "owner media incidents", function: "get-explore-media-incidents",
        expectedJSON: "{}", responseJSON: ExplorePostManagementEndpointResponses.incidents
    ) { client in
        _ = try await client.getExploreMediaIncidents()
    }

    static let unshare = Self(
        name: "unshare post", function: "unshare-explore-post",
        expectedJSON: #"{"post_id":"post-test"}"#, responseJSON: ""
    ) { client in
        try await client.unshareExplorePost(postId: "post-test")
    }

    static let notesEdit = Self(
        name: "legacy notes edit sends null without an idempotency key", function: "update-explore-field-notes",
        expectedJSON: #"{"post_id":"post-test","field_notes":null}"#,
        responseJSON: ExplorePostManagementEndpointResponses.edit
    ) { client in
        _ = try await client.updateExplorePostFieldNotes(postId: "post-test", fieldNotes: nil)
    }

    static let contentEdit = contentCase(
        name: "content defaults omit common name and media",
        expectedJSON: #"{"post_id":"post-test","field_notes":null,"hashtags":[],"location_sharing":"obscured"}"#
    )

    @discardableResult
    func expectRequest(_ request: URLRequest) throws -> NetworkEndpointRequestSnapshot {
        let key = request.value(forHTTPHeaderField: "Idempotency-Key")
        if requiresIdempotencyKey {
            let value = try #require(key)
            #expect(UUID(uuidString: value) != nil)
            #expect(value == value.lowercased())
        } else {
            #expect(key == nil)
        }
        return try NetworkEndpointTestSupport.expectPOST(
            request, function: function, json: expectedJSON, idempotencyKey: key
        )
    }

    @MainActor
    func withResponse(
        _ responseJSON: String? = nil,
        body: (MerianNetworkClient) async throws -> Void
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("Exactly one post-management POST") { sent in
            fixture.transport.register(path: path) { request in
                sent()
                try expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, json: responseJSON ?? self.responseJSON)
            }
            try await body(fixture.client)
        }
    }

    private static var composerVariants: [Self] {
        let values: [(String, String?, String?, String)] = [
            ("scan only", " scan-test ", nil, #"{"scan_id":" scan-test "}"#),
            ("post only", nil, " post-test ", #"{"post_id":" post-test "}"#),
            ("both", "scan-test", "post-test", #"{"scan_id":"scan-test","post_id":"post-test"}"#),
            ("empty scan", "", nil, #"{"scan_id":""}"#),
            ("empty post", nil, "", #"{"post_id":""}"#),
            ("blank pair", " ", " ", #"{"scan_id":" ","post_id":" "}"#)
        ]
        return values.map { name, scanID, postID, json in
            Self(
                name: "composer: \(name)", function: "get-explore-composer-media",
                expectedJSON: json, responseJSON: ExplorePostManagementEndpointResponses.composer
            ) { client in
                _ = try await client.getExploreComposerMedia(scanId: scanID, postId: postID)
            }
        }
    }

    private static var rawIdentifierVariants: [Self] {
        ["", " RAW-ID "].flatMap { identifier in
            [
                Self(
                    name: "share-state raw ID: \(identifier)", function: "get-scan-explore-share-state",
                    expectedJSON: #"{"scan_id":"\#(identifier)"}"#,
                    responseJSON: """
                    {"data":{"scan_id":"\(identifier)","post_id":null,"shared_at":null,
                     "is_explore_feed_visible":false,"location_sharing":"private"}}
                    """
                ) { client in
                    _ = try await client.getExploreShareState(scanId: identifier)
                },
                Self(
                    name: "unshare raw ID: \(identifier)", function: "unshare-explore-post",
                    expectedJSON: #"{"post_id":"\#(identifier)"}"#, responseJSON: ""
                ) { client in
                    try await client.unshareExplorePost(postId: identifier)
                },
                Self(
                    name: "legacy edit raw ID: \(identifier)", function: "update-explore-field-notes",
                    expectedJSON: #"{"post_id":"\#(identifier)","field_notes":null}"#,
                    responseJSON: ExplorePostManagementEndpointResponses.edit
                ) { client in
                    _ = try await client.updateExplorePostFieldNotes(postId: identifier, fieldNotes: nil)
                },
                contentCase(
                    name: "content edit raw ID: \(identifier)",
                    expectedJSON: #"{"post_id":"\#(identifier)","field_notes":null,"hashtags":[],"location_sharing":"obscured"}"#,
                    postID: identifier
                )
            ]
        }
    }

    private static var notesVariants: [Self] {
        [("", #""""#), (" \n ", #"" \n ""#), ("  Test notes  ", #""  Test notes  ""#)].map { notes, json in
            Self(
                name: "legacy notes preserve text: \(json)", function: "update-explore-field-notes",
                expectedJSON: #"{"post_id":"post-test","field_notes":\#(json)}"#,
                responseJSON: ExplorePostManagementEndpointResponses.edit
            ) { client in
                _ = try await client.updateExplorePostFieldNotes(postId: "post-test", fieldNotes: notes)
            }
        }
    }

    private static var contentVariants: [Self] {
        let longName = String(repeating: "x", count: 201)
        let longNotes = String(repeating: "n", count: 1001)
        let locations: [(ExplorePostLocationSharing, String)] = [
            (.open, "open"), (.obscured, "obscured"), (.privateLocation, "private")
        ]
        return locations.map { location, wireValue in
            contentCase(
                name: "content location: \(wireValue)",
                expectedJSON: #"{"post_id":"post-test","field_notes":null,"hashtags":[],"location_sharing":"\#(wireValue)"}"#,
                location: location
            )
        } + [
            contentCase(
                name: "empty common name omitted",
                expectedJSON: contentEdit.expectedJSON, commonName: ""
            ),
            contentCase(
                name: "blank common name omitted",
                expectedJSON: contentEdit.expectedJSON, commonName: " \n "
            ),
            contentCase(
                name: "common name trims only outer whitespace",
                expectedJSON: #"{"post_id":"post-test","field_notes":null,"hashtags":[],"location_sharing":"obscured","species_common_name":"Test  species"}"#,
                commonName: " \nTest  species \n "
            ),
            contentCase(
                name: "common name is not truncated",
                expectedJSON: #"{"post_id":"post-test","field_notes":null,"hashtags":[],"location_sharing":"obscured","species_common_name":"\#(longName)"}"#,
                commonName: longName
            ),
            contentCase(
                name: "empty notes stay a string",
                expectedJSON: #"{"post_id":"post-test","field_notes":"","hashtags":[],"location_sharing":"obscured"}"#,
                notes: ""
            ),
            contentCase(
                name: "notes and hashtags stay raw and ordered",
                expectedJSON: ##"{"post_id":"post-test","field_notes":" \n ","hashtags":["#B","a","#B",""],"location_sharing":"obscured"}"##,
                notes: " \n ", hashtags: ["#B", "a", "#B", ""]
            ),
            contentCase(
                name: "notes are not truncated",
                expectedJSON: #"{"post_id":"post-test","field_notes":"\#(longNotes)","hashtags":[],"location_sharing":"obscured"}"#,
                notes: longNotes
            ),
            contentCase(
                name: "empty media is present",
                expectedJSON: #"{"post_id":"post-test","field_notes":null,"hashtags":[],"location_sharing":"obscured","media_items":[]}"#,
                media: []
            ),
            contentCase(
                name: "nil media selection fields omitted",
                expectedJSON: #"{"post_id":"post-test","field_notes":null,"hashtags":[],"location_sharing":"obscured","media_items":[{"kind":"image","order_index":0}]}"#,
                media: [.init(kind: .image, sourceMediaId: nil, sourceIndex: nil, thumbnailSourceIndex: nil,
                              url: nil, thumbnailUrl: nil, orderIndex: 0)]
            ),
            contentCase(
                name: "media selection keeps all optional fields and order",
                expectedJSON: """
                {"post_id":"post-test","field_notes":null,"hashtags":[],"location_sharing":"obscured","media_items":[
                  {"kind":"audio","source_media_id":" audio-source ","source_index":0,"thumbnail_source_index":0,
                   "url":"","thumbnail_url":"","order_index":8},
                  {"kind":"video","source_index":-1,"thumbnail_source_index":2,
                   "url":"https://media.example.test/clip.mp4","thumbnail_url":"https://media.example.test/poster.webp","order_index":-1},
                  {"kind":"image","source_media_id":"image-source","order_index":3}
                ]}
                """,
                media: [
                    .init(kind: .audio, sourceMediaId: " audio-source ", sourceIndex: 0, thumbnailSourceIndex: 0,
                          url: "", thumbnailUrl: "", orderIndex: 8),
                    .init(kind: .video, sourceMediaId: nil, sourceIndex: -1, thumbnailSourceIndex: 2,
                          url: "https://media.example.test/clip.mp4", thumbnailUrl: "https://media.example.test/poster.webp", orderIndex: -1),
                    .init(kind: .image, sourceMediaId: "image-source", sourceIndex: nil, thumbnailSourceIndex: nil,
                          url: nil, thumbnailUrl: nil, orderIndex: 3)
                ]
            )
        ]
    }

    private static func contentCase(
        name: String, expectedJSON: String, postID: String = "post-test", commonName: String? = nil, notes: String? = nil,
        hashtags: [String] = [], location: ExplorePostLocationSharing = .obscured,
        media: [ExplorePostMediaSelection]? = nil
    ) -> Self {
        Self(
            name: name, function: "update-explore-field-notes", expectedJSON: expectedJSON,
            responseJSON: ExplorePostManagementEndpointResponses.edit, requiresIdempotencyKey: true
        ) { client in
            _ = try await client.updateExplorePostContent(
                postId: postID, speciesCommonName: commonName, fieldNotes: notes,
                hashtags: hashtags, locationSharing: location, mediaItems: media
            )
        }
    }
}
