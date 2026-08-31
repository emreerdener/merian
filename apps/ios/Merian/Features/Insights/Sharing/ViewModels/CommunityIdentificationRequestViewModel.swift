import Foundation
import Observation

@MainActor
@Observable
final class CommunityIdentificationRequestViewModel {
    var note: String
    var locationSharing: ExplorePostLocationSharing
    private(set) var isLoading = false
    private(set) var loadErrorMessage: String?

    @ObservationIgnored private let dependencies: CommunityRequestDependencies
    @ObservationIgnored private var activeRequestID: String?
    @ObservationIgnored private var loadedRequestID: String?
    @ObservationIgnored private var loadGeneration: UInt64 = 0

    init(
        initialNote: String?,
        initialLocationSharing: ExplorePostLocationSharing?,
        dependencies: CommunityRequestDependencies? = nil
    ) {
        note = initialNote ?? ""
        locationSharing = initialLocationSharing ?? .obscured
        self.dependencies = dependencies ?? .live
    }

    var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func loadExistingRequestIfNeeded(
        requestID: String?,
        initialNote: String?,
        initialLocationSharing: ExplorePostLocationSharing?,
        shouldLoadDetail: Bool
    ) async -> String? {
        let trimmedRequestID = requestID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRequestID: String? = if let trimmedRequestID,
                                              !trimmedRequestID.isEmpty {
            trimmedRequestID
        } else {
            nil
        }

        guard let normalizedRequestID else {
            loadGeneration &+= 1
            activeRequestID = nil
            loadedRequestID = nil
            note = initialNote ?? ""
            locationSharing = initialLocationSharing ?? .obscured
            isLoading = false
            loadErrorMessage = nil
            return nil
        }

        if activeRequestID?.caseInsensitiveCompare(normalizedRequestID) !=
            .orderedSame {
            loadGeneration &+= 1
            activeRequestID = normalizedRequestID
            loadedRequestID = nil
            note = initialNote ?? ""
            locationSharing = initialLocationSharing ?? .obscured
            isLoading = false
            loadErrorMessage = nil
        }

        guard loadedRequestID?.caseInsensitiveCompare(normalizedRequestID) !=
            .orderedSame else {
            return nil
        }

        guard shouldLoadDetail else {
            loadedRequestID = normalizedRequestID
            loadErrorMessage = nil
            return nil
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        loadErrorMessage = nil
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }

        do {
            let detail = try await dependencies.loadDetail(normalizedRequestID)
            guard !Task.isCancelled,
                  generation == loadGeneration,
                  activeRequestID?.caseInsensitiveCompare(
                      normalizedRequestID
                  ) == .orderedSame else {
                return nil
            }
            guard detail.requestId.caseInsensitiveCompare(
                normalizedRequestID
            ) == .orderedSame else {
                throw MerianError.invalidResponse
            }
            note = detail.note ?? ""
            locationSharing = detail.locationSharing ??
                initialLocationSharing ?? .obscured
            loadedRequestID = normalizedRequestID
            loadErrorMessage = nil
            return nil
        } catch {
            guard !Task.isCancelled,
                  generation == loadGeneration,
                  activeRequestID?.caseInsensitiveCompare(
                      normalizedRequestID
                  ) == .orderedSame else {
                return nil
            }
            let message = dependencies.errorMessage(error)
            loadErrorMessage = message
            return message
        }
    }
}
