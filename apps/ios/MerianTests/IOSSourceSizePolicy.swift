import Foundation

/// Shared numeric policy for the fast preflight and the selected architecture tests.
/// Other domain and aggregate architecture rules remain in their owning tests.
struct IOSSourceSizePolicy: Decodable {
    struct Rule: Decodable {
        let counter: Counter
        let ceiling: Int

        enum Counter: String, Decodable {
            case physical, segments
        }

        func count(_ source: String) -> Int {
            switch counter {
            case .physical: IOSSourceSizePolicy.physicalLines(source)
            case .segments: IOSSourceSizePolicy.newlineSegments(source)
            }
        }
    }

    let version: Int
    let productionRoot: String
    let globalCeiling: Int
    let oversizedOwners: Set<String>
    let sealedOwnerCeilings: [String: Int]
    let directoryRules: [String: Rule]
    let fileRules: [String: Rule]
    let globalOnlyDirectories: [String]
    let globalOnlyFiles: [String]

    static func load(root: URL) throws -> Self {
        let url = root.appendingPathComponent("scripts/config/ios-source-size-policy.json")
        let policy = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard policy.version == 1,
              policy.globalCeiling > 0,
              policy.directoryRules.values.allSatisfy({ $0.ceiling > 0 }),
              policy.fileRules.values.allSatisfy({ $0.ceiling > 0 }),
              policy.sealedOwnerCeilings.values.allSatisfy({ $0 > 0 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return policy
    }

    static func newlineSegments(_ source: String) -> Int {
        source.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    static func physicalLines(_ source: String) -> Int {
        guard !source.isEmpty else { return 0 }
        return newlineSegments(source) - (source.hasSuffix("\n") ? 1 : 0)
    }
}
