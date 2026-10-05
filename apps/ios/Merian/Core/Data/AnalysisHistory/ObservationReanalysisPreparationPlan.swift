import Foundation

/// A final explicit evidence selection. Construct once; never mint replacement IDs on retry.
struct ObservationReanalysisPreparationPlan: Sendable {
    enum Photo: Sendable {
        case original(ObservationHistoryPhotoReference)
        case added(Data)
        case edited(ObservationHistoryPhotoReference, Data)
    }
    enum Choice: Sendable { case photo(Photo), description(String) }
    enum Item: Sendable { case photo(UUID, Photo), description(String) }
    let source: ObservationReanalysisSource
    let analysisID: UUID
    let items: [Item]

    init(source: ObservationReanalysisSource, choices: [Choice], analysisID: UUID = UUID(), makeMediaID: () -> UUID = UUID.init) throws {
        guard (1...64).contains(choices.count), analysisID != source.observationID, analysisID != source.analysisID else {
            throw MerianError.invalidResponse
        }
        var used = Set(source.photos.map(\.mediaID) + [source.observationID, source.analysisID, analysisID, source.ownerID])
        var items: [Item] = [], count = 0, bytes = 0, textUnits = 0
        for choice in choices {
            switch choice {
            case let .description(text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.unicodeScalars.count <= 8192,
                      text.utf16.count <= 16384, text.utf16.count <= 32000 - textUnits else { throw MerianError.invalidResponse }
                textUnits += text.utf16.count; items.append(.description(text))
            case let .photo(photo):
                let length: Int
                switch photo {
                case let .original(reference):
                    guard source.photos.contains(reference), ["image/jpeg", "image/png"].contains(reference.contentType) else { throw MerianError.invalidResponse }
                    length = reference.byteCount
                case let .edited(reference, data):
                    guard source.photos.contains(reference) else { throw MerianError.invalidResponse }
                    length = data.count
                case let .added(data): length = data.count
                }
                count += 1
                guard count <= 5, length > 0, length <= ObservationEvidenceUpload.maximumBytes - bytes else { throw MerianError.invalidResponse }
                bytes += length
                let mediaID = makeMediaID()
                guard used.insert(mediaID).inserted else { throw MerianError.invalidResponse }
                items.append(.photo(mediaID, photo))
            }
        }
        guard count > 0 else { throw MerianError.invalidResponse }
        self.source = source; self.analysisID = analysisID; self.items = items
    }
}
