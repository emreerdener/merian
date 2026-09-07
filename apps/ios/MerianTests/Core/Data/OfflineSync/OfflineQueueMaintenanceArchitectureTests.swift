import Foundation
import Testing

@Suite("Offline Queue Maintenance Architecture")
struct OfflineQueueMaintenanceArchitectureTests {
    @Test func focusedFilesAndDeclarationsHaveExactOwners() throws {
        let root = try offlineSyncRoot()
        let sources = try swiftFiles(below: root)
        let maintenanceRoot = root.appendingPathComponent(
            "Services/QueueMaintenance"
        )
        let maintenancePaths = try swiftFiles(below: maintenanceRoot).map {
            relativePath(of: $0, below: root)
        }

        #expect(Set(maintenancePaths) == Set(Self.expectedImportsByPath.keys))

        for (declaration, expectedPath) in Self.declarationOwners {
            let owners = try sources.compactMap { file -> String? in
                let source = try contents(of: file)
                guard containsDeclaration(declaration, in: source) else {
                    return nil
                }
                return relativePath(of: file, below: root)
            }
            #expect(owners == [expectedPath])
        }
    }

    @Test func focusedFilesStayBoundedAndDependencyFocused() throws {
        let root = try offlineSyncRoot()

        for (path, expectedImports) in Self.expectedImportsByPath {
            let source = try contents(
                of: root.appendingPathComponent(path)
            )
            #expect(
                lineCount(of: source) <= 600,
                "\(path) exceeds the 600-line review ceiling"
            )
            #expect(
                imports(in: source) == expectedImports,
                "\(path) has an unexpected framework dependency"
            )
        }
    }

    @Test func responsibilitiesAndDestructiveOrderingRemainContained() throws {
        let root = try offlineSyncRoot()
        let state = try source(
            "Services/QueueMaintenance/OfflineQueueManager+QueueState.swift",
            below: root
        )
        let deletion = try source(
            "Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift",
            below: root
        )
        let goalHints = try source(
            "Persistence/ModelContext+FieldTripGoalHints.swift",
            below: root
        )

        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "OfflineQueueManager+Queue.swift"
                ).path
            )
        )

        #expect(!state.contains("backgroundSession"))
        #expect(!state.contains("FileIOActor"))
        #expect(state.contains("PushNotificationManager.shared"))
        #expect(deletion.contains(
            "private func deleteQueuedScanAssumingPersistenceLock("
        ))
        #expect(deletion.contains(
            "private func clearForegroundInferenceOwnershipAfterDeletion("
        ))
        #expect(!deletion.contains("PushNotificationManager"))
        #expect(!deletion.contains("UIApplication"))
        #expect(goalHints.contains("extension ModelContext"))
        #expect(!goalHints.contains("extension OfflineQueueManager"))

        let normalized = normalizedSource(deletion)
        let persistenceLock = try #require(normalized.range(
            of: "ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)"
        ))
        let lockedDelete = try #require(normalized.range(
            of: "deleteQueuedScanAssumingPersistenceLock(",
            range: persistenceLock.upperBound..<normalized.endIndex
        ))
        let release = try #require(normalized.range(
            of: "ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)",
            range: lockedDelete.upperBound..<normalized.endIndex
        ))
        #expect(persistenceLock.lowerBound < lockedDelete.lowerBound)
        #expect(lockedDelete.lowerBound < release.lowerBound)

        let rowDelete = try #require(normalized.range(
            of: "context.delete(scan)"
        ))
        let committedSave = try #require(normalized.range(
            of: "try context.save()",
            range: rowDelete.upperBound..<normalized.endIndex
        ))
        let fileDelete = try #require(normalized.range(
            of: "await FileIOActor.shared.deleteFiles",
            range: committedSave.upperBound..<normalized.endIndex
        ))
        #expect(rowDelete.lowerBound < committedSave.lowerBound)
        #expect(committedSave.lowerBound < fileDelete.lowerBound)
    }

    private static let declarationOwners: [String: String] = [
        "func flushOfflineQueuedScan":
            "Services/QueueMaintenance/OfflineQueueManager+QueueState.swift",
        "func updateUnsyncedItemCount":
            "Services/QueueMaintenance/OfflineQueueManager+QueueState.swift",
        "func softDeleteQueuedScan":
            "Services/QueueMaintenance/OfflineQueueManager+QueueState.swift",
        "func deleteQueuedScan":
            "Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift",
        "func deleteQueuedScanAssumingPersistenceLock":
            "Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift",
        "func clearForegroundInferenceOwnershipAfterDeletion":
            "Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift",
        "func purgeSoftDeletedRecords":
            "Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift",
        "func deletePreferredGoalHint":
            "Persistence/ModelContext+FieldTripGoalHints.swift",
        "func fetchOfflineJob":
            "Persistence/ModelContext+OfflineJobs.swift"
    ]

    private static let expectedImportsByPath: [String: Set<String>] = [
        "Services/QueueMaintenance/OfflineQueueManager+QueueState.swift": [
            "import Foundation",
            "import SwiftData",
            "import UIKit"
        ],
        "Services/QueueMaintenance/OfflineQueueManager+QueueDeletion.swift": [
            "import Foundation",
            "import SwiftData"
        ]
    ]

    private func offlineSyncRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Data/OfflineSync"
        )
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func source(_ path: String, below root: URL) throws -> String {
        try contents(of: root.appendingPathComponent(path))
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func imports(in source: String) -> Set<String> {
        Set(
            source.split(separator: "\n")
                .map(String.init)
                .filter { $0.hasPrefix("import ") }
        )
    }

    private func lineCount(of source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private func normalizedSource(_ source: String) -> String {
        source.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func relativePath(of file: URL, below root: URL) -> String {
        file.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }
        return try enumerator.compactMap { element in
            guard let file = element as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: keys).isRegularFile == true
            else {
                return nil
            }
            return file
        }
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: declaration)
        let pattern =
            #"(?m)^\s*(?:(?:private|fileprivate|internal|package|public|final|static|nonisolated)\s+)*"#
            + escaped
            + #"(?:\s*[:(<{=])"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }
}
