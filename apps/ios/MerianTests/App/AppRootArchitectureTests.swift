import Foundation
import Testing

@Suite("App root architecture")
struct AppRootArchitectureTests {
    @Test func appDirectoriesAndRootOwnersRemainExplicit() throws {
        let root = try appSourceRoot()
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
        )

        var directories: Set<String> = []
        var rootSwiftFiles: Set<String> = []
        for entry in entries {
            let values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey]
            )
            if values.isDirectory == true {
                directories.insert(entry.lastPathComponent)
            } else if values.isRegularFile == true,
                      entry.pathExtension == "swift" {
                rootSwiftFiles.insert(entry.lastPathComponent)
            }
        }

        #expect(directories == [
            "Lifecycle",
            "Presentation",
            "Routing",
            "UITesting"
        ])
        #expect(rootSwiftFiles == ["AppDelegate.swift", "MerianApp.swift"])
    }

    @Test func extractedDeclarationsKeepSoleFocusedOwners() throws {
        let sources = try appSources()
        let expectedOwners = [
            "final class AppDelegate:": "AppDelegate.swift",
            "enum AppRootPresentation:":
                "Presentation/AppRootPresentation.swift",
            "enum StartupRecoveryNoticePolicy {":
                "Presentation/AppRootPresentation.swift",
            "enum MerianOpenURLRoute:": "Routing/AppURLRouting.swift",
            "enum UITestSeedCoordinator {":
                "UITesting/UITestSeedCoordinator.swift"
        ]

        for (marker, expectedOwner) in expectedOwners {
            let owners = sources.filter { $0.contents.contains(marker) }
                .map(\.relativePath)
            #expect(
                Set(owners) == [expectedOwner],
                "\(marker) owners changed: \(owners)"
            )
        }
    }

    @Test func productionOwnersStayWithinReviewGuard() throws {
        let oversized = Set(try appSources().compactMap { source in
            guard !source.relativePath.hasPrefix("UITesting/") else {
                return nil
            }
            return DatabaseActorTestSupport.lineCount(of: source.contents) > 600
                ? source.relativePath
                : nil
        })

        #expect(oversized.isEmpty)
    }

    @Test func uiTestSeedsRemainDebugOnlyWithReleaseNoOps() throws {
        let source = try source(
            at: "UITesting/UITestSeedCoordinator.swift"
        )
        let debugStart = try #require(source.range(of: "#if DEBUG"))
        let releaseStart = try #require(source.range(
            of: "#else",
            range: debugStart.upperBound..<source.endIndex
        ))
        let boundaryEnd = try #require(source.range(
            of: "#endif",
            range: releaseStart.upperBound..<source.endIndex
        ))
        let debugSource = source[debugStart.upperBound..<releaseStart.lowerBound]
        let releaseSource = source[
            releaseStart.upperBound..<boundaryEnd.lowerBound
        ]

        #expect(debugSource.contains("-seed"))
        #expect(debugSource.contains("ui_test_"))
        #expect(releaseSource.contains(
            "static var isEnabled: Bool { return false }"
        ))
        #expect(!releaseSource.contains("-seed"))
        #expect(!releaseSource.contains("ui_test_"))
        let merianAppSource = try source(at: "MerianApp.swift")
        #expect(!merianAppSource.contains("-seed"))
    }

    @Test func merianAppRetainsRootCompositionAndURLTaskOwnership() throws {
        let source = try source(at: "MerianApp.swift")
        for marker in [
            "@main",
            "@UIApplicationDelegateAdaptor(AppDelegate.self)",
            "ModelContainerBootstrapper.bootstrap()",
            "WindowGroup {",
            ".onOpenURL { url in",
            ".onContinueUserActivity(NSUserActivityTypeBrowsingWeb)",
            "googleHandled: GIDSignIn.sharedInstance.handle(url)",
            "await diContainer.supabaseManager",
            ".handleAuthenticationCallbackURL(url)"
        ] {
            #expect(source.contains(marker), "MerianApp lost \(marker)")
        }
        #expect(!source.contains("ModelContainer("))
        #expect(!source.contains("SchemaMigrationPlan"))

        let openURL = try #require(source.range(of: ".onOpenURL { url in"))
        let openURLSource = source[openURL.lowerBound...]
        let google = try #require(openURLSource.range(
            of: "googleHandled: GIDSignIn.sharedInstance.handle(url)"
        ))
        let fallbackTask = try #require(openURLSource.range(
            of: "Task {",
            range: google.upperBound..<openURLSource.endIndex
        ))
        let fallbackAuth = try #require(openURLSource.range(
            of: ".handleAuthenticationCallbackURL(url)",
            range: fallbackTask.upperBound..<openURLSource.endIndex
        ))

        #expect(google.lowerBound < fallbackTask.lowerBound)
        #expect(fallbackTask.lowerBound < fallbackAuth.lowerBound)

        for focusedPath in [
            "AppDelegate.swift",
            "Presentation/AppRootPresentation.swift",
            "Routing/AppURLRouting.swift",
            "UITesting/UITestSeedCoordinator.swift"
        ] {
            let focusedSource = try source(at: focusedPath)
            #expect(!focusedSource.contains("WindowGroup {"))
            #expect(!focusedSource.contains("handleAuthenticationCallbackURL"))
        }
    }

    private func appSourceRoot() throws -> URL {
        try DatabaseActorTestSupport.repositoryRoot()
            .appendingPathComponent(Self.appDirectory)
    }

    private func appSources() throws
        -> [DatabaseActorTestSupport.RepositorySourceFile] {
        try DatabaseActorTestSupport.swiftSources(below: Self.appDirectory)
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: appSourceRoot().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static let appDirectory = "apps/ios/Merian/App"
}
