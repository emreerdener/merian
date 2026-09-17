import SwiftData

private func firstThumbnailImagePath(in items: [SerializedMediaItem]) -> String? {
    CapturedMediaSnapshot(items: items).primaryImagePath
}

private func replaceCapturedMediaEntries(
    on record: LocalScanRecord,
    items: [SerializedMediaItem]
) {
    let newEntries = CapturedMediaEntry.makeEntries(from: items)

    if let context = record.modelContext {
        for existingEntry in record.capturedMediaEntries ?? [] {
            context.delete(existingEntry)
        }
    }

    record.capturedMediaEntries = newEntries
}

private func replaceCapturedMediaEntries(
    on queuedScan: OfflineQueuedScan,
    items: [SerializedMediaItem]
) {
    let newEntries = CapturedMediaEntry.makeEntries(from: items)

    if let context = queuedScan.modelContext {
        for existingEntry in queuedScan.capturedMediaEntries ?? [] {
            context.delete(existingEntry)
        }
    }

    queuedScan.capturedMediaEntries = newEntries
}

private func resolvedSerializedMediaItems(
    capturedMediaJSON: String?,
    capturedMediaEntries: @autoclosure () -> [CapturedMediaEntry]?
) -> [SerializedMediaItem] {
    // Prefer scalar JSON so SwiftUI read paths do not fault relationship rows during layout.
    if let capturedMediaJSON,
       let jsonItems = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
        return jsonItems
    }

    let capturedMediaEntries = capturedMediaEntries()
    if let capturedMediaEntries, !capturedMediaEntries.isEmpty {
        return CapturedMediaEntry.serializedItems(from: capturedMediaEntries)
    }

    return []
}

extension LocalScanRecord {
    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: serializedCapturedMediaItems)
    }

    var serializedCapturedMediaItems: [SerializedMediaItem] {
        resolvedSerializedMediaItems(
            capturedMediaJSON: capturedMediaJSON,
            capturedMediaEntries: capturedMediaEntries
        )
    }

    func replaceCapturedMedia(with items: [SerializedMediaItem]) {
        capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        coverImagePath = firstThumbnailImagePath(in: items)
        replaceCapturedMediaEntries(on: self, items: items)
    }
}

extension OfflineQueuedScan {
    var capturedMediaSnapshot: CapturedMediaSnapshot {
        CapturedMediaSnapshot(items: serializedCapturedMediaItems)
    }

    var serializedCapturedMediaItems: [SerializedMediaItem] {
        resolvedSerializedMediaItems(
            capturedMediaJSON: capturedMediaJSON,
            capturedMediaEntries: capturedMediaEntries
        )
    }

    func replaceCapturedMedia(with items: [SerializedMediaItem]) {
        capturedMediaJSON = MediaJSONParser.jsonString(from: items)
        coverImagePath = firstThumbnailImagePath(in: items)
        replaceCapturedMediaEntries(on: self, items: items)
    }
}
