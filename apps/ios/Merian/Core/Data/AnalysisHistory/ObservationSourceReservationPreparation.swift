import Foundation
import SwiftData

/// Private source handoff variants. Photo v9 keeps its exact historical envelope.
enum ObservationSourceReservationPreparation: Equatable, Sendable {
    case photo(ObservationReanalysisPreparationIntent)
    case audio(ObservationAudioPreparation)

    var identity: OfflineQueueWork.Reanalysis {
        switch self {
        case let .photo(value): value.draft.identity
        case let .audio(value): value.identity
        }
    }
    var version: Int {
        switch self {
        case .photo: 9
        case .audio: 10
        }
    }

    func storedData() throws -> Data {
        switch self {
        case let .photo(value): try value.storedData()
        case let .audio(value): try value.storedData(phase: .admissionPending)
        }
    }

    static func decode(_ data: Data, version: Int) throws -> Self {
        switch version {
        case 9: return try .photo(.decode(data))
        case 10:
            let saved = try ObservationAudioPreparation.decode(data)
            guard saved.phase == .admissionPending else { throw MerianError.invalidResponse }
            return .audio(saved.preparation)
        default: throw MerianError.invalidResponse
        }
    }

    func validate(_ request: ObservationSourceReservationRequest) throws {
        guard request.observationID == identity.observationID, request.analysisID == identity.analysisID,
              request.sourceAnalysisID == identity.sourceAnalysisID else { throw MerianError.invalidResponse }
        switch self {
        case let .photo(value):
            let saved = try ObservationReanalysisRequest(savedBody: request.input)
            guard value.action == .submit, saved.evidence == value.draft.evidence else { throw MerianError.invalidResponse }
        case let .audio(value):
            let saved = try ObservationAudioReanalysisRequest(savedBody: request.input)
            guard value.action == .submit, saved.evidence == value.evidence else { throw MerianError.invalidResponse }
        }
    }

    @MainActor func validateRow(_ row: OfflineQueuedScan, job: OfflineJobRecord) throws {
        switch self {
        case let .photo(value):
            try ObservationReanalysisAdmissionStore.validatePristinePair(identity, preparation: value, row: row, job: job)
        case let .audio(value): try ObservationAudioPreparationStore.validateRow(value, row: row, job: job)
        }
    }

    func verified(source: ObservationReanalysisSource) throws -> Verified {
        switch self {
        case let .photo(value): try .photo(value.verified(source: source))
        case let .audio(value): try .audio(value.verified(source: source))
        }
    }

    enum Verified: Sendable {
        case photo(ObservationReanalysisPreparationIntent.Verified)
        case audio(ObservationAudioPreparation.Verified)
        var preparation: ObservationSourceReservationPreparation {
            switch self {
            case let .photo(value): .photo(value.pending)
            case let .audio(value): .audio(value.preparation)
            }
        }
        @MainActor func validate(context: ModelContext) throws {
            switch self {
            case let .photo(value): try value.validate(context: context)
            case let .audio(value): try value.validate(context: context)
            }
        }
    }
}
