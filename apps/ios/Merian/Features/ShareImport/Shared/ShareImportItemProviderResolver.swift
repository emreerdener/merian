import Foundation
import UniformTypeIdentifiers

enum ShareImportItemProviderError: LocalizedError {
    case noImage
    case loadFailed

    var errorDescription: String? {
        switch self {
        case .noImage:
            return "Choose one image to identify with Merian."
        case .loadFailed:
            return "Merian could not load that shared image."
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
            if let url = try? await loadFileRepresentation(from: provider, typeIdentifier: typeIdentifier) {
                return url
            }
        }

        for typeIdentifier in supportedTypeIdentifiers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let url = try? await loadDataRepresentation(from: provider, typeIdentifier: typeIdentifier) {
                return url
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

    private static func loadDataRepresentation(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: ShareImportItemProviderError.loadFailed)
                    return
                }

                do {
                    let preferredExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "img"
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(preferredExtension)
                    try data.write(to: destination, options: [.atomic])
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
