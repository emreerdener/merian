import Foundation

/// Immutable input for reference-thumbnail recovery.
///
/// Keeping this value with the Core image pipeline prevents Core actors from
/// depending on a feature-owned SwiftUI component.
struct ScanThumbnailBackfillCandidate: Sendable, Equatable {
    let scanId: String
    let scientificName: String
    let gbifTaxonKey: Int?

    init?(record: LocalScanRecord) {
        guard record.canResolveReferenceThumbnail,
              record.referenceImageUrl?.trimmedNonEmptyValue == nil,
              let identity = Self.referenceIdentity(for: record) else {
            return nil
        }

        scanId = record.id
        scientificName = identity.scientificName
        gbifTaxonKey = identity.gbifTaxonKey
    }

    /// Builds a request for a map thumbnail whose stored owner media is absent
    /// or unreadable. The map may recover archived or stale visual records
    /// because its caller has already established that no captured bitmap can
    /// render.
    init?(missingVisualFallbackFor record: LocalScanRecord) {
        guard record.isBiological,
              record.referenceImageUrl?.trimmedNonEmptyValue == nil,
              let identity = Self.referenceIdentity(for: record) else {
            return nil
        }

        scanId = record.id
        scientificName = identity.scientificName
        gbifTaxonKey = identity.gbifTaxonKey
    }

    private static func referenceIdentity(
        for record: LocalScanRecord
    ) -> (scientificName: String, gbifTaxonKey: Int?)? {
        guard record.hasResolvedBiologicalIdentification else { return nil }

        let override = record.userIdentificationOverride?
            .trimmedNonEmptyValue
        guard let scientificName = override
            ?? record.scientificName.trimmedNonEmptyValue,
            !ReferenceImageVisibilityPolicy.shouldSuppress(
                isHumanSubject: record.isHumanSubject,
                scientificName: scientificName
            ) else {
            return nil
        }

        return (
            scientificName: scientificName,
            gbifTaxonKey: override == nil ? record.gbifTaxonKey : nil
        )
    }
}

extension LocalScanRecord {
    var hasStoredVisualThumbnail: Bool {
        preferredVisualThumbnailPath != nil || capturedMediaSummary.hasImage
    }

    var canResolveReferenceThumbnail: Bool {
        guard isBiological,
              !isLocallyArchived,
              !hasStoredVisualThumbnail,
              hasResolvedBiologicalIdentification else {
            return false
        }

        let effectiveScientificName = userIdentificationOverride?
            .trimmedNonEmptyValue
            ?? scientificName
        return !ReferenceImageVisibilityPolicy.shouldSuppress(
            isHumanSubject: isHumanSubject,
            scientificName: effectiveScientificName
        )
    }

    private var capturedMediaSummary: CapturedMediaSummary {
        capturedMediaSnapshot.summary
    }

    private var preferredVisualThumbnailPath: String? {
        if let coverImagePath = coverImagePath?.trimmedNonEmptyValue {
            return coverImagePath
        }

        return capturedMediaSnapshot.primaryImagePath?.trimmedNonEmptyValue
    }
}
