import Foundation
import Testing

@Suite("Core Routing architecture")
struct CoreRoutingArchitectureTests {
    @Test func ownerInventoryAndImportsAreExact() throws {
        let root = try routingRoot()
        let files = try swiftFiles(below: root)
        let actualPaths = Set(files.map { relativePath(of: $0, below: root) })

        #expect(actualPaths == Set(Self.expectedImportsByPath.keys))

        for file in files {
            let path = relativePath(of: file, below: root)
            let source = try contents(of: file)
            #expect(imports(in: source) == Self.expectedImportsByPath[path])
            #expect(
                lineCount(source) <= 600,
                "\(path) exceeds 600 lines"
            )
        }
    }

    @Test func modelsAndPoliciesRemainEffectFree() throws {
        let root = try routingRoot()
        for directory in ["Models", "Policies"] {
            for file in try swiftFiles(
                below: root.appendingPathComponent(directory)
            ) {
                let source = try contents(of: file)
                for forbidden in Self.liveEffectTokens {
                    #expect(
                        !source.contains(forbidden),
                        "\(file.lastPathComponent) resolves \(forbidden)"
                    )
                }
            }
        }
    }

    @Test func declarationsHaveFocusedOwners() throws {
        let root = try routingRoot()
        var sources: [String: String] = [:]
        for file in try swiftFiles(below: root) {
            sources[relativePath(of: file, below: root)] = try contents(
                of: file
            )
        }

        for (declaration, expectedPath) in Self.expectedDeclarationOwners {
            let owners = sources.compactMap { path, source in
                source.contains(declaration) ? path : nil
            }
            #expect(owners == [expectedPath])
        }

        #expect(
            sources["Coordination/AppEventPublisher.swift"]?.contains(
                "PassthroughSubject<AppEvent, Never>"
            ) == true
        )
        #expect(
            sources["Coordination/AppRouteCoordinator.swift"]?.contains(
                "@Observable\nfinal class AppRouteCoordinator:"
            ) == true
        )
    }

    @Test func retiredUtilityOwnersAreAbsent() throws {
        let root = try repositoryRoot()
        for path in Self.retiredPaths {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                )
            )
        }
    }

    @Test func featureRouteConsumptionRemainsFeatureOwned() throws {
        let root = try repositoryRoot()
        let coordinatorTests = try contents(
            of: root.appendingPathComponent(
                "apps/ios/MerianTests/Core/Routing/AppRouteCoordinatorTests.swift"
            )
        )
        for forbidden in [
            "AppDIContainer",
            "CaptureWorkspaceViewModel",
            "import CoreData",
            "import SwiftData",
            "import SwiftUI",
            "import UIKit"
        ] {
            #expect(!coordinatorTests.contains(forbidden))
        }

        let captureRoutingTests = try contents(
            of: root.appendingPathComponent(
                "apps/ios/MerianTests/Features/Capture/Shell/" +
                    "CaptureWorkspaceRoutingTests.swift"
            )
        )
        #expect(
            captureRoutingTests.contains(
                "testMissingScanIsRejectedAndDoesNotStallTheQueue"
            )
        )
    }

    private func routingRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Routing"
        )
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func swiftFiles(below root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else { return [] }

        return try enumerator.compactMap { element in
            guard let file = element as? URL,
                  file.pathExtension == "swift",
                  try file.resourceValues(forKeys: keys).isRegularFile == true
            else { return nil }
            return file
        }
    }

    private func relativePath(of file: URL, below root: URL) -> String {
        file.path.replacingOccurrences(of: root.path + "/", with: "")
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func imports(in source: String) -> Set<String> {
        Set(source.split(separator: "\n").lazy
            .map(String.init)
            .filter { $0.hasPrefix("import ") })
    }

    private func lineCount(_ source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private static let expectedImportsByPath: [String: Set<String>] = [
        "Coordination/AppEventPublisher.swift": ["import Combine"],
        "Coordination/AppRouteCoordinator.swift": [
            "import Foundation",
            "import Observation"
        ],
        "Coordination/AppRouteProtocols.swift": ["import Foundation"],
        "Models/AppEvent.swift": [],
        "Models/AppRouteModels.swift": ["import Foundation"],
        "Policies/AppRoutePolicy.swift": ["import Foundation"]
    ]

    private static let expectedDeclarationOwners = [
        "enum AppEvent: Sendable": "Models/AppEvent.swift",
        "final class AppEventPublisher":
            "Coordination/AppEventPublisher.swift",
        "enum AppRoute: Sendable": "Models/AppRouteModels.swift",
        "final class AppRouteCoordinator":
            "Coordination/AppRouteCoordinator.swift",
        "extension AppRoute {": "Policies/AppRoutePolicy.swift",
        "protocol AppRouteRequesting":
            "Coordination/AppRouteProtocols.swift"
    ]

    private static let liveEffectTokens = [
        ".shared",
        "AppDIContainer",
        "MerianNetworkClient",
        "NotificationCenter",
        "SupabaseManager",
        "URLSession",
        "UserDefaults.standard"
    ]

    private static let retiredPaths = [
        "apps/ios/Merian/Core/Utilities/AppEventPublisher.swift",
        "apps/ios/Merian/Core/Utilities/AppRouteCoordinator.swift"
    ]
}
