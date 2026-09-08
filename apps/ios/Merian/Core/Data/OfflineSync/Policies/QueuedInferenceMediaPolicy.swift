import Foundation

/// Lightweight manifest checks for media entering durable queue inference.
///
/// Byte-level existence, size, and RIFF/WAVE validation remains owned by
/// `MediaStagingContract` before upload signing.
enum QueuedInferenceMediaPolicy {
    static func containsUnsupportedAudio(
        in snapshot: CapturedMediaSnapshot
    ) -> Bool {
        snapshot.refinementAudioReferences.contains { reference in
            localWAVURL(for: reference) == nil
        }
    }

    private static func localWAVURL(
        for reference: StoredMediaReference
    ) -> URL? {
        let url: URL
        switch reference.storage {
        case .documents:
            guard !reference.path.hasPrefix("/"),
                  let components = URLComponents(string: reference.path),
                  components.scheme == nil,
                  components.host == nil,
                  !reference.path.split(separator: "/").contains("..") else {
                return nil
            }
            url = URL(fileURLWithPath: reference.path)
        case .absolutePath:
            if reference.path.hasPrefix("file://") {
                guard let components = URLComponents(string: reference.path),
                      components.user == nil,
                      components.password == nil,
                      (components.host ?? "").isEmpty ||
                        components.host?.caseInsensitiveCompare("localhost") ==
                        .orderedSame,
                      let fileURL = components.url,
                      fileURL.isFileURL else {
                    return nil
                }
                url = fileURL
            } else {
                guard reference.path.hasPrefix("/") else { return nil }
                url = URL(fileURLWithPath: reference.path)
            }
        case .remoteURL:
            return nil
        }

        guard url.pathExtension.caseInsensitiveCompare("wav") == .orderedSame
        else {
            return nil
        }
        return url
    }
}
