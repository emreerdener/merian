import Foundation

/// Maps only the final staged timeline; removed originals are never reinserted.
enum CaptureReanalysisPreparation {
    static func plan(source: ObservationReanalysisSource, capture: StagedCapture) throws -> ObservationReanalysisPreparationPlan {
        let choices: [ObservationReanalysisPreparationPlan.Choice] = try capture.orderedNodes.map { node in
            switch node {
            case let .description(_, value): return .description(value.context.serialized())
            case let .image(_, image):
                switch image.reanalysisProvenance {
                case .added: return .photo(.added(image.compressedData))
                case let .original(analysisID, photo):
                    guard analysisID == source.analysisID else { throw MerianError.invalidResponse }
                    return .photo(.original(photo))
                case let .editedOriginal(analysisID, photo):
                    guard analysisID == source.analysisID else { throw MerianError.invalidResponse }
                    return .photo(.edited(photo, image.compressedData))
                }
            case .audio, .video: throw MerianError.invalidResponse
            }
        }
        return try ObservationReanalysisPreparationPlan(source: source, choices: choices)
    }
}
