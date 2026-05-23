import Foundation
import UniformTypeIdentifiers

enum ShareImportItemProviderError: LocalizedError {
    case noImage
    case loadFailed
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .noImage:
            return "Choose one image to identify with Merian."
        case .loadFailed:
            return "Merian could not load that shared image."
        case .fileTooLarge:
            return "Choose an image smaller than 50 MB."
        }
    }
}

enum ShareImportItemProviderResolver {
    static let supportedTypeIdentifiers = [
        UTType.image.identifier,
        UTType.heic.identifier,
        UTType.heif.identifier,
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.webP.identifier
    ]

    static func supportsImage(_ provider: NSItemProvider) -> Bool {
        supportedTypeIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
    }

    static func firstImageProvider(in extensionContext: NSExtensionContext?) -> NSItemProvider? {
        extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .first(where: supportsImage)
    }

    static func loadImageFile(from provider: NSItemProvider) async throws -> URL {
        for typeIdentifier in supportedTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            do {
                let url = try await loadFileRepresentation(from: provider, typeIdentifier: typeIdentifier)
                return url
            } catch ShareImportItemProviderError.fileTooLarge {
                throw ShareImportItemProviderError.fileTooLarge
            } catch {
                continue
            }
        }

        for typeIdentifier in supportedTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            do {
                let url = try await loadInPlaceFileRepresentation(from: provider, typeIdentifier: typeIdentifier)
                return url
            } catch ShareImportItemProviderError.fileTooLarge {
                throw ShareImportItemProviderError.fileTooLarge
            } catch {
                continue
            }
        }

        throw ShareImportItemProviderError.loadFailed
    }

    private static func loadFileRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ShareImportItemProviderError.loadFailed)
                    return
                }

                do {
                    try validateSourceImageSize(url)
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension.isEmpty ? "img" : url.pathExtension)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func loadInPlaceFileRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadInPlaceFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: ShareImportItemProviderError.loadFailed)
                    return
                }

                do {
                    try validateSourceImageSize(url)
                    let preferredExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "img"
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(preferredExtension)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func validateSourceImageSize(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize,
              fileSize <= ShareImportSharedConstants.sourceImageMaxBytes else {
            throw ShareImportItemProviderError.fileTooLarge
        }
    }
}
