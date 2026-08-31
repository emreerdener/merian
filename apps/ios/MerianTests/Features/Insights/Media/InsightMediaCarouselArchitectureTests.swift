import Foundation
import XCTest

@testable import Merian

final class InsightMediaCarouselArchitectureTests: XCTestCase {
    func testProductionCarouselFilesStayBelowSixHundredLines() throws {
        let files = try swiftFiles(in: carouselSourceRoot())

        XCTAssertFalse(files.isEmpty)
        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let lineCount = contents.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count
            XCTAssertLessThanOrEqual(
                lineCount,
                600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    func testCarouselOwnershipDirectoriesRemainPresent() throws {
        let root = try carouselSourceRoot()
        for directory in [
            "Animation",
            "Builders",
            "Components",
            "Models",
            "Pages",
            "Playback",
            "Services"
        ] {
            var isDirectory: ObjCBool = false
            let path = root.appendingPathComponent(directory).path
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: path,
                    isDirectory: &isDirectory
                ),
                "Insight media Carousel is missing its \(directory) owner"
            )
            XCTAssertTrue(isDirectory.boolValue)
        }
    }

    func testLiveResolutionStaysInServices() throws {
        let forbiddenTokens = [
            "HapticManager.shared",
            "AudioBoostProcessor.shared",
            "AVAudioSession.sharedInstance",
            "MediaPlaybackAudioSession.activate",
            "AppTelemetry.trackInsightAudioBoost",
            "LocalImageLoader.shared"
        ]

        for file in try swiftFiles(in: carouselSourceRoot()) {
            guard !file.pathComponents.contains("Services") else { continue }
            let contents = try String(contentsOf: file, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(file.lastPathComponent) directly resolves \(token)"
                )
            }
        }
    }

    func testModelsRemainPlatformNeutral() throws {
        let root = try carouselSourceRoot().appendingPathComponent("Models")
        for file in try swiftFiles(in: root) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for forbiddenImport in ["import SwiftUI", "import UIKit"] {
                XCTAssertFalse(
                    contents.contains(forbiddenImport),
                    "\(file.lastPathComponent) imports \(forbiddenImport)"
                )
            }
            for featureViewType in [
                "CarouselPageItem",
                "NativePageCarouselPage",
                "AnyView"
            ] {
                XCTAssertFalse(
                    contents.contains(featureViewType),
                    "\(file.lastPathComponent) depends on \(featureViewType)"
                )
            }
        }
    }

    func testRootViewsDoNotRegainExtractedDeclarations() throws {
        let root = try carouselSourceRoot()
        let rootFiles = ["ImagesCarousel.swift", "InsightFullscreenImageCarousel.swift"]
        let forbiddenDeclarations = [
            "struct CarouselPageBuilder",
            "struct LensFocusOverlay",
            "struct ImageFocusOverlayLayout",
            "struct InlineVideoPlaybackCarouselPage",
            "struct FullscreenVideoPlaybackView"
        ]

        for fileName in rootFiles {
            let contents = try String(
                contentsOf: root.appendingPathComponent(fileName),
                encoding: .utf8
            )
            for declaration in forbiddenDeclarations {
                XCTAssertFalse(
                    contents.contains(declaration),
                    "\(fileName) regained \(declaration)"
                )
            }
        }
    }

    func testPlaybackStateRemainsPrivateAndColocated() throws {
        let root = try carouselSourceRoot()
        let audio = try contents(
            of: root.appendingPathComponent(
                "Pages/AudioPlaybackCarouselPage.swift"
            )
        )
        XCTAssertTrue(audio.contains("@State private var player: AVAudioPlayer?"))
        XCTAssertTrue(audio.contains("@State private var pendingPlayer:"))

        for path in [
            "Playback/InlineVideoPlaybackCarouselPage.swift",
            "Playback/FullscreenVideoPlaybackView.swift"
        ] {
            let playback = try contents(of: root.appendingPathComponent(path))
            XCTAssertTrue(playback.contains("@State private var player: AVPlayer?"))
            XCTAssertTrue(
                playback.contains("@State private var playbackObservation")
            )
        }
    }

    func testCrossFeatureImageRendererLivesInCoreUI() throws {
        let repositoryRoot = try repositoryRoot()
        let carouselCopy = repositoryRoot.appendingPathComponent(
            "apps/ios/Merian/Features/Insights/Media/Carousel/Pages/" +
                "AsyncLocalImageView.swift"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: carouselCopy.path)
        )

        let component = try contents(
            of: repositoryRoot.appendingPathComponent(
                "apps/ios/Merian/Core/UI/Components/AsyncLocalImageView.swift"
            )
        )
        let service = try contents(
            of: repositoryRoot.appendingPathComponent(
                "apps/ios/Merian/Core/UI/Services/" +
                    "AsyncLocalImageDependencies.swift"
            )
        )
        XCTAssertTrue(component.contains("AsyncLocalImageDependencies"))
        XCTAssertFalse(component.contains("LocalImageLoader.shared"))
        XCTAssertTrue(service.contains("LocalImageLoader.shared"))
    }

    func testCrossFeatureCarouselPrimitivesLiveInCoreUI() throws {
        let repositoryRoot = try repositoryRoot()
        let carouselRoot = try carouselSourceRoot()
        let sharedFiles = [
            "MediaCarouselPaginationDots.swift",
            "MediaHeroTopScrollEdgeEffect.swift",
            "NativePageCarousel+Coordinator.swift",
            "NativePageCarousel.swift",
            "NativePageCarouselPage.swift",
            "ZoomableHostingController.swift"
        ]

        for fileName in sharedFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: carouselRoot.appendingPathComponent(fileName).path
                ),
                "Insight Carousel contains a feature-owned copy of \(fileName)"
            )
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: repositoryRoot.appendingPathComponent(
                        "apps/ios/Merian/Core/UI/Components/MediaCarousel/" +
                            fileName
                    ).path
                ),
                "Core UI is missing the shared \(fileName) owner"
            )
        }

        let fieldTripCarousel = try contents(
            of: repositoryRoot.appendingPathComponent(
                "apps/ios/Merian/Features/Explore/FieldTrips/Components/" +
                    "Media/FieldTripFeaturedMediaCarousel.swift"
            )
        )
        XCTAssertTrue(fieldTripCarousel.contains("NativePageCarouselPage"))
        XCTAssertTrue(fieldTripCarousel.contains("item.pageReuseIdentity"))
        XCTAssertFalse(fieldTripCarousel.contains("CarouselPageItem"))
    }

    private func carouselSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Insights/Media/Carousel"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        return root
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()

        for _ in 0..<10 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else { return [] }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: keys).isRegularFile == true
            else {
                return nil
            }
            return url
        }
    }
}
