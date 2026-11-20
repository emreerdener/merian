import Foundation

/// One explicit input snapshot. Construction freezes identities; verification does not replace bytes.
struct CaptureAudioReanalysisPlan: Sendable {
    enum Choice: Equatable, Sendable { case audio(Data), description(String) }
    let source: ObservationReanalysisSource
    let choices: [Choice]
    let analysisID: UUID
    let mediaID: UUID

    init(source: ObservationReanalysisSource, choices: [Choice]) throws {
        guard (1...64).contains(choices.count) else { throw MerianError.invalidResponse }
        var audioCount = 0
        for choice in choices {
            switch choice {
            case let .audio(bytes):
                guard ObservationAudioContainer.isValid(bytes) else { throw MerianError.invalidResponse }
                audioCount += 1
            case let .description(text):
                guard text.utf8.count <= 131_072 else { throw MerianError.invalidResponse }
            }
        }
        guard audioCount == 1 else { throw MerianError.invalidResponse }
        self.source = source; self.choices = choices
        analysisID = UUID(); mediaID = UUID()
    }

    struct Verified: Sendable {
        let proof: ObservationAudioPreparation.Verified
        let bytes: Data
    }

    /// Run off-main; strict existing codecs own the actual WAV and description contract.
    func verify() throws -> Verified {
        var bytes = Data()
        let evidence: [ObservationAudioReanalysisRequest.Evidence] = try choices.map { choice in
            switch choice {
            case let .description(text): return .description(text)
            case let .audio(value):
                bytes = value
                return .audio(try ObservationAudioEvidenceUpload(observationID: source.observationID,
                    analysisID: analysisID, mediaID: mediaID, bytes: value).prepare().reference)
            }
        }
        let preparation = try ObservationAudioPreparation(identity: .init(observationID: source.observationID,
            sourceAnalysisID: source.analysisID, analysisID: analysisID, ownerID: source.ownerID),
            evidence: evidence, source: source, action: .submit)
        return try Verified(proof: preparation.verified(source: source), bytes: bytes)
    }
}
