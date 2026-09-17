import Foundation
@testable import Merian
import Testing

@Suite("Offline Queue Policy")
struct OfflineQueuePolicyTests {
    @Test func batchBudgetsRetainExactValues() {
        #expect(OfflineQueueBatchPolicy.uploadBatchSize == 5)
        #expect(OfflineQueueBatchPolicy.pendingScanFetchLimit == 50)
    }

    @Test func storageBudgetsRetainExactValues() {
        #expect(
            OfflineQueueStoragePolicy.minimumFreeDiskBytes
                == 100 * 1_024 * 1_024
        )
        #expect(
            OfflineQueueStoragePolicy.singlePayloadSoftLimitBytes
                == 25 * 1_024 * 1_024
        )
    }

    @Test func storageSizingPreservesAdmissionAndQueuedMediaSemantics() throws {
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: localURL) }
        try Data(repeating: 0, count: 7).write(to: localURL)

        #expect(
            OfflineQueueStoragePolicy.approximateBytes(
                for: [localURL, localURL]
            ) == 14
        )
        #expect(
            OfflineQueueStoragePolicy.estimatedBytes(
                for: [localURL.path]
            ) == 7
        )

        let mediaItems: [SerializedMediaItem] = [
            .image(.absolutePath(localURL.path)),
            .audio(.absolutePath(localURL.path)),
            .image(.remoteURL("https://media.merian.app/remote.jpg"))
        ]
        #expect(
            OfflineQueueStoragePolicy.queuedMediaBytes(
                mediaItems: mediaItems,
                inferenceImagePaths: [localURL.absoluteString]
            ) == 7
        )
    }

    @Test func relativeSizingPreservesDocumentsPrecedenceForEmptyFiles() throws {
        let fileName = "offline-storage-policy-\(UUID().uuidString)"
        let documentsURL = URL.documentsDirectory
            .appendingPathComponent(fileName)
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        defer {
            try? FileManager.default.removeItem(at: documentsURL)
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        try Data().write(to: documentsURL)
        try Data(repeating: 0, count: 7).write(to: temporaryURL)

        #expect(
            OfflineQueueStoragePolicy.estimatedBytes(for: [fileName]) == 0
        )
    }
}
