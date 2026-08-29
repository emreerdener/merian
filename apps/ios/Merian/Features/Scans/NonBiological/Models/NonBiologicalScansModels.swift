import Foundation

enum NonBiologicalScansPresentation {
    static let navigationTitle = "Non-biological"
    static let emptyIconName = "photo.on.rectangle.angled"
    static let emptyTitle = "Empty"
    static let emptyMessage =
        "This collection is currently empty. " +
        "Non-biological items are automatically purged here after 30 days."
    static let retentionMessage =
        "Items in this collection are permanently deleted after 30 days " +
        "to free up space."
    static let reanalysisAction = "Reanalyze as biological"
    static let clearingProgress = "Clearing scans..."
    static let deleteAllAction = "Delete all"
    static let cancelAction = "Cancel"
    static let deleteAllMessage = "This action cannot be undone."
    static let singleDeleteSuccess = "Scan deleted"
    static let clearSuccess = "Scans cleared"
    static let clearFailure = "Couldn't clear scans"
    static let reanalysisStarted = "Reanalysis started"

    static func deleteAllConfirmationTitle(count: Int) -> String {
        "Delete \(count) non-biological scans?"
    }
}

enum NonBiologicalCorrectionReanalysis {
    static let confirmationTitle = "Reanalyze identification?"
    static let confirmationMessage =
        "This identification was marked as non-biological. " +
        "Reanalysis will look for a biological subject using the original capture."
    static let primaryAction = "Reanalyze"
    static let secondaryAction = "Cancel"

    static func refinementRoute(scanId: String) -> AppRoute {
        .refinement(
            scanId: scanId,
            initialDescription: nil,
            entryPoint: .nonBiologicalCorrection
        )
    }
}

struct NonBiologicalScanErasureSnapshot: Equatable, Sendable {
    let id: String
    let mediaPaths: [String]

    init(scan: LocalScanRecord) {
        let snapshot = scan.capturedMediaSnapshot
        id = scan.id
        mediaPaths =
            snapshot.thumbnailImagePaths +
            snapshot.audioPaths +
            snapshot.videoPaths
    }
}

struct NonBiologicalScansRefreshIdentity: Hashable {
    private struct Entry: Hashable {
        let id: String
        let timestamp: Date
        let isBiological: Bool
    }

    private let entries: [Entry]

    init(scans: [LocalScanRecord]) {
        entries = scans.map {
            Entry(
                id: $0.id,
                timestamp: $0.timestamp,
                isBiological: $0.isBiological
            )
        }
    }
}
