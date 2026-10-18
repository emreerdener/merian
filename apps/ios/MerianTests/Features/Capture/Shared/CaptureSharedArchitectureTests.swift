import Foundation
import Testing

@Suite("Capture Shared Architecture")
struct CaptureSharedArchitectureTests {
    @Test func focusDetectionSeparatesCoreWorkFromCaptureTelemetry() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )
        for declaration in [
            "struct ImageFocusRegionCandidate",
            "enum ImageFocusRegionResolution",
            "enum ImageFocusRegionResolver"
        ] {
            let owners = sources.compactMap { source in
                source.contents.contains(declaration)
                    ? source.relativePath
                    : nil
            }
            #expect(owners == [
                "Core/Media/ImageFocusRegionResolver.swift"
            ])
        }

        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Features/Capture/Shared/Services/ImageFocusRegionDetector.swift"
        )
        #expect(imports(in: source) == [
            "import CoreGraphics",
            "import Foundation"
        ])
        #expect(source.contains("ImageFocusEngine.detect(in: imageData)"))
        #expect(source.contains("AppTelemetry.trackImageFocusDetection("))
        #expect(!source.contains("MerianNetworkClient"))
        #expect(!source.contains("AppDIContainer"))
        #expect(!source.contains("URLSession"))
        let engine = try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/Core/Media/ImageFocusEngine.swift")
        #expect(engine.contains("ImageDownsampler.downsample("))
        #expect(engine.contains("func detectAndDrain("))
        #expect(!engine.contains("AppTelemetry"))
        #expect(!engine.contains("ImageFocusRegionDetector"))
    }

    @Test func focusDetectionTestsMirrorCoreOwnership() throws {
        let repository = try DatabaseActorTestSupport.repositoryRoot()
        let testPath = repository.appendingPathComponent(
            "apps/ios/MerianTests/Core/Media/ImageFocusRegionResolverTests.swift"
        )
        let retiredPaths = [
            "apps/ios/Merian/Core/Utilities/ImageFocusRegionDetector.swift",
            "apps/ios/MerianTests/Core/Utilities/ImageFocusRegionDetectorTests.swift"
        ]

        #expect(FileManager.default.fileExists(atPath: testPath.path))
        for path in retiredPaths {
            #expect(!FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(path).path
            ))
        }

        let tests = try String(contentsOf: testPath, encoding: .utf8)
        #expect(tests.contains("struct ImageFocusRegionResolverTests"))
        #expect(tests.contains("rejectsAmbiguousSeparatedSubjects"))
    }

    @Test func captureSharedProductionFilesStayBounded() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian/Features/Capture/Shared"
        )

        #expect(!sources.isEmpty)
        for source in sources {
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 600,
                "\(source.relativePath) exceeds the 600-line review ceiling"
            )
        }
    }

    private func imports(in source: String) -> [String] {
        source.split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("import ") }
    }
}
