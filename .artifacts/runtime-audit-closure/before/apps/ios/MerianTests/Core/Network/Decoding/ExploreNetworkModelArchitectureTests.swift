import Foundation
import Testing

@Suite("Explore Network Model Architecture")
struct ExploreNetworkModelArchitectureTests {
    @Test func focusedOwnersRetireTheAggregateAndStayBounded() throws {
        let root = try repositoryRoot()
        let networkRoot = root.appendingPathComponent("apps/ios/Merian/Core/Network")
        let modelsRoot = networkRoot.appendingPathComponent("Models/Explore")
        let aggregate = networkRoot.appendingPathComponent("ExploreAPIModels.swift")

        #expect(!FileManager.default.fileExists(atPath: aggregate.path))

        let files = try swiftFiles(in: modelsRoot)
        #expect(Set(files.map(\.lastPathComponent)) == Self.expectedModelFilenames)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(lineCount(source) <= 600, "\(file.lastPathComponent) exceeded the model review ceiling")
            for forbiddenToken in Self.forbiddenEffectTokens {
                #expect(
                    !source.contains(forbiddenToken),
                    "\(file.lastPathComponent) must not acquire \(forbiddenToken)"
                )
            }
        }

        let privacy = try source(
            "apps/ios/Merian/Core/Models/ExploreLocationPrivacy.swift",
            below: root
        )
        #expect(privacy.contains("enum ExploreLocationPrivacy"))
        #expect(lineCount(privacy) <= 600)
        for forbiddenToken in Self.forbiddenEffectTokens {
            #expect(!privacy.contains(forbiddenToken))
        }
    }

    @Test func representativeDeclarationsHaveExactlyOneFocusedOwner() throws {
        let root = try repositoryRoot()
        let modelsRoot = root.appendingPathComponent(
            "apps/ios/Merian/Core/Network/Models/Explore"
        )
        let sources = try Dictionary(uniqueKeysWithValues: swiftFiles(in: modelsRoot).map {
            ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
        })

        for (declaration, expectedFilename) in Self.declarationOwners {
            let owners = Set(sources.compactMap { filename, source in
                source.contains(declaration) ? filename : nil
            })
            #expect(
                owners == Set([expectedFilename]),
                "Unexpected owner for \(declaration)"
            )
        }

        #expect(
            !sources.values.contains { $0.contains("enum ExploreLocationPrivacy") },
            "Cross-feature location redaction belongs in Core Models, not wire DTOs"
        )
    }

    @Test func locationSharingSeparatesWireContractFromExplorePresentation() throws {
        let root = try repositoryRoot()
        let wire = try source(
            "apps/ios/Merian/Core/Network/Models/Explore/ExploreLocationSharingAPIModels.swift",
            below: root
        )
        let presentation = try source(
            "apps/ios/Merian/Features/Explore/Shared/Models/ExploreLocationSharingPresentation.swift",
            below: root
        )
        let composer = try source(
            "apps/ios/Merian/Features/Explore/Feed/Models/ExplorePostComposerModels.swift",
            below: root
        )

        #expect(
            wire.contains(
                "enum ExplorePostLocationSharing: String, CaseIterable, Identifiable, Decodable, Equatable"
            )
        )
        #expect(!wire.contains("var title: String"))
        #expect(!wire.contains("var systemImage: String"))
        #expect(!wire.contains("var detail: String"))
        #expect(presentation.contains("extension ExplorePostLocationSharing"))
        #expect(presentation.contains("var title: String"))
        #expect(presentation.contains("var systemImage: String"))
        #expect(presentation.contains("var detail: String"))
        #expect(!presentation.contains("import "))
        for forbiddenToken in Self.forbiddenEffectTokens {
            #expect(!presentation.contains(forbiddenToken))
        }
        #expect(!composer.contains("enum ExplorePostLocationSharing"))
    }

    private static let expectedModelFilenames: Set<String> = [
        "CommunityFeedbackAPIModels.swift",
        "CommunityIdentificationAPIModels.swift",
        "ExploreAuthorProfileAPIModels.swift",
        "ExploreBrowsingAPIModels.swift",
        "ExploreBrowsingQueryModels.swift",
        "ExploreCommentAPIModels.swift",
        "ExploreLocationSharingAPIModels.swift",
        "ExploreMapAPIModels.swift",
        "ExploreMediaIncidentAPIModels.swift",
        "ExploreNotificationAPIModels.swift",
        "ExplorePostDetailAPIModels.swift",
        "ExploreSharingAPIModels.swift",
        "PublicProfileAPIModels.swift"
    ]

    private static let declarationOwners: [String: String] = [
        "struct CommunityFeedbackSubmission: Encodable": "CommunityFeedbackAPIModels.swift",
        "struct CommunityIdentificationDetail: Decodable": "CommunityIdentificationAPIModels.swift",
        "struct CommunityTaxonSearchResult: Decodable": "CommunityIdentificationAPIModels.swift",
        "struct ExploreAuthorProfile: Decodable": "ExploreAuthorProfileAPIModels.swift",
        "struct ExploreEmptyStringIfMissing: Decodable": "ExploreBrowsingAPIModels.swift",
        "struct ExploreFeedResponse: Decodable": "ExploreBrowsingAPIModels.swift",
        "enum ExploreMediaKind: String": "ExploreBrowsingAPIModels.swift",
        "struct ExplorePost: Decodable": "ExploreBrowsingAPIModels.swift",
        "enum ExploreFeedFilter: String": "ExploreBrowsingQueryModels.swift",
        "struct ExploreFeedCursor: Equatable": "ExploreBrowsingQueryModels.swift",
        "struct ExploreSpeciesPostCursor: Decodable": "ExploreBrowsingQueryModels.swift",
        "struct ExploreComment: Decodable": "ExploreCommentAPIModels.swift",
        "struct ExploreMentionSuggestion: Decodable": "ExploreCommentAPIModels.swift",
        "enum ExplorePostLocationSharing: String": "ExploreLocationSharingAPIModels.swift",
        "struct ExploreMapPointsResponse: Decodable": "ExploreMapAPIModels.swift",
        "struct ExploreMapPost: Decodable": "ExploreMapAPIModels.swift",
        "struct ExploreMediaIncident: Decodable": "ExploreMediaIncidentAPIModels.swift",
        "struct ExploreNotificationsResponse: Decodable": "ExploreNotificationAPIModels.swift",
        "struct ExplorePostDetail: Decodable": "ExplorePostDetailAPIModels.swift",
        "struct ExploreReferenceGalleryImage: Identifiable": "ExplorePostDetailAPIModels.swift",
        "struct ExploreShareResponse: Decodable": "ExploreSharingAPIModels.swift",
        "struct ExploreScanShareState: Decodable": "ExploreSharingAPIModels.swift",
        "struct PublicUsernameAvailabilityResponse: Decodable": "PublicProfileAPIModels.swift"
    ]

    private static let forbiddenEffectTokens = [
        "@Observable",
        "MerianNetworkClient",
        "ModelContext(",
        "SupabaseManager",
        "Task {",
        "Task.detached",
        "URLSession",
        "import Observation",
        "import Supabase",
        "import SwiftData",
        "import SwiftUI",
        "static let shared"
    ]

    private func swiftFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func source(_ path: String, below root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func lineCount(_ source: String) -> Int {
        guard !source.isEmpty else { return 0 }
        let count = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        return count - (source.hasSuffix("\n") ? 1 : 0)
    }

    private func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("project.yml").path
            ) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
