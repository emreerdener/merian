import Foundation

enum CaptureWorkspacePresentationPolicy {
    static func messageShareCacheSignature(
        records: [LocalScanRecord],
        defaultGeoprivacy: String,
        sharedPostId: (_ scanId: String) -> String?
    ) -> String {
        records
            .prefix(MessageScanShareCacheConstants.maxRecordCount)
            .map { record in
                [
                    record.id,
                    String(record.timestamp.timeIntervalSinceReferenceDate),
                    record.commonName,
                    record.scientificName,
                    record.locationName ?? "",
                    record.coverImagePath ?? "",
                    record.capturedMediaSnapshot.imagePaths.joined(separator: ","),
                    record.fieldNotes ?? "",
                    sharedPostId(record.id) ?? "",
                    defaultGeoprivacy
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }
}
