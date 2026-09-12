import Foundation
import Testing

@Suite("Core Utilities Integration Architecture")
struct CoreUtilitiesArchitectureTests {
    @Test func utilitiesContainOnlyCrossDomainValueHelpers() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.utilitiesDirectory
        )

        #expect(
            Set(sources.map(\.relativePath)) == Self.expectedUtilitySources
        )
        for source in sources {
            #expect(
                imports(in: source.contents) == ["import Foundation"],
                "\(source.relativePath) has an unexpected dependency"
            )
            #expect(
                DatabaseActorTestSupport.lineCount(of: source.contents) <= 100,
                "\(source.relativePath) exceeds the Utilities ceiling"
            )
            for token in Self.forbiddenUtilityEffects {
                #expect(
                    !source.contents.contains(token),
                    "\(source.relativePath) resolves \(token)"
                )
            }
        }
    }

    @Test func relocatedDeclarationsHaveOneExactOwner() throws {
        let sources = try DatabaseActorTestSupport.swiftSources(
            below: Self.productionDirectory
        )

        for owner in Self.relocatedOwners {
            let owners = sources.compactMap { source -> String? in
                containsDeclaration(owner.declaration, in: source.contents)
                    ? source.relativePath
                    : nil
            }
            #expect(
                owners == [owner.path],
                "\(owner.declaration) changed ownership"
            )
        }

        for owner in Self.relocatedMembers {
            let owners = sources.compactMap { source -> String? in
                source.contents.contains(owner.member)
                    ? source.relativePath
                    : nil
            }
            #expect(owners == [owner.path], "\(owner.member) changed ownership")
        }
    }

    @Test func utilitiesTestsAndRetiredLocationsRemainExact() throws {
        let repository = try DatabaseActorTestSupport.repositoryRoot()
        let utilityTests = try DatabaseActorTestSupport.swiftSources(
            below: Self.utilitiesTestsDirectory
        )
        #expect(Set(utilityTests.map(\.relativePath)) == Self.expectedUtilityTests)

        for relativePath in Self.expectedRelocatedTestPaths {
            #expect(FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(relativePath).path
            ))
        }
        for relativePath in Self.retiredPaths {
            #expect(!FileManager.default.fileExists(
                atPath: repository.appendingPathComponent(relativePath).path
            ))
        }
    }

    @Test func movedPoliciesDoNotRegainAggregateBehavior() throws {
        let fieldNotes = try DatabaseActorTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/FieldNotes/FieldNotesRepository.swift"
        )
        #expect(!fieldNotes.contains("try? modelContext.fetch"))
        #expect(fieldNotes.contains("try modelContext.fetch(descriptor).first"))

        let appContainer = try DatabaseActorTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/AppDIContainer.swift"
        )
        #expect(!appContainer.contains("enum DetachedWork"))

        let safeArray = try DatabaseActorTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/UI/Utilities/Array+Safe.swift"
        )
        #expect(!safeArray.contains("commonName"))
        #expect(!safeArray.contains("removingDuplicates"))

        let allSources = try DatabaseActorTestSupport.swiftSources(
            below: Self.productionDirectory
        )
        for retiredMember in [
            ".commonNameKey",
            ".removingFuzzyDuplicateNames()",
            "func removingDuplicates()"
        ] {
            #expect(!allSources.contains {
                $0.contents.contains(retiredMember)
            })
        }
    }

    private struct Owner {
        let declaration: String
        let path: String
    }

    private struct MemberOwner {
        let member: String
        let path: String
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: declaration)
        let modifiers = [
            "private", "fileprivate", "internal", "package", "public", "open",
            "final", "indirect", "nonisolated"
        ].joined(separator: "|")
        let pattern = #"(?m)^\s*(?:@[_A-Za-z][_A-Za-z0-9]*(?:\([^\n]*\))?\s+)*"#
            + "(?:(?:(\(modifiers)))\\s+)*"
            + escaped
            + #"(?=\s|:|\{|$)"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }

    private func imports(in source: String) -> Set<String> {
        Set(source.split(separator: "\n").compactMap { line in
            line.hasPrefix("import ") ? String(line) : nil
        })
    }

    private static let productionDirectory = "apps/ios/Merian"
    private static let utilitiesDirectory = "\(productionDirectory)/Core/Utilities"
    private static let utilitiesTestsDirectory =
        "apps/ios/MerianTests/Core/Utilities"

    private static let expectedUtilitySources: Set<String> = [
        "DateUtilities.swift",
        "String+Trimming.swift"
    ]

    private static let expectedUtilityTests: Set<String> = [
        "CoreUtilitiesIntegrationArchitectureTests.swift",
        "DateUtilitiesTests.swift",
        "StringTrimmingTests.swift"
    ]

    private static let relocatedOwners = [
        Owner(
            declaration: "class AppLifecycleManager",
            path: "App/Lifecycle/AppLifecycleManager.swift"
        ),
        Owner(
            declaration: "enum DetachedWorkCategory",
            path: "Core/Concurrency/DetachedWork.swift"
        ),
        Owner(
            declaration: "enum DetachedWork",
            path: "Core/Concurrency/DetachedWork.swift"
        ),
        Owner(
            declaration: "class BackgroundTaskWrapper",
            path: "Core/Data/OfflineSync/Services/BackgroundExecution/BackgroundTaskWrapper.swift"
        ),
        Owner(
            declaration: "enum FieldNotesRepository",
            path: "Core/Data/FieldNotes/FieldNotesRepository.swift"
        ),
        Owner(
            declaration: "enum MerianError",
            path: "Core/Errors/MerianError.swift"
        ),
        Owner(
            declaration: "enum ScanConnectivityFailurePolicy",
            path: "Core/Data/OfflineSync/Policies/ScanConnectivityFailurePolicy.swift"
        ),
        Owner(
            declaration: "enum SpeciesCommonNamePresentation",
            path: "Features/SpeciesReference/Models/SpeciesCommonNamePresentation.swift"
        )
    ]

    private static let relocatedMembers = [
        MemberOwner(
            member: "func sinkOnMainActor(",
            path: "Core/Hardware/Utilities/Publisher+MainActor.swift"
        ),
        MemberOwner(
            member: "subscript(safe index: Int)",
            path: "Core/UI/Utilities/Array+Safe.swift"
        )
    ]

    private static let expectedRelocatedTestPaths = [
        "apps/ios/MerianTests/App/Lifecycle/AppLifecycleManagerTests.swift",
        "apps/ios/MerianTests/Core/Architecture/CorePolicyOwnershipArchitectureTests.swift",
        "apps/ios/MerianTests/Core/Concurrency/DetachedWorkTests.swift",
        "apps/ios/MerianTests/Core/Data/FieldNotes/FieldNotesRepositoryTests.swift",
        "apps/ios/MerianTests/Core/Data/OfflineSync/BackgroundTaskWrapperTests.swift",
        "apps/ios/MerianTests/Core/Data/OfflineSync/ScanConnectivityFailurePolicyTests.swift",
        "apps/ios/MerianTests/Core/Hardware/FrameworkPublisherBridgeTests.swift",
        "apps/ios/MerianTests/Core/Media/MediaPlaybackObservationTests.swift",
        "apps/ios/MerianTests/Core/UI/SafeArrayAccessTests.swift",
        "apps/ios/MerianTests/Features/SpeciesReference/SpeciesCommonNamePresentationTests.swift"
    ]

    private static let retiredPaths = [
        "apps/ios/Merian/Core/Utilities/AppLifecycleManager.swift",
        "apps/ios/Merian/Core/Utilities/Array+Safe.swift",
        "apps/ios/Merian/Core/Utilities/BackgroundTaskWrapper.swift",
        "apps/ios/Merian/Core/Utilities/FieldNotesRepository.swift",
        "apps/ios/Merian/Core/Utilities/MerianError.swift",
        "apps/ios/Merian/Core/Utilities/Publisher+MainActor.swift",
        "apps/ios/MerianTests/Core/Utilities/AppLifecycleManagerTests.swift",
        "apps/ios/MerianTests/Core/Utilities/BackgroundTaskWrapperTests.swift",
        "apps/ios/MerianTests/Core/Utilities/DetachedWorkTests.swift",
        "apps/ios/MerianTests/Core/Utilities/EventDeliveryTests.swift",
        "apps/ios/MerianTests/Core/Utilities/FieldNotesRepositoryTests.swift",
        "apps/ios/MerianTests/Core/Utilities/ScanConnectivityFailurePolicyTests.swift"
    ]

    private static let forbiddenUtilityEffects = [
        "@MainActor",
        "@Observable",
        "AppDIContainer",
        "FieldNotes",
        "MerianError",
        "ModelContext",
        "Task {",
        "UIApplication",
        "URLSession",
        "UserDefaults",
        "import Combine",
        "import SwiftData",
        "import SwiftUI",
        "import UIKit"
    ]
}
