import Foundation

/// Explicit caller-selected input only. No history lookup, account lease or operation identity.
struct CaptureAudioInputPreparer: Sendable {
    struct SecurityScope: Sendable {
        let start: @Sendable (URL) -> Bool
        let stop: @Sendable (URL) -> Void
        static let live = Self(start: { $0.startAccessingSecurityScopedResource() },
                               stop: { $0.stopAccessingSecurityScopedResource() })
    }
    let directory: URL
    var securityScope: SecurityScope = .live
    var transcode: @Sendable (URL, URL) async throws -> URL = { source, output in
        try await InferenceAudioPreparer.prepareLocalFile(at: source, outputDirectory: output)
    }

    func prepare(_ source: URL) async throws -> Data {
        guard source.isFileURL, directory.isFileURL else { throw MerianError.invalidResponse }
        try Task.checkCancellation()
        let scoped = securityScope.start(source)
        defer { if scoped { securityScope.stop(source) } }
        let temporary = directory.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        do {
            let output = try await transcode(source, temporary)
            try Task.checkCancellation()
            guard output.isFileURL,
                  output.deletingLastPathComponent().standardizedFileURL == temporary.standardizedFileURL,
                  output.resolvingSymlinksInPath().deletingLastPathComponent() == temporary.resolvingSymlinksInPath(),
                  try output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
                  try output.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw MerianError.invalidResponse
            }
            let handle = try FileHandle(forReadingFrom: output)
            let bytes: Data
            do {
                bytes = try handle.read(upToCount: ScanMediaPayloadPolicy.maxInferenceAudioBytes + 1) ?? Data()
                guard try handle.read(upToCount: 1)?.isEmpty != false else { throw MerianError.invalidResponse }
                try handle.close()
            } catch {
                try? handle.close(); throw error
            }
            guard ObservationAudioContainer.isValid(bytes) else { throw MerianError.invalidResponse }
            try Task.checkCancellation()
            // Cleanup is part of success, not an unretained background task.
            try FileManager.default.removeItem(at: temporary)
            try Task.checkCancellation()
            return bytes
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
