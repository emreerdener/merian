import Foundation
import Testing

@Suite("Core-wide Integration Architecture")
struct CoreIntegrationArchitectureTests {
    @Test func coreDomainsAndRootOwnersRemainExplicit() throws {
        let root = try DatabaseActorTestSupport.repositoryRoot()
            .appendingPathComponent(Self.coreDirectory)
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

        #expect(directories == Self.expectedCoreDomains)
        #expect(rootSwiftFiles == Self.expectedRootSwiftFiles)

        for directory in directories {
            #expect(FileManager.default.fileExists(
                atPath: root.appendingPathComponent(directory)
                    .appendingPathComponent("README.md").path
            ))
        }
    }

    @Test func oversizedOwnersRemainAnExplicitResidualInventory() throws {
        let sources = try coreSources()
        let oversized = Set(sources.compactMap { source in
            DatabaseActorTestSupport.lineCount(of: source.contents) > 600
                ? source.relativePath
                : nil
        })

        #expect(oversized == Self.trackedOversizedOwners)
    }

    @Test func policiesRemainBoundedAndRespectExplicitEffectBoundaries() throws {
        let policies = try coreSources().filter {
            $0.relativePath.hasPrefix("Policies/") ||
                $0.relativePath.contains("/Policies/")
        }
        #expect(!policies.isEmpty)
        #expect(
            Set(Self.allowedPolicyInputTokens.keys).isSubset(
                of: Set(policies.map(\.relativePath))
            )
        )

        for policy in policies {
            #expect(
                DatabaseActorTestSupport.lineCount(of: policy.contents) <= 600,
                "\(policy.relativePath) exceeds the policy review ceiling"
            )
            for effect in Self.liveEffectTokens {
                #expect(
                    !policy.contents.contains(effect),
                    "\(policy.relativePath) resolves \(effect)"
                )
            }

            let observedInputs = Set(
                Self.documentedPolicyInputTokens.filter {
                    policy.contents.contains($0)
                }
            )
            #expect(
                observedInputs == Self.allowedPolicyInputTokens[
                    policy.relativePath,
                    default: []
                ],
                "\(policy.relativePath) changed its documented live-input boundary"
            )
        }
    }

    @Test func reusableUIComponentsRemainTransportAndPersistenceFree() throws {
        let components = try DatabaseActorTestSupport.swiftSources(
            below: "\(Self.coreDirectory)/UI/Components"
        )
        #expect(!components.isEmpty)

        for component in components {
            for effect in Self.componentEffectTokens {
                #expect(
                    !component.contents.contains(effect),
                    "\(component.relativePath) resolves \(effect)"
                )
            }
        }
    }

    @Test func swiftDataReadsNeverSilentlyCollapseFailureAcrossCore() throws {
        for rejectedExample in [
            "try? context.fetch(descriptor)",
            "try?\nawait modelContext.fetchCount(descriptor)"
        ] {
            #expect(rejectedExample.range(
                of: Self.silentSwiftDataReadPattern,
                options: .regularExpression
            ) != nil)
        }
        #expect("try? imageFetcher.fetch()".range(
            of: Self.silentSwiftDataReadPattern,
            options: .regularExpression
        ) == nil)

        for source in try coreSources() {
            #expect(
                source.contents.range(
                    of: Self.silentSwiftDataReadPattern,
                    options: .regularExpression
                ) == nil,
                "\(source.relativePath) silently discards a SwiftData fetch failure"
            )
        }
    }

    @Test func diagnosticLogsKeepErrorsAndLocalMediaPathsPrivate() throws {
        for source in try coreSources() {
            for pattern in Self.sensitivePublicLogPatterns {
                #expect(
                    source.contents.range(
                        of: pattern,
                        options: .regularExpression
                    ) == nil,
                    "\(source.relativePath) exposes a sensitive diagnostic value"
                )
            }
        }
    }

    @Test func diagnosticPrivacyPatternsRejectOnlySensitivePublicValues() {
        let rejectedExamples = [
            #"\(error, privacy: .public)"#,
            #"""
            \(uploadError?.localizedDescription ?? "nil"),
            privacy: .public
            """#,
            #"""
            terminal server failure
            message=\(message, privacy: .public)
            """#,
            #"""
            \(resultFileURL.path,
            privacy: .public)
            """#
        ]
        for example in rejectedExamples {
            #expect(Self.sensitivePublicLogPatterns.contains { pattern in
                example.range(
                    of: pattern,
                    options: .regularExpression
                ) != nil
            })
        }

        let allowedExamples = [
            #"\(MerianLog.errorKind(error), privacy: .public)"#,
            #"\(message, privacy: .public)"#,
            #"\(error.localizedDescription, privacy: .private) scan=\(scanId, privacy: .public)"#,
            #"\(outputURL.lastPathComponent, privacy: .private) duration=\(duration, privacy: .public)"#
        ]
        for example in allowedExamples {
            #expect(!Self.sensitivePublicLogPatterns.contains { pattern in
                example.range(
                    of: pattern,
                    options: .regularExpression
                ) != nil
            })
        }
    }

    private func coreSources() throws
        -> [DatabaseActorTestSupport.RepositorySourceFile] {
        try DatabaseActorTestSupport.swiftSources(below: Self.coreDirectory)
    }

    private static let coreDirectory = "apps/ios/Merian/Core"

    private static let expectedCoreDomains: Set<String> = [
        "AI",
        "Analytics",
        "Concurrency",
        "Data",
        "Errors",
        "Hardware",
        "Intents",
        "Media",
        "Models",
        "Network",
        "Notifications",
        "Preferences",
        "Routing",
        "Security",
        "SpeciesReference",
        "UI",
        "Utilities"
    ]

    private static let expectedRootSwiftFiles: Set<String> = [
        "AppDIContainer.swift",
        "MerianLog.swift"
    ]

    private static let trackedOversizedOwners: Set<String> = [
        "AI/InferenceEngine.swift",
        "Network/ExploreAPIModels.swift",
        "Network/FieldTripAPIModels.swift",
        "Network/SupabaseManager.swift",
        "Security/ConsentManager.swift"
    ]

    private static let liveEffectTokens = [
        "@Observable",
        ".from(\"",
        ".rpc(",
        "AppDIContainer",
        "MerianNetworkClient",
        "ModelContainer",
        "ModelContext(",
        "NotificationCenter.default",
        "Purchases.shared",
        "RevenueCatManager",
        "SupabaseManager",
        "Task {",
        "Task.detached",
        "URLSession.shared",
        "URLSession(configuration:",
        "UIApplication.shared",
        "UsageManager",
        "UserDefaults.standard",
        "import Supabase",
        "import SwiftData",
        "static let shared"
    ]

    private static let documentedPolicyInputTokens = [
        ".resourceValues(",
        "Date()",
        "Double.random(",
        "FileManager.default",
        "InferenceAudioPreparer.isEdgeCompatibleWAV",
        "fileManager: FileManager = .default",
        "hasStoreArtifacts(at:"
    ]

    private static let allowedPolicyInputTokens: [String: Set<String>] = [
        "Data/OfflineSync/Policies/BackgroundInferencePolicy.swift": [
            "Date()"
        ],
        "Data/OfflineSync/Policies/MediaStagingContract.swift": [
            "FileManager.default",
            "InferenceAudioPreparer.isEdgeCompatibleWAV"
        ],
        "Data/OfflineSync/Policies/OfflineQueueRetryPolicy.swift": [
            "Double.random("
        ],
        "Data/OfflineSync/Policies/OfflineQueueStoragePolicy.swift": [
            ".resourceValues("
        ],
        "Data/StoreRecovery/Policies/ModelStoreRecoveryPolicy.swift": [
            "fileManager: FileManager = .default",
            "hasStoreArtifacts(at:"
        ],
        "Security/RevenueCat/Policies/RevenueCatAccessPolicies.swift": [
            "Date()"
        ]
    ]

    private static let componentEffectTokens = [
        ".from(\"",
        ".rpc(",
        "MerianNetworkClient",
        "FileManager.default",
        "ModelContainer",
        "ModelContext",
        "Purchases.shared",
        "RevenueCatManager",
        "SupabaseClient",
        "SupabaseManager",
        "URLRequest(",
        "URLSession",
        "UsageManager",
        "UserDefaults.standard",
        "import RevenueCat",
        "import Supabase",
        "import SwiftData"
    ]

    private static let silentSwiftDataReadPattern =
        #"try\?\s*(?:await\s+)?(?:context|[A-Za-z_][A-Za-z0-9_]*Context)\.(?:fetch|fetchCount)\s*\("#

    private static let sensitivePublicLogPatterns = [
        #"\(\s*(?:error|[A-Za-z_][A-Za-z0-9_]*Error)\s*,\s*privacy:\s*\.public\s*\)"#,
        #"localizedDescription(?:(?!privacy:)[\s\S]){0,160}privacy:\s*\.public"#,
        #"terminal server failure(?:(?!message=)[\s\S]){0,200}message=(?:(?!privacy:)[\s\S]){0,160}privacy:\s*\.public"#,
        #"(?:tempPath|resultFileURL\.path|outputURL\.lastPathComponent|callbackURL\.lastPathComponent|[Ff]ileNames)(?:(?!privacy:)[\s\S]){0,200}privacy:\s*\.public"#
    ]
}
