import Foundation
import SwiftData
import Testing
import UIKit

@testable import Merian

// Shares the parent suite's serialization because these cases use the process registry.
extension LocalImageLoaderTests {
    @MainActor
    @Test func directFilenameOwnershipIsReservedAcrossRegistrationPages() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            LocalScanMediaRecoveryResolver.resetRegisteredRecoveryMappingsForTesting()
            try? FileManager.default.removeItem(at: directory)
        }
        let writtenAt = Date(timeIntervalSince1970: 1_700_000_000)
        let fileName = "\(UUID().uuidString)_scan.webp"
        let localURL = directory.appendingPathComponent(fileName)
        try Data([1]).write(to: localURL)
        try FileManager.default.setAttributes([.modificationDate: writtenAt], ofItemAtPath: localURL.path)
        let missingURL = try #require(URL(
            string: "https://media.merian.app/public_uploads/free/\(UUID().uuidString).webp"
        ))
        let exactURL = try #require(URL(
            string: "https://media.merian.app/public_uploads/free/\(UUID().uuidString)_\(fileName)"
        ))
        let container = try ModelContainer(
            for: LocalScanRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for (index, url) in [missingURL, exactURL].enumerated() {
            let record = LocalScanRecord(
                id: "page-\(index)", speciesId: "synthetic-species",
                scientificName: "Synthetic species", commonName: "Synthetic subject",
                timestamp: writtenAt.addingTimeInterval(TimeInterval(10 + index * 10))
            )
            record.coverImagePath = url.absoluteString
            container.mainContext.insert(record)
        }
        try container.mainContext.save()
        let service = ScanMediaRecoveryRegistrationService(dependencies: .init(
            hasLegacyRecoveryIndex: { true },
            registerStrongEvidenceMappings: { snapshots in
                LocalScanMediaRecoveryResolver.registerStrongEvidenceRecoveryMappings(
                    for: snapshots, documentsDirectory: directory
                )
            },
            registerTimestampMappings: { snapshots in
                // Exercise the real timestamp algorithm without requiring a rescued
                // production SQLite store in this in-memory fixture.
                snapshots.reduce(0) { count, snapshot in
                    count + LocalScanMediaRecoveryResolver.registerTimestampRecoveryMappingsForTesting(
                        scanID: snapshot.scanID, timestamp: snapshot.timestamp ?? writtenAt,
                        remoteImageURLs: snapshot.imagePaths.compactMap { $0.flatMap(URL.init(string:)) },
                        documentsDirectory: directory
                    )
                }
            }
        ))
        _ = try await service.registerMappings(in: container, batchSize: 1)
        #expect(LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: missingURL, documentsDirectory: directory
        ) == nil)
        #expect(LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: exactURL, allowTimestampFallback: false, documentsDirectory: directory
        ) == localURL)
    }

    @MainActor
    @Test func directEvidenceEvictsEarlierTimestampGuessAndOnlyVerifiedMatchesAuthorizeRepair() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            LocalScanMediaRecoveryResolver.resetRegisteredRecoveryMappingsForTesting()
            try? FileManager.default.removeItem(at: directory)
        }
        let writtenAt = Date(timeIntervalSince1970: 1_700_000_000)
        let fileName = "\(UUID().uuidString)_scan.webp"
        let localURL = directory.appendingPathComponent(fileName)
        try Data([1]).write(to: localURL)
        try FileManager.default.setAttributes([.modificationDate: writtenAt], ofItemAtPath: localURL.path)
        let guessURL = try #require(URL(
            string: "https://media.merian.app/public_uploads/free/\(UUID().uuidString).webp"
        ))
        let directURL = try #require(URL(
            string: "https://media.merian.app/public_uploads/free/\(UUID().uuidString)_\(fileName)"
        ))
        #expect(LocalScanMediaRecoveryResolver.registerTimestampRecoveryMappingsForTesting(
            scanID: "earlier-guess", timestamp: writtenAt.addingTimeInterval(10),
            remoteImageURLs: [guessURL], documentsDirectory: directory
        ) == 1)
        #expect(LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: guessURL, documentsDirectory: directory
        ) == localURL)
        #expect(LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: guessURL, allowTimestampFallback: false, documentsDirectory: directory
        ) == nil)
        let record = LocalScanRecord(
            id: UUID().uuidString, speciesId: "synthetic-species",
            scientificName: "Synthetic species", commonName: "Synthetic subject"
        )
        record.coverImagePath = directURL.absoluteString
        #expect(LocalScanMediaRecoveryResolver.registerStrongEvidenceRecoveryMappings(
            for: [LocalScanMediaRecoverySnapshot(record: record)], documentsDirectory: directory
        ) == 1)
        #expect(LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: guessURL, documentsDirectory: directory
        ) == nil)
        #expect(LocalScanMediaRecoveryResolver.existingLocalImageURL(
            for: directURL, allowTimestampFallback: false, documentsDirectory: directory
        ) == localURL)
    }
}

private actor RecoveryDecodeGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

extension LocalImageLoaderTests {
    @MainActor
    @Test(arguments: [false, true])
    func correctedEvidenceBypassesCachedAndInFlightTimestampImages(lateDecode: Bool) async throws {
        let registry = LocalScanMediaRecoveryRegistry()
        let gate = RecoveryDecodeGate()
        let guessedImage = UIImage()
        let correctImage = UIImage()
        let source = try #require(URL(string:
            "https://media.merian.app/public_uploads/free/\(UUID().uuidString).webp"
        ))
        let strongSource = try #require(URL(string:
            "https://media.merian.app/public_uploads/free/\(UUID().uuidString).webp"
        ))
        #expect(registry.registerTimestampMappings(remoteURLs: [source], fileNames: ["guess.webp"]))
        let loader = LocalImageLoader(dependencies: .init(
            existingLocalImageURL: { url in
                registry.fileName(for: url).map { URL(fileURLWithPath: "/tmp/\($0)") }
            },
            recoveryRevision: { _, _ in registry.cacheRevision(for: [source]) },
            decodeImage: { _, key, _ in
                if lateDecode { await gate.suspend() }
                ImageCache.shared.set(guessedImage, forKey: key)
                return guessedImage
            },
            loadLocalImage: { _, _, _ in nil },
            fetchRemoteImage: { _, key, _ in
                ImageCache.shared.set(correctImage, forKey: key)
                return correctImage
            },
            recordLocalRecovery: { _ in }, enqueueCloudRepair: { _, _ in }
        ))
        let first = Task { await loader.loadImage(fromPath: source.absoluteString) }
        if lateDecode {
            await gate.waitUntilEntered()
        } else {
            #expect(await first.value === guessedImage)
        }
        #expect(registry.registerStrongMapping(remoteURL: strongSource, fileName: "guess.webp"))
        let corrected = await loader.loadImage(fromPath: source.absoluteString)
        #expect(corrected === correctImage)
        if lateDecode {
            await gate.release()
            #expect(await first.value === guessedImage)
        }
        // A late write to the obsolete cache key cannot replace the corrected entry.
        #expect(await loader.loadImage(fromPath: source.absoluteString) === correctImage)
    }
}
