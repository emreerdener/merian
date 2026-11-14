import Foundation

/// An explicit subset, in the source's original mixed-evidence order. Never chooses the first N photos.
struct CaptureReanalysisEvidenceSelection: Sendable {
    let source: ObservationReanalysisSource
    let evidence: [ObservationHistoryPhotoReference.Evidence]
    static let maximumPhotos = 5

    init(source: ObservationReanalysisSource, selectedPhotoIDs: Set<UUID>) throws {
        guard source.audio == nil, selectedPhotoIDs.isSubset(of: Set(source.photos.map(\.mediaID))),
              selectedPhotoIDs.count <= Self.maximumPhotos else { throw ObservationHistoryError.invalidSnapshot }
        var bytes = 0, textUnits = 0
        self.source = source
        self.evidence = try source.evidence.filter { item in
            switch item {
            case let .description(text):
                guard text.utf16.count <= 16384, text.utf16.count <= 32000 - textUnits else { throw MerianError.invalidResponse }
                textUnits += text.utf16.count
                return true
            case let .photo(photo):
                guard selectedPhotoIDs.contains(photo.mediaID) else { return false }
                guard ["image/jpeg", "image/png"].contains(photo.contentType),
                      photo.byteCount <= ObservationEvidenceUpload.maximumBytes - bytes else { throw MerianError.invalidResponse }
                bytes += photo.byteCount
                return true
            }
        }
    }
}
