import Foundation

/// Unchanged CPM-1 limits. These are byte limits, not claims about decoder RAM.
enum PhotoPreparationPolicy {
    static let contract = "P1-L1"
    static let mib: Int64 = 1_048_576
    static let original: Int64 = 32 * mib
    static let originalCohort: Int64 = 64 * mib
    static let aiCohort: Int64 = 5 * mib
    static let display: Int64 = 4 * mib
    static let displayCohort: Int64 = 8 * mib
    static let metadata: Int64 = mib
    static let package: Int64 = 96 * mib
    static let durable: Int64 = 384 * mib
    static let temporary: Int64 = 192 * mib
    static let minimumFree: Int64 = 544 * mib
    static let maximumPixels: Int64 = 64_000_000
    static let maximumPackages = 4

    static func add(_ values: [Int64]) throws -> Int64 {
        var sum: Int64 = 0
        for value in values {
            let (next, overflow) = sum.addingReportingOverflow(value)
            guard value >= 0, !overflow else { throw PhotoPreparationFailure.inconsistentOwnership }
            sum = next
        }
        return sum
    }

    static func contexts(_ values: [ObservationContext]) throws -> Data {
        guard values.count <= 64 else { throw PhotoPreparationFailure.sizeLimit }
        var units: Int64 = 0
        for value in values {
            // Match the existing photo reanalysis description envelope without
            // trimming or rewriting the durably retained context.
            guard value.freeText.unicodeScalars.count <= 8_192,
                  value.freeText.utf16.count <= 16_384 else { throw PhotoPreparationFailure.sizeLimit }
            units = try add([units, Int64(value.freeText.utf16.count)])
        }
        guard units <= 32_000 else { throw PhotoPreparationFailure.sizeLimit }
        let bytes = try JSONEncoder().encode(values)
        guard bytes.count <= metadata else { throw PhotoPreparationFailure.sizeLimit }
        return bytes
    }

    static func encodeDraft(contexts: [ObservationContext], presentation: [PhotoPreparationImagePresentation] = []) throws -> Data {
        _ = try self.contexts(contexts)
        guard presentation.count <= 2, Set(presentation.map(\.referenceID)).count == presentation.count,
              presentation.allSatisfy({ $0.cropScale.isFinite && $0.cropScale >= 1
                  && $0.cropOffsetX.isFinite && $0.cropOffsetY.isFinite
                  && (0...3).contains($0.cropQuarterTurns) }) else { throw PhotoPreparationFailure.invalidMedia }
        let bytes = try JSONEncoder().encode(PhotoPreparationDraftEnvelope(version: 1, contexts: contexts, presentation: presentation))
        guard bytes.count <= metadata else { throw PhotoPreparationFailure.sizeLimit }
        return bytes
    }

    static func decodeDraft(_ bytes: Data) throws -> PhotoPreparationDraftEnvelope {
        guard bytes.count <= metadata else { throw PhotoPreparationFailure.sizeLimit }
        let decoded = try JSONDecoder().decode(PhotoPreparationDraftEnvelope.self, from: bytes)
        guard decoded.version == 1 else { throw PhotoPreparationFailure.inconsistentOwnership }
        _ = try encodeDraft(contexts: decoded.contexts, presentation: decoded.presentation)
        return decoded
    }

    static func limit(for role: PhotoPreparationRole) -> Int64 {
        switch role {
        case .original: original
        case .aiInput: aiCohort
        case .display: display
        }
    }
}
