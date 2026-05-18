import Foundation
import SwiftData
import UIKit

@MainActor
enum MessageScanShareCacheWriter {
    struct Source: Sendable {
        let id: String
        let commonName: String
        let scientificName: String
        let timestamp: Date
        let locationName: String?
        let confidenceScore: Double?
        let publicExplorePostId: String?
        let fieldNotes: String?
        let localImageURL: URL?
    }

    static func refresh(
        records: [LocalScanRecord],
        fileManager: FileManager = .default
    ) async {
        guard let rootURL = MessageScanShareCacheStore.appGroupRootURL(fileManager: fileManager) else {
            return
        }

        let sources = records
            .filter(\.isBiological)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(MessageScanShareCacheConstants.maxRecordCount)
            .map { source(from: $0, fileManager: fileManager) }

        await MessageScanShareCacheRenderActor.shared.writeCache(
            sources: Array(sources),
            rootURL: rootURL,
            fileManager: fileManager
        )
    }

    private static func source(
        from record: LocalScanRecord,
        fileManager: FileManager
    ) -> Source {
        Source(
            id: record.id,
            commonName: record.commonName,
            scientificName: record.scientificName,
            timestamp: record.timestamp,
            locationName: record.locationName,
            confidenceScore: record.confidenceScore,
            publicExplorePostId: ExploreShareStateStore.sharedPostId(for: record.id),
            fieldNotes: trimmedNonEmpty(record.fieldNotes),
            localImageURL: firstLocalImageURL(for: record, fileManager: fileManager)
        )
    }

    private static func firstLocalImageURL(
        for record: LocalScanRecord,
        fileManager: FileManager
    ) -> URL? {
        for reference in record.capturedMediaSnapshot.imageReferences {
            if let url = localURL(from: reference, fileManager: fileManager) {
                return url
            }
        }

        if let coverImagePath = trimmedNonEmpty(record.coverImagePath) {
            return localURL(
                from: StoredMediaReference(legacyPath: coverImagePath),
                fileManager: fileManager
            )
        }

        return nil
    }

    private static func localURL(
        from reference: StoredMediaReference,
        fileManager: FileManager
    ) -> URL? {
        guard !reference.isRemote,
              let url = reference.resolvedURL,
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return url
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

actor MessageScanShareCacheRenderActor {
    static let shared = MessageScanShareCacheRenderActor()

    func writeCache(
        sources: [MessageScanShareCacheWriter.Source],
        rootURL: URL,
        fileManager: FileManager
    ) {
        do {
            try fileManager.createDirectory(
                at: MessageScanShareCacheStore.thumbnailDirectoryURL(rootURL: rootURL),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: MessageScanShareCacheStore.attachmentDirectoryURL(rootURL: rootURL),
                withIntermediateDirectories: true
            )

            let records = sources.map { source in
                let filenames = renderImages(for: source, rootURL: rootURL, fileManager: fileManager)
                return MessageScanShareCacheRecord(
                    id: source.id,
                    commonName: source.commonName,
                    scientificName: source.scientificName,
                    timestamp: source.timestamp,
                    locationName: source.locationName,
                    confidenceScore: source.confidenceScore,
                    thumbnailFilename: filenames.thumbnail,
                    attachmentFilename: filenames.attachment,
                    publicExplorePostId: source.publicExplorePostId,
                    fieldNotes: source.fieldNotes
                )
            }

            let snapshot = MessageScanShareCacheSnapshot(generatedAt: Date(), records: records)
            try MessageScanShareCacheStore.writeSnapshot(
                snapshot,
                fileManager: fileManager,
                rootURL: rootURL
            )
            MessageScanShareCacheStore.removeImagesNotReferenced(
                by: snapshot,
                fileManager: fileManager,
                rootURL: rootURL
            )
        } catch {
            MerianLog.general.error("Failed to write Messages scan share cache: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func renderImages(
        for source: MessageScanShareCacheWriter.Source,
        rootURL: URL,
        fileManager: FileManager
    ) -> (thumbnail: String?, attachment: String?) {
        guard let localImageURL = source.localImageURL else {
            return (nil, nil)
        }

        let safeID = safeFilenameComponent(source.id)
        let thumbnailFilename = "thumb-\(safeID).jpg"
        let attachmentFilename = "attachment-\(safeID).jpg"

        let thumbnailURL = MessageScanShareCacheStore.thumbnailDirectoryURL(rootURL: rootURL)
            .appendingPathComponent(thumbnailFilename)
        let attachmentURL = MessageScanShareCacheStore.attachmentDirectoryURL(rootURL: rootURL)
            .appendingPathComponent(attachmentFilename)

        let thumbnailWasWritten = writeJPEG(
            sourceURL: localImageURL,
            destinationURL: thumbnailURL,
            maxDimension: CGFloat(MessageScanShareCacheConstants.thumbnailMaxDimension),
            fileManager: fileManager
        )
        let attachmentWasWritten = writeJPEG(
            sourceURL: localImageURL,
            destinationURL: attachmentURL,
            maxDimension: CGFloat(MessageScanShareCacheConstants.attachmentMaxDimension),
            fileManager: fileManager
        )

        return (
            thumbnailWasWritten ? thumbnailFilename : nil,
            attachmentWasWritten ? attachmentFilename : nil
        )
    }

    private func writeJPEG(
        sourceURL: URL,
        destinationURL: URL,
        maxDimension: CGFloat,
        fileManager: FileManager
    ) -> Bool {
        if fileManager.fileExists(atPath: destinationURL.path),
           let sourceAttributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
           let destinationAttributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
           let sourceModifiedAt = sourceAttributes[.modificationDate] as? Date,
           let destinationModifiedAt = destinationAttributes[.modificationDate] as? Date,
           destinationModifiedAt >= sourceModifiedAt {
            return true
        }

        guard let cgImage = ImageDownsampler.downsample(url: sourceURL, maxSize: maxDimension),
              let data = UIImage(cgImage: cgImage).jpegData(
                compressionQuality: MessageScanShareCacheConstants.imageCompressionQuality
              ) else {
            return false
        }

        do {
            try data.write(to: destinationURL, options: [.atomic])
            return true
        } catch {
            MerianLog.general.error("Failed to write Messages share image: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private func safeFilenameComponent(_ rawValue: String) -> String {
        let joined = rawValue
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return joined.isEmpty ? UUID().uuidString : joined
    }
}
