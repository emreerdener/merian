import Foundation

enum InferenceURLSessionTaskContract {
    private static let currentPrefix = "inference_v3"
    private static let generationOnlyPrefix = "inference_v2"
    private static let legacyPrefix = "inference_"

    static func taskDescription(
        scanId: String,
        generation: UUID,
        ownerUserID: UUID
    ) -> String {
        "\(currentPrefix)|\(ownerUserID.uuidString.lowercased())|\(generation.uuidString.lowercased())|\(scanId)"
    }

    static func parse(_ description: String?) -> InferenceURLSessionTaskIdentity? {
        guard let description else { return nil }

        if description.hasPrefix("\(currentPrefix)|") {
            let parts = description.split(
                separator: "|",
                maxSplits: 3,
                omittingEmptySubsequences: false
            )
            guard parts.count == 4,
                  String(parts[0]) == currentPrefix,
                  let ownerUserID = UUID(uuidString: String(parts[1])),
                  let generation = UUID(uuidString: String(parts[2])),
                  !parts[3].isEmpty else {
                return nil
            }
            return InferenceURLSessionTaskIdentity(
                scanId: String(parts[3]),
                generation: generation,
                ownerUserID: ownerUserID
            )
        }

        if description.hasPrefix("\(generationOnlyPrefix)|") {
            let parts = description.split(
                separator: "|",
                maxSplits: 2,
                omittingEmptySubsequences: false
            )
            guard parts.count == 3,
                  String(parts[0]) == generationOnlyPrefix,
                  let generation = UUID(uuidString: String(parts[1])),
                  !parts[2].isEmpty else {
                return nil
            }
            return InferenceURLSessionTaskIdentity(
                scanId: String(parts[2]),
                generation: generation,
                ownerUserID: nil
            )
        }

        guard description.hasPrefix(legacyPrefix) else { return nil }
        let scanId = String(description.dropFirst(legacyPrefix.count))
        guard !scanId.isEmpty else { return nil }
        return InferenceURLSessionTaskIdentity(
            scanId: scanId,
            generation: nil,
            ownerUserID: nil
        )
    }
}
