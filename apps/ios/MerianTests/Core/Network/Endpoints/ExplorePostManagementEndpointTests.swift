import Foundation
import Testing

@testable import Merian

@Suite("Explore Post Management Endpoints")
@MainActor
struct ExplorePostManagementEndpointTests {
    private typealias RequestCase = ExplorePostManagementEndpointRequestCase

    @Test func requestInventoryKeepsSixOperationsAndTheSharedEditRoute() {
        #expect(RequestCase.all.count == 36)
        #expect(RequestCase.operations.count == 6)
        #expect(Set(RequestCase.operations.map(\.function)) == [
            "get-explore-composer-media", "get-scan-explore-share-state", "get-explore-media-incidents",
            "unshare-explore-post", "update-explore-field-notes"
        ])
        #expect(RequestCase.replayableOperations.count == 4)
        #expect(RequestCase.nonReplayableMutations.count == 2)
        #expect(RequestCase.rawDecodingOperations.count == 3)
        #expect(RequestCase.mappedDecodingOperations.count == 2)
        #expect(RequestCase.operations.filter(\.requiresIdempotencyKey).count == 1)
    }

    @Test(arguments: ExplorePostManagementEndpointRequestCase.all)
    func requestMappingRemainsStable(_ testCase: ExplorePostManagementEndpointRequestCase) async throws {
        try await testCase.withResponse { client in
            try await testCase.invoke(client)
        }
    }

    @Test func composerKeepsServerSelectionAndMediaOrder() async throws {
        try await RequestCase.composer.withResponse { client in
            let response = try await client.getExploreComposerMedia()
            #expect(response.scanId == "server-scan" && response.postId == "server-post")
            #expect(response.mediaItems.map(\.sourceMediaId) == ["audio-source", "video-source", "image-source"])
            #expect(response.mediaItems.map(\.kind) == [.audio, .video, .image])
            #expect(response.mediaItems.map(\.orderIndex) == [8, 2, 4])
            #expect(response.mediaItems.map(\.isSelected) == [false, true, nil])
            #expect(response.mediaItems.map(\.selectionOrderIndex) == [nil, 0, nil])
            #expect(response.mediaItems.first?.thumbnailUrl == "")
            #expect(response.mediaItems[1].url == "https://media.example.test/clip.mp4")
            #expect(response.mediaItems[1].thumbnailUrl == "https://media.example.test/poster.webp")
        }
    }

    @Test func composerAllowsEmptyMediaAndMissingPostWithoutInventingASelection() async throws {
        try await RequestCase.composer.withResponse(#"{"data":{"scan_id":"server-scan","media_items":[]}}"#) { client in
            let response = try await client.getExploreComposerMedia()
            #expect(response.scanId == "server-scan" && response.postId == nil)
            #expect(response.mediaItems.isEmpty)
        }
    }

    @Test(arguments: [
        ExplorePostManagementEndpointRequestCase.notesEdit,
        ExplorePostManagementEndpointRequestCase.contentEdit
    ])
    func editResponsesKeepServerValuesAndCallerOwnedSuccess(
        _ testCase: ExplorePostManagementEndpointRequestCase
    ) async throws {
        try await testCase.withResponse { client in
            let response = try await editResponse(for: testCase, client: client)
            #expect(!response.success)
            #expect(response.postId == "server-post")
            #expect(response.fieldNotes == "  Server notes  ")
            #expect(response.hashtags == ["server", "tags"])
            #expect(response.speciesCommonName == "Server name")
            #expect(response.locationSharing == .privateLocation)
        }
    }

    @Test(arguments: [
        ExplorePostManagementEndpointRequestCase.notesEdit,
        ExplorePostManagementEndpointRequestCase.contentEdit
    ], [#"{"success":true,"post_id":""}"#,
        #"{"success":true,"post_id":"","field_notes":null,"hashtags":null,"species_common_name":null,"location_sharing":null}"#])
    func editOptionalFieldsRemainOptional(
        _ testCase: ExplorePostManagementEndpointRequestCase, json: String
    ) async throws {
        try await testCase.withResponse(json) { client in
            let response = try await editResponse(for: testCase, client: client)
            #expect(response.success && response.postId == "")
            #expect(response.fieldNotes == nil && response.hashtags == nil)
            #expect(response.speciesCommonName == nil && response.locationSharing == nil)
        }
    }

    private func editResponse(
        for testCase: ExplorePostManagementEndpointRequestCase, client: MerianNetworkClient
    ) async throws -> ExploreUpdateFieldNotesResponse {
        if testCase.requiresIdempotencyKey {
            return try await client.updateExplorePostContent(
                postId: "post-test", fieldNotes: nil, hashtags: [], locationSharing: .obscured
            )
        }
        return try await client.updateExplorePostFieldNotes(postId: "post-test", fieldNotes: nil)
    }
}
