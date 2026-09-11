import Foundation
import Testing

@Suite("Core UI integration architecture")
struct CoreUIArchitectureTests {
    @Test("Core UI contains only bounded production owners")
    func productionFilesStayBounded() throws {
        for file in try swiftFiles(in: coreUIRoot()) {
            let source = try contents(of: file)
            #expect(
                lineCount(source) <= 600,
                "\(file.lastPathComponent) exceeds 600 lines"
            )
        }
    }

    @Test("Presentation owners do not resolve live process services")
    func presentationOwnersAreEffectFree() throws {
        for file in try swiftFiles(in: coreUIRoot()) {
            guard !file.pathComponents.contains("Services") else { continue }
            let source = try contents(of: file)
            for ownership in Self.liveEffectOwnership {
                #expect(
                    !source.contains(ownership.token),
                    "\(file.lastPathComponent) resolves \(ownership.token)"
                )
            }
        }
    }

    @Test("Live effects remain in explicit service adapters")
    func liveEffectsHaveExplicitServiceOwners() throws {
        let root = try repositoryRoot()
        let sources = try swiftFiles(in: coreUIRoot()).map { file in
            (
                path: String(file.path.dropFirst(root.path.count + 1)),
                contents: try contents(of: file)
            )
        }

        for source in sources {
            for sourceLine in source.contents.split(separator: "\n")
                where sourceLine.contains(".shared") {
                let line = String(sourceLine)
                #expect(
                    Self.liveEffectOwnership.contains { ownership in
                        line.contains(ownership.token)
                    },
                    "Unclassified singleton lookup in \(source.path): \(line)"
                )
            }
        }

        for ownership in Self.liveEffectOwnership {
            let owners = Set(sources.compactMap { source in
                source.contents.contains(ownership.token)
                    ? source.path
                    : nil
            })
            let expectedOwners = ownership.owners.sorted()
            let actualOwners = owners.sorted()

            #expect(
                owners == ownership.owners,
                "\(ownership.token) ownership changed from \(expectedOwners) to \(actualOwners)"
            )
        }
    }

    @Test("Feature and domain UI has its narrowest owner")
    func featureAndDomainOwnersAreRelocated() throws {
        let root = try repositoryRoot()

        for path in Self.retiredCoreUIPaths {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "Retired Core UI owner remains at \(path)"
            )
        }

        for path in Self.relocatedOwnerPaths {
            #expect(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                ),
                "Missing relocated owner at \(path)"
            )
        }
    }

    @Test("Audio page keeps mutable playback state file-private")
    func audioPlaybackStateRemainsEncapsulated() throws {
        let file = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/UI/Components/MediaCarousel/" +
                "AudioPlayback/AudioPlaybackCarouselPage.swift"
        )
        let source = try contents(of: file)

        for line in source.split(separator: "\n")
            where line.contains("@State") {
            #expect(
                line.contains("@State private"),
                "Audio playback state widened: \(line)"
            )
        }
        #expect(source.contains("private func startPlayback("))
        #expect(source.contains("private func updateAudioBoostMode() async"))
        #expect(source.contains("private func handlePlaybackFailure("))
    }

    private func coreUIRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/UI"
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

    private func swiftFiles(in root: URL) throws -> [URL] {
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

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func lineCount(_ source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private static let asyncLocalImageDependenciesPath =
        "apps/ios/Merian/Core/UI/Services/AsyncLocalImageDependencies.swift"
    private static let scanThumbnailLoaderPath =
        "apps/ios/Merian/Core/UI/Services/ScanThumbnailLoader.swift"
    private static let scanMilestoneDependenciesPath =
        "apps/ios/Merian/Core/UI/Feedback/Services/" +
            "ScanMilestoneDependencies.swift"

    private static let liveEffectOwnership: [(
        token: String,
        owners: Set<String>
    )] = [
        (
            "AppDIContainer.shared",
            []
        ),
        (
            "AudioSpectrogramThumbnailLoader.shared",
            [scanThumbnailLoaderPath]
        ),
        (
            "FeatureFlags.",
            [scanMilestoneDependenciesPath]
        ),
        (
            "GamificationManager.shared",
            [scanMilestoneDependenciesPath]
        ),
        (
            "HardwareOrchestrator.shared",
            []
        ),
        (
            "HapticManager.shared",
            []
        ),
        (
            "LocalImageLoader.shared",
            [
                asyncLocalImageDependenciesPath,
                scanThumbnailLoaderPath
            ]
        ),
        (
            "MerianNetworkClient.shared",
            [scanMilestoneDependenciesPath]
        ),
        (
            "OfflineQueueManager.shared",
            [scanMilestoneDependenciesPath]
        ),
        (
            "SupabaseManager.shared",
            [scanMilestoneDependenciesPath]
        ),
        (
            "UIApplication.shared",
            []
        ),
        (
            "UNUserNotificationCenter.current()",
            []
        ),
        (
            "URLSession(",
            []
        ),
        (
            "URLSession.shared",
            []
        )
    ]

    private static let retiredCoreUIPaths = [
        "apps/ios/Merian/Core/UI/Components/FadingScrollView.swift",
        "apps/ios/Merian/Core/UI/Components/FloatingNavigationMenu.swift",
        "apps/ios/Merian/Core/UI/Components/FlowLayout.swift",
        "apps/ios/Merian/Core/UI/Components/PostIdentificationNotificationSheetView.swift",
        "apps/ios/Merian/Core/UI/Components/SlideToConfirm.swift",
        "apps/ios/Merian/Core/UI/Models/ComplimentaryScanDisplayState.swift",
        "apps/ios/Merian/Core/UI/Modifiers/CardEntranceModifier.swift"
    ]

    private static let relocatedOwnerPaths = [
        "apps/ios/Merian/Core/Notifications/Views/PostIdentificationNotificationSheetView.swift",
        "apps/ios/Merian/Features/Capture/Shell/Components/Navigation/FloatingNavigationMenu.swift",
        "apps/ios/Merian/Features/Explore/Shared/Components/FlowLayout.swift",
        "apps/ios/Merian/Features/Insights/Content/Modifiers/InsightCardEntranceModifier.swift",
        "apps/ios/Merian/Features/Insights/IdentificationReview/Candidates/Components/Review/SlideToConfirm.swift",
        "apps/ios/Merian/Features/Profile/Settings/Plan/Models/ComplimentaryScanDisplayState.swift",
        "apps/ios/Merian/Features/Profile/UserProfile/Components/Stats/FadingScrollView.swift"
    ]
}
