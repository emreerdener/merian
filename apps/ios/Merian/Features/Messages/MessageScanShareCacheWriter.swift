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
        let imageURL: URL?
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
            imageURL: firstImageURL(for: record, fileManager: fileManager)
        )
    }

    private static func firstImageURL(
        for record: LocalScanRecord,
        fileManager: FileManager
    ) -> URL? {
        for reference in record.capturedMediaSnapshot.imageReferences {
            if let url = imageURL(from: reference, fileManager: fileManager) {
                return url
            }
        }

        if let coverImagePath = trimmedNonEmpty(record.coverImagePath) {
            return imageURL(
                from: StoredMediaReference(legacyPath: coverImagePath),
                fileManager: fileManager
            )
        }

        return nil
    }

    private static func imageURL(
        from reference: StoredMediaReference,
        fileManager: FileManager
    ) -> URL? {
        guard let url = reference.resolvedURL else {
            return nil
        }

        if reference.isRemote {
            let scheme = url.scheme?.lowercased()
            return scheme == "http" || scheme == "https" ? url : nil
        }

        return fileManager.fileExists(atPath: url.path) ? url : nil
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
    ) async {
        do {
            try fileManager.createDirectory(
                at: MessageScanShareCacheStore.thumbnailDirectoryURL(rootURL: rootURL),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: MessageScanShareCacheStore.attachmentDirectoryURL(rootURL: rootURL),
                withIntermediateDirectories: true
            )

            var records: [MessageScanShareCacheRecord] = []
            records.reserveCapacity(sources.count)

            for source in sources {
                let filenames = await renderImages(for: source, rootURL: rootURL, fileManager: fileManager)
                let record = MessageScanShareCacheRecord(
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
                records.append(record)
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
    ) async -> (thumbnail: String?, attachment: String?) {
        guard let imageURL = source.imageURL else {
            return (nil, nil)
        }

        let safeID = safeFilenameComponent(source.id)
        let thumbnailFilename = "thumb-square-v2-\(safeID).jpg"
        let attachmentFilename = "attachment-square-v2-\(safeID).jpg"

        let thumbnailURL = MessageScanShareCacheStore.thumbnailDirectoryURL(rootURL: rootURL)
            .appendingPathComponent(thumbnailFilename)
        let attachmentURL = MessageScanShareCacheStore.attachmentDirectoryURL(rootURL: rootURL)
            .appendingPathComponent(attachmentFilename)

        if !imageURL.isFileURL,
           fileManager.fileExists(atPath: thumbnailURL.path),
           fileManager.fileExists(atPath: attachmentURL.path) {
            return (thumbnailFilename, attachmentFilename)
        }

        let temporaryDownloadURL: URL?
        if imageURL.isFileURL {
            temporaryDownloadURL = nil
        } else {
            temporaryDownloadURL = await downloadRemoteImage(from: imageURL, fileManager: fileManager)
        }

        defer {
            if let temporaryDownloadURL {
                try? fileManager.removeItem(at: temporaryDownloadURL)
            }
        }

        guard let renderSourceURL = temporaryDownloadURL ?? (imageURL.isFileURL ? imageURL : nil) else {
            return (nil, nil)
        }

        let thumbnailWasWritten = writeJPEG(
            sourceURL: renderSourceURL,
            originalSourceURL: imageURL,
            destinationURL: thumbnailURL,
            maxDimension: CGFloat(MessageScanShareCacheConstants.thumbnailMaxDimension),
            fileManager: fileManager
        )
        let attachmentWasWritten = writeJPEG(
            sourceURL: renderSourceURL,
            originalSourceURL: imageURL,
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
        originalSourceURL: URL,
        destinationURL: URL,
        maxDimension: CGFloat,
        fileManager: FileManager
    ) -> Bool {
        if originalSourceURL.isFileURL,
           fileManager.fileExists(atPath: destinationURL.path),
           let sourceAttributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
           let destinationAttributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
           let sourceModifiedAt = sourceAttributes[.modificationDate] as? Date,
           let destinationModifiedAt = destinationAttributes[.modificationDate] as? Date,
           destinationModifiedAt >= sourceModifiedAt {
            return true
        }

        guard let cgImage = ImageDownsampler.downsample(url: sourceURL, maxSize: maxDimension),
              let squareImage = centerSquareCroppedImage(cgImage),
              let data = UIImage(cgImage: squareImage).jpegData(
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

    private func centerSquareCroppedImage(_ image: CGImage) -> CGImage? {
        let side = min(image.width, image.height)
        guard side > 0 else {
            return nil
        }

        let cropRect = CGRect(
            x: CGFloat((image.width - side) / 2),
            y: CGFloat((image.height - side) / 2),
            width: CGFloat(side),
            height: CGFloat(side)
        )
        return image.cropping(to: cropRect) ?? image
    }

    private func downloadRemoteImage(from url: URL, fileManager: FileManager) async -> URL? {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                try? fileManager.removeItem(at: temporaryURL)
                return nil
            }

            let destinationURL = fileManager.temporaryDirectory
                .appendingPathComponent("merian-message-cache-\(UUID().uuidString)")
                .appendingPathExtension(url.pathExtension.isEmpty ? "img" : url.pathExtension)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            return destinationURL
        } catch {
            MerianLog.general.error("Failed to download Messages share image: \(error.localizedDescription, privacy: .private)")
            return nil
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
