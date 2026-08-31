import Foundation
import Testing

@testable import Merian

@MainActor
struct CommunityIdentificationRequestViewModelTests {
    @Test func requestReplacementRejectsLateDetail() async throws {
        let firstRequestID = UUID().uuidString.lowercased()
        let secondRequestID = UUID().uuidString.lowercased()
        let firstDetail = try makeDetail(
            requestID: firstRequestID,
            note: "Stale note",
            locationSharing: .open
        )
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (responses, responseContinuation) =
            AsyncStream<CommunityIdentificationDetail>.makeStream()
        var startedIterator = started.makeAsyncIterator()

        let viewModel = CommunityIdentificationRequestViewModel(
            initialNote: "Initial",
            initialLocationSharing: .obscured,
            dependencies: CommunityRequestDependencies(
                loadDetail: { _ in
                    startedContinuation.yield()
                    for await response in responses {
                        return response
                    }
                    throw CancellationError()
                }
            )
        )

        let firstLoad = Task { @MainActor in
            await viewModel.loadExistingRequestIfNeeded(
                requestID: firstRequestID,
                initialNote: "Initial",
                initialLocationSharing: .obscured,
                shouldLoadDetail: true
            )
        }
        _ = await startedIterator.next()

        _ = await viewModel.loadExistingRequestIfNeeded(
            requestID: secondRequestID,
            initialNote: "Current note",
            initialLocationSharing: .privateLocation,
            shouldLoadDetail: false
        )
        responseContinuation.yield(firstDetail)
        responseContinuation.finish()
        startedContinuation.finish()
        _ = await firstLoad.value

        #expect(viewModel.note == "Current note")
        #expect(viewModel.locationSharing == .privateLocation)
        #expect(viewModel.loadErrorMessage == nil)
        #expect(!viewModel.isLoading)
    }

    @Test func currentFailureUsesInjectedCustomerMessage() async {
        struct TestError: Error {}
        let requestID = UUID().uuidString.lowercased()
        let viewModel = CommunityIdentificationRequestViewModel(
            initialNote: nil,
            initialLocationSharing: nil,
            dependencies: CommunityRequestDependencies(
                loadDetail: { _ in throw TestError() },
                errorMessage: { _ in "Request temporarily unavailable" }
            )
        )

        let message = await viewModel.loadExistingRequestIfNeeded(
            requestID: requestID,
            initialNote: nil,
            initialLocationSharing: nil,
            shouldLoadDetail: true
        )

        #expect(message == "Request temporarily unavailable")
        #expect(
            viewModel.loadErrorMessage ==
                "Request temporarily unavailable"
        )
        #expect(!viewModel.isLoading)
    }

    @Test func mismatchedCurrentDetailFailsClosed() async throws {
        let requestedID = UUID().uuidString.lowercased()
        let mismatchedDetail = try makeDetail(
            requestID: UUID().uuidString.lowercased(),
            note: "Wrong request",
            locationSharing: .open
        )
        let viewModel = CommunityIdentificationRequestViewModel(
            initialNote: "Keep this draft",
            initialLocationSharing: .obscured,
            dependencies: CommunityRequestDependencies(
                loadDetail: { _ in mismatchedDetail },
                errorMessage: { _ in "Request response did not match" }
            )
        )

        let message = await viewModel.loadExistingRequestIfNeeded(
            requestID: requestedID,
            initialNote: "Keep this draft",
            initialLocationSharing: .obscured,
            shouldLoadDetail: true
        )

        #expect(message == "Request response did not match")
        #expect(viewModel.note == "Keep this draft")
        #expect(viewModel.locationSharing == .obscured)
        #expect(
            viewModel.loadErrorMessage ==
                "Request response did not match"
        )
        #expect(!viewModel.isLoading)
    }

    private func makeDetail(
        requestID: String,
        note: String?,
        locationSharing: ExplorePostLocationSharing
    ) throws -> CommunityIdentificationDetail {
        let postID = UUID().uuidString.lowercased()
        let scanID = UUID().uuidString.lowercased()
        let authorID = UUID().uuidString.lowercased()
        let noteJSON = note.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "request_id": "\(requestID)",
          "post_id": "\(postID)",
          "scan_id": "\(scanID)",
          "hero_image_url": "https://example.com/observation.jpg",
          "requested_at": "2026-08-31T12:00:00Z",
          "status": "needs_id",
          "note": \(noteJSON),
          "author_user_id": "\(authorID)",
          "author_name": "Explorer",
          "identification_count": 0,
          "location_sharing": "\(locationSharing.rawValue)",
          "identifications": []
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(
            CommunityIdentificationDetail.self,
            from: Data(json.utf8)
        )
    }
}
