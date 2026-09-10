import Foundation
@testable import Merian
import XCTest

final class StoreRecoveryArchitectureTests: XCTestCase {
    func testRecoveryCoordinatorDoesNotReferenceAuthOrSessionManagers() throws {
        let forbiddenTokens = [
            "KeychainManager",
            "SupabaseManager",
            "PostHogManager.shared.reset",
            "signOut(",
            "initializeGhostSession",
            "currentUser"
        ]
        let sources = try productionSwiftSources()

        let violations = try sources.flatMap { sourceURL in
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            return forbiddenTokens.compactMap { token in
                source.contains(token)
                    ? "\(sourceURL.lastPathComponent):\(token)"
                    : nil
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Store recovery must remain isolated from auth/session state. " +
                "Violations: \(violations.joined(separator: ", "))"
        )
    }

    func testStoreRecoveryDeclarationsHaveFocusedOwners() throws {
        let expectedOwners = [
            ("enum ModelStoreRecoveryCoordinator {", "ModelStoreRecoveryCoordinator.swift"),
            ("enum RecentSourceSchema:", "StoreMigrationModels.swift"),
            ("struct StoreMigrationDecision:", "StoreMigrationModels.swift"),
            ("struct StartupStoreDiagnostic:", "StartupStoreDiagnostic.swift"),
            ("enum StoreRecoveryJSONCoding {", "StoreRecoveryJSONCoding.swift"),
            ("struct ModelStoreRecoveryManifest:", "StoreRecoveryManifest.swift"),
            ("enum StoreRecoveryErrorPolicy {", "ModelStoreRecoveryPolicy.swift"),
            ("enum StoreRecoveryPrivacyPolicy {", "StoreRecoveryPrivacyPolicy.swift"),
            ("enum StoreRecoveryMetadataService {", "StoreRecoveryMetadataService.swift"),
            ("enum StoreRecoveryArtifactArchiver {", "StoreRecoveryArtifactArchiver.swift")
        ]
        let sources = try productionSwiftSources()

        for (declarationMarker, expectedFilename) in expectedOwners {
            let owners = try sources.filter { sourceURL in
                try String(contentsOf: sourceURL, encoding: .utf8)
                    .contains(declarationMarker)
            }
            XCTAssertEqual(
                owners.map(\.lastPathComponent),
                [expectedFilename],
                "\(declarationMarker) must remain solely in \(expectedFilename)."
            )
        }
    }

    func testStoreRecoveryProductionFilesStayWithinReviewGuard() throws {
        try assertFilesStayWithinReviewGuard(productionSwiftSources())
    }

    func testStoreRecoveryTestFilesStayWithinReviewGuard() throws {
        try assertFilesStayWithinReviewGuard(
            swiftSources(under: testSourceRoot)
        )
    }

    func testPureStoreRecoveryLayersDoNotOwnEffects() throws {
        let pureDirectories = ["Models", "Policies"]
        let forbiddenImports = [
            "import SwiftUI",
            "import Supabase",
            "import RevenueCat"
        ]

        for directory in pureDirectories {
            let directoryURL = storeRecoverySourceRoot
                .appendingPathComponent(directory, isDirectory: true)
            for sourceURL in try swiftSources(under: directoryURL) {
                let source = try String(
                    contentsOf: sourceURL,
                    encoding: .utf8
                )
                let violations = forbiddenImports.filter { source.contains($0) }
                XCTAssertTrue(
                    violations.isEmpty,
                    "\(sourceURL.lastPathComponent) has effect imports: " +
                        violations.joined(separator: ", ")
                )
            }
        }
    }

    func testStoreRecoveryTestsUseMirroredOwnership() throws {
        let legacyTestURL = iosRoot
            .appendingPathComponent("MerianTests")
            .appendingPathComponent("App")
            .appendingPathComponent("ModelStoreRecoveryCoordinatorTests.swift")
        let expectedTestFiles = [
            "ModelStoreRecoveryCoordinatorTests.swift",
            "StartupStoreDiagnosticTests.swift",
            "StoreRecoveryArchitectureTests.swift",
            "StoreRecoveryArtifactArchiverTests.swift",
            "StoreRecoveryTestSupport.swift"
        ]
        let testFiles = try swiftSources(under: testSourceRoot)
            .map(\.lastPathComponent)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyTestURL.path))
        XCTAssertEqual(testFiles, expectedTestFiles)
    }

    func testUsableContainerRecoveryNoticeHasDismissControl() throws {
        let source = try String(
            contentsOf: iosRoot
                .appendingPathComponent("Merian")
                .appendingPathComponent("App")
                .appendingPathComponent("MerianApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let onDismiss: (() -> Void)?"))
        XCTAssertTrue(source.contains("Button(action: onDismiss)"))
        XCTAssertTrue(source.contains("!isStartupRecoveryNoticeDismissed"))
        XCTAssertTrue(
            source.contains(
                ".accessibilityLabel(\"Dismiss recovery notice\")"
            )
        )
    }

    private var iosRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private var storeRecoverySourceRoot: URL {
        iosRoot
            .appendingPathComponent("Merian")
            .appendingPathComponent("Core")
            .appendingPathComponent("Data")
            .appendingPathComponent("StoreRecovery", isDirectory: true)
    }

    private var testSourceRoot: URL {
        iosRoot
            .appendingPathComponent("MerianTests")
            .appendingPathComponent("Core")
            .appendingPathComponent("Data")
            .appendingPathComponent("StoreRecovery", isDirectory: true)
    }

    private func productionSwiftSources() throws -> [URL] {
        try swiftSources(under: storeRecoverySourceRoot)
    }

    private func assertFilesStayWithinReviewGuard(
        _ sourceURLs: [URL]
    ) throws {
        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            let lineCount = source.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count

            XCTAssertLessThanOrEqual(
                lineCount,
                600,
                "\(sourceURL.lastPathComponent) has \(lineCount) lines."
            )
        }
    }

    private func swiftSources(under root: URL) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Unable to enumerate \(root.path)")
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: resourceKeys).isRegularFile == true else {
                return nil
            }
            return url
        }
        .sorted { $0.path < $1.path }
    }
}
