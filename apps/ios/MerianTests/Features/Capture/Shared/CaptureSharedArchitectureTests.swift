import Foundation
import Testing

@Suite("Capture Shared Architecture")
struct CaptureSharedArchitectureTests {
    @Test func focusDetectionHasOneCaptureSharedOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: "apps/ios/Merian"
        )
        for declaration in [
            "struct ImageFocusRegionCandidate",
            "enum ImageFocusRegionResolution",
            "enum ImageFocusRegionResolver",
            "enum ImageFocusRegionDetector"
        ] {
            let owners = sources.compactMap { source in
                source.contents.contains(declaration)
                    ? source.relativePath
                    : nil
            }
            #expect(owners == [
                "Features/Capture/Shared/Services/ImageFocusRegionDetector.swift"
            ])
        }

        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Features/Capture/Shared/Services/ImageFocusRegionDetector.swift"
        )
        #expect(imports(in: source) == [
            "import CoreGraphics",
            "import Foundation",
            "import Vision"
        ])
        #expect(source.contains("ImageDownsampler.downsample("))
        #expect(!source.contains("MerianNetworkClient"))
        #expect(!source.contains("AppDIContainer"))
        #expect(!source.contains("URLSession"))
    }

    @Test func focusDetectionTestsMirrorTheCaptureOwner() throws {
        let repository = try DatabaseActorTestSupport.repositoryRoot()
        let testPath = repository.appendingPathComponent(
            "apps/ios/MerianTests/Features/Capture/Shared/ImageFocusRegionDetectorTests.swift"
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
        #expect(tests.contains("struct ImageFocusRegionDetectorTests"))
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
