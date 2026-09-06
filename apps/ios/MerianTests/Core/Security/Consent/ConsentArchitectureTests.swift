import Foundation
import Testing

@Suite("Consent Architecture")
struct ConsentArchitectureTests {
    @Test func consentOwnersHaveFocusedBoundaries() throws {
        let consentRoot = try securityRoot().appendingPathComponent("Consent")
        let actualPaths = try Set(
            swiftFiles(below: consentRoot).map {
                String($0.path.dropFirst(consentRoot.path.count + 1))
            }
        )
        #expect(actualPaths == Self.extractedOwnerPaths)

        let manager = try securitySource("ConsentManager.swift")
        let models = try consentSource("Models/ConsentModels.swift")
        let policy = try consentSource("Models/ConsentPolicy.swift")
        let errors = try consentSource("Models/ConsentErrors.swift")
        let authority = try consentSource(
            "Policies/ConsentAuthorityPolicy.swift"
        )
        let ownership = try consentSource(
            "Policies/ConsentLedgerOwnershipPolicy.swift"
        )
        let retry = try consentSource("Policies/ConsentRetryPolicy.swift")
        let synchronizationMergePolicy = try consentSource(
            "Policies/ConsentSynchronizationMergePolicy.swift"
        )
        let realtimeCoordinator = try consentSource(
            "Coordinators/ConsentRealtimeCoordinator.swift"
        )
        let synchronizationCoordinator = try consentSource(
            "Coordinators/ConsentSynchronizationCoordinator.swift"
        )
        let restorationCoordinator = try consentSource(
            "Coordinators/RequiredConsentRestorationCoordinator.swift"
        )
        let ledgerRepository = try consentSource(
            "Repositories/ConsentLedgerRepository.swift"
        )
        let remoteModels = try consentSource(
            "Services/ConsentRemoteModels.swift"
        )
        let remoteService = try consentSource(
            "Services/ConsentRemoteService.swift"
        )
        let liveRemoteService = try consentSource(
            "Services/ConsentRemoteService+Live.swift"
        )
        let liveRealtimeCoordinator = try consentSource(
            "Services/ConsentRealtimeCoordinator+Live.swift"
        )

        for declaration in [
            "enum AdultConfirmationMethod",
            "enum AIConsentEventKind",
            "enum AnalyticsConsentEventKind",
            "enum AnalyticsCloudAuthorityState",
            "enum RequiredConsentRestorationState",
            "struct AdultEligibilityReceipt",
            "struct TermsAcceptanceReceipt",
            "struct AIConsentEvent",
            "struct AnalyticsConsentEvent",
            "struct AnalyticsRevocationIntent",
            "struct AnalyticsRevocationJournal",
            "struct LocalLedger",
            "struct RemoteState"
        ] {
            #expect(containsDeclaration(declaration, in: models))
            #expect(!containsDeclaration(declaration, in: manager))
        }

        #expect(containsDeclaration("enum ConsentPolicy", in: policy))
        #expect(!containsDeclaration("enum ConsentPolicy", in: manager))
        for declaration in [
            "enum ConsentHandoffError",
            "enum ConsentPersistenceError"
        ] {
            #expect(containsDeclaration(declaration, in: errors))
            #expect(!containsDeclaration(declaration, in: manager))
        }

        #expect(authority.contains("enum ConsentAuthorityPolicy"))
        #expect(ownership.contains("enum ConsentLedgerOwnershipPolicy"))
        #expect(retry.contains("enum ConsentRetryPolicy"))
        #expect(
            synchronizationMergePolicy.contains(
                "enum ConsentSynchronizationMergePolicy"
            )
        )
        #expect(
            realtimeCoordinator.contains(
                "final class ConsentRealtimeCoordinator"
            )
        )
        #expect(
            realtimeCoordinator.contains("struct Dependencies")
        )
        #expect(realtimeCoordinator.contains("final class Subscription"))
        #expect(
            realtimeCoordinator.contains(
                "private var removalTask: Task<Void, Never>?"
            )
        )
        #expect(realtimeCoordinator.contains("if let removalTask"))
        #expect(realtimeCoordinator.contains("await removalTask.value"))
        #expect(
            realtimeCoordinator.contains(
                "private var teardownTasks: [UUID: Task<Void, Never>] = [:]"
            )
        )
        #expect(realtimeCoordinator.contains("func awaitTeardown() async"))
        #expect(
            realtimeCoordinator.contains(
                "self?.teardownTasks.removeValue(forKey: id)"
            )
        )
        #expect(realtimeCoordinator.contains("deinit {"))
        #expect(
            realtimeCoordinator.contains("let subscription = subscription")
        )
        #expect(
            realtimeCoordinator.contains(
                "self.subscription === subscription"
            )
        )
        #expect(!realtimeCoordinator.contains("self.subscription?.id"))
        #expect(
            manager.contains(
                "private let realtimeCoordinator: ConsentRealtimeCoordinator"
            )
        )
        #expect(
            occurrences(
                of: "realtimeCoordinator.ensureUpdates(for: userId)",
                in: manager
            ) == 3
        )
        #expect(manager.contains("realtimeCoordinator.stopUpdates()"))
        #expect(
            manager.contains("await realtimeCoordinator.awaitTeardown()")
        )
        #expect(
            manager.contains(
                "func cancelAndAwaitAccountBoundWorkForAuthTransition() async"
            )
        )
        #expect(
            synchronizationCoordinator.contains(
                "final class ConsentSynchronizationCoordinator"
            )
        )
        #expect(
            manager.contains(
                "private let synchronizationCoordinator:"
            )
        )
        #expect(
            restorationCoordinator.contains(
                "final class RequiredConsentRestorationCoordinator"
            )
        )
        #expect(restorationCoordinator.contains("struct Dependencies"))
        #expect(
            manager.contains(
                "private let restorationCoordinator:"
            )
        )
        #expect(
            manager.contains(
                "self?.requiredConsentRestorationState = state"
            )
        )
        #expect(
            occurrences(
                of: "requiredConsentRestorationState =",
                in: manager
            ) == 1
        )
        for relocatedRestorationState in [
            "requiredConsentRestorationRetryTask",
            "requiredConsentRestorationRetryAttempt"
        ] {
            #expect(!manager.contains(relocatedRestorationState))
        }
        for restorationState in [
            "private(set) var state:",
            "private var retryAttempt = 0",
            "private var retryTasks: [UUID: Task<Void, Never>] = [:]",
            "private var currentRetryTaskId: UUID?"
        ] {
            #expect(restorationCoordinator.contains(restorationState))
        }
        for relocatedRestorationFunction in [
            "handleSynchronizationFailure",
            "scheduleRetry",
            "isRetryPending",
            "belongs",
            "resetRetry"
        ] {
            #expect(
                restorationCoordinator.contains(
                    "func \(relocatedRestorationFunction)("
                )
            )
        }
        #expect(restorationCoordinator.contains("retryTasks[id] = nil"))
        #expect(restorationCoordinator.contains("currentRetryTaskId == id"))
        let beginRetrySource = restorationCoordinator
            .components(separatedBy: "func beginRetry(")
            .dropFirst()
            .first?
            .components(separatedBy: "func isRetryPending(")
            .first ?? ""
        #expect(!beginRetrySource.isEmpty)
        #expect(beginRetrySource.contains("guard !Task.isCancelled,"))
        #expect(
            restorationCoordinator.contains(
                "retryTasks: Array(retryTasks.values)"
            )
        )
        #expect(manager.contains("await restoration.wait()"))
        #expect(!restorationCoordinator.contains("import Supabase"))
        #expect(!restorationCoordinator.contains("SupabaseManager"))
        #expect(!restorationCoordinator.contains(".shared"))
        #expect(!restorationCoordinator.contains("MerianLog"))
        #expect(!restorationCoordinator.contains("PostHogManager"))
        #expect(!restorationCoordinator.contains("Observation"))
        #expect(!restorationCoordinator.contains("TestExecutionCoordinator"))
        #expect(
            manager.contains(
                "try await synchronizationCoordinator.synchronize(for: userId)"
            )
        )
        let authTransitionDrainSource = manager
            .components(
                separatedBy:
                    "func cancelAndAwaitAccountBoundWorkForAuthTransition() async"
            )
            .dropFirst()
            .first?
            .components(
                separatedBy: "private func requiresRequiredConsentReapproval("
            )
            .first ?? ""
        #expect(!authTransitionDrainSource.isEmpty)
        #expect(
            authTransitionDrainSource.contains(
                "let cancelledWork = invalidateSynchronizationWork()"
            )
        )
        #expect(
            authTransitionDrainSource.contains(
                "await cancelledWork.wait()"
            )
        )
        #expect(
            synchronizationCoordinator.contains(
                "private var scheduledTasks: [UUID: Task<Void, Never>] = [:]"
            )
        )
        #expect(
            synchronizationCoordinator.contains(
                "private var activeTasks: [UUID: Task<Void, Error>] = [:]"
            )
        )
        #expect(
            synchronizationCoordinator.contains(
                "scheduledTasks: Array(scheduledTasks.values)"
            )
        )
        #expect(
            synchronizationCoordinator.contains(
                "activeTasks: Array(activeTasks.values)"
            )
        )
        for relocatedSynchronizationState in [
            "scheduledSyncTask",
            "activeSyncTask",
            "activeSyncUserId",
            "activeSyncGeneration"
        ] {
            #expect(!manager.contains(relocatedSynchronizationState))
        }
        #expect(!manager.contains("private var synchronizationGeneration"))
        #expect(
            synchronizationCoordinator.contains(
                "private(set) var generation: UInt = 0"
            )
        )
        for relocatedSynchronizationFunction in [
            "performSynchronization",
            "bindUnownedRecords",
            "pushPendingRecords",
            "validateSynchronization"
        ] {
            #expect(
                !manager.contains("func \(relocatedSynchronizationFunction)(")
            )
            #expect(
                synchronizationCoordinator.contains(
                    "func \(relocatedSynchronizationFunction)("
                )
            )
        }
        #expect(!synchronizationCoordinator.contains("import Supabase"))
        #expect(!synchronizationCoordinator.contains("SupabaseManager"))
        #expect(!synchronizationCoordinator.contains(".shared"))
        #expect(!synchronizationCoordinator.contains("MerianLog"))
        #expect(!synchronizationCoordinator.contains("PostHogManager"))
        #expect(!synchronizationCoordinator.contains("Observation"))
        #expect(!synchronizationMergePolicy.contains("import Supabase"))
        #expect(!synchronizationMergePolicy.contains("Task"))
        #expect(!synchronizationMergePolicy.contains(".shared"))
        for relocatedRealtimeState in [
            "analyticsConsentChannel",
            "analyticsConsentChannelUserId",
            "analyticsConsentSubscribedUserId",
            "analyticsConsentListenerTask",
            "analyticsConsentRetryTask",
            "analyticsConsentRetryUserId",
            "analyticsConsentRetryAttempt",
            "analyticsConsentSubscriptionGeneration"
        ] {
            #expect(!manager.contains(relocatedRealtimeState))
        }
        for relocatedRealtimeFunction in [
            "ensureAnalyticsConsentUpdates",
            "startAnalyticsConsentUpdates",
            "stopAnalyticsConsentUpdates",
            "isCurrentAnalyticsConsentSubscription",
            "finishAnalyticsConsentSubscription",
            "scheduleAnalyticsConsentRetry"
        ] {
            #expect(!manager.contains("func \(relocatedRealtimeFunction)("))
        }
        #expect(!realtimeCoordinator.contains("import Supabase"))
        #expect(!realtimeCoordinator.contains("SupabaseManager"))
        #expect(!realtimeCoordinator.contains("RealtimeChannelV2"))
        #expect(!realtimeCoordinator.contains("InsertAction"))
        #expect(!realtimeCoordinator.contains(".shared"))
        #expect(!realtimeCoordinator.contains("MerianLog"))
        #expect(!realtimeCoordinator.contains("user_analytics_consent_events"))
        #expect(liveRealtimeCoordinator.contains("import Supabase"))
        #expect(liveRealtimeCoordinator.contains("SupabaseManager.shared"))
        #expect(liveRealtimeCoordinator.contains("RealtimeChannelV2"))
        #expect(liveRealtimeCoordinator.contains("InsertAction.self"))
        #expect(liveRealtimeCoordinator.contains("subscribeWithError()"))
        #expect(liveRealtimeCoordinator.contains("removeChannel(channel)"))
        #expect(
            liveRealtimeCoordinator.contains(
                "table: \"user_analytics_consent_events\""
            )
        )
        #expect(
            liveRealtimeCoordinator.contains(
                "filter: .eq(\"user_id\", value: userId.uuidString)"
            )
        )
        #expect(!manager.contains("import Supabase"))
        #expect(!manager.contains("RealtimeChannelV2"))
        #expect(!manager.contains("postgresChange("))
        #expect(!manager.contains("subscribeWithError()"))
        #expect(!manager.contains("removeChannel("))
        #expect(
            ledgerRepository.contains("final class ConsentLedgerRepository")
        )
        #expect(
            ledgerRepository.contains(
                "private var pendingAnalyticsRevocationJournal:"
            )
        )
        #expect(manager.contains("ConsentLedgerRepository(store: ledgerStore)"))
        #expect(!ledgerRepository.contains("import Supabase"))
        #expect(!ledgerRepository.contains("import Observation"))
        #expect(!ledgerRepository.contains("SupabaseManager"))
        #expect(!ledgerRepository.contains("PostHogManager"))
        #expect(!ledgerRepository.contains("URLSession"))
        #expect(!ledgerRepository.contains("Task"))
        #expect(!ledgerRepository.contains(".shared"))
        for relocatedFunction in [
            "persistLedger",
            "persistConsentChange",
            "persistAnalyticsRevocation",
            "saveAnalyticsRevocationJournal",
            "clearAnalyticsRevocationJournal",
            "recoverPendingAnalyticsRevocation",
            "rebindPendingAnalyticsRevocationJournal",
            "ledgerByApplyingPendingAnalyticsRevocation",
            "pendingAnalyticsRevocationEvent",
            "pendingAnalyticsRevocationApplies"
        ] {
            #expect(ledgerRepository.contains("func \(relocatedFunction)("))
            #expect(!manager.contains("func \(relocatedFunction)("))
        }
        for relocatedPersistenceCall in [
            "loadLedgerData()",
            "saveLedgerData(",
            "loadAnalyticsRevocationIntentData()",
            "saveAnalyticsRevocationIntentData(",
            "clearAnalyticsRevocationIntentData()",
            "JSONEncoder()",
            "JSONDecoder()"
        ] {
            #expect(ledgerRepository.contains(relocatedPersistenceCall))
            #expect(!manager.contains(relocatedPersistenceCall))
        }

        for declaration in [
            "struct AdultEligibilityReceiptInsert",
            "struct TermsReceiptInsert",
            "struct AIConsentEventAppend",
            "struct AnalyticsConsentEventAppend",
            "struct ConsentAppendResult",
            "struct AdultEligibilityReceipt",
            "struct TermsReceipt",
            "struct AIConsentEvent",
            "struct AnalyticsConsentEvent",
            "struct RemoteRows"
        ] {
            #expect(containsDeclaration(declaration, in: remoteModels))
        }
        #expect(remoteService.contains("struct ConsentRemoteService"))
        #expect(!remoteModels.contains("import Supabase"))
        #expect(!remoteModels.contains("SupabaseManager"))
        #expect(!remoteModels.contains(".shared"))
        #expect(!remoteModels.contains(".from("))
        #expect(!remoteModels.contains(".rpc("))
        #expect(!remoteService.contains("import Supabase"))
        #expect(!remoteService.contains("SupabaseManager"))
        #expect(!remoteService.contains(".shared"))
        #expect(
            occurrences(
                of: "try Self.firstMappedRemoteRow(",
                in: remoteService
            ) == 10
        )
        #expect(!remoteService.contains(".first.flatMap("))
        #expect(
            remoteService.contains("matchesAdultEligibilityReceipt")
        )
        #expect(remoteService.contains("matchesTermsReceipt"))
        #expect(liveRemoteService.contains("import Supabase"))
        #expect(liveRemoteService.contains("SupabaseManager.shared"))
        #expect(liveRemoteService.contains("async let"))

        for contractName in [
            "user_adult_eligibility_receipts",
            "user_terms_acceptance_receipts",
            "user_ai_consent_events",
            "user_analytics_consent_events",
            "append_user_ai_consent_event",
            "append_user_analytics_consent_event"
        ] {
            #expect(liveRemoteService.contains(contractName))
        }
        for relocatedContractName in [
            "user_adult_eligibility_receipts",
            "user_terms_acceptance_receipts",
            "user_ai_consent_events",
            "append_user_ai_consent_event",
            "append_user_analytics_consent_event"
        ] {
            #expect(!manager.contains(relocatedContractName))
        }
        #expect(!manager.contains("user_analytics_consent_events"))
        #expect(!manager.contains(".from("))
        #expect(!manager.contains(".rpc("))

        for function in [
            "isAuthoritativeAnalyticsGrant",
            "isAuthoritativeRequiredConsent",
            "rebinding",
            "activating",
            "requiredConsentRestorationRetryDelay",
            "analyticsConsentRetryDelay",
            "isSynchronizationContextCurrent"
        ] {
            #expect(!manager.contains("static func \(function)("))
        }

        try assertExtractedProductionTypesRemainOwned()
    }

    @Test func extractedOwnersRemainSmallAndPolicyLayerInfrastructureFree() throws {
        let consentRoot = try securityRoot().appendingPathComponent("Consent")
        for file in try swiftFiles(below: consentRoot) {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(
                lineCount(source) <= 600,
                "\(file.lastPathComponent) exceeded the Consent review ceiling"
            )
            let relativePath = String(
                file.path.dropFirst(consentRoot.path.count + 1)
            )
            guard relativePath.hasPrefix("Models/")
                || relativePath.hasPrefix("Policies/") else {
                continue
            }
            #expect(!source.contains("import Supabase"))
            #expect(!source.contains("import Observation"))
            #expect(!source.contains(".shared"))
            #expect(!source.contains("URLSession"))
            #expect(!source.contains("Task"))
            #expect(!source.contains("MerianLog"))
            #expect(!source.contains("PostHogManager"))
            #expect(!source.contains("KeychainManager"))
        }
    }

    private static let extractedOwnerPaths: Set<String> = [
        "Models/ConsentErrors.swift",
        "Models/ConsentModels.swift",
        "Models/ConsentPolicy.swift",
        "Coordinators/ConsentRealtimeCoordinator.swift",
        "Coordinators/RequiredConsentRestorationCoordinator.swift",
        "Coordinators/ConsentSynchronizationCoordinator.swift",
        "Policies/ConsentAuthorityPolicy.swift",
        "Policies/ConsentLedgerOwnershipPolicy.swift",
        "Policies/ConsentRetryPolicy.swift",
        "Policies/ConsentSynchronizationMergePolicy.swift",
        "Repositories/ConsentLedgerRepository.swift",
        "Services/ConsentRealtimeCoordinator+Live.swift",
        "Services/ConsentRemoteModels.swift",
        "Services/ConsentRemoteService+Live.swift",
        "Services/ConsentRemoteService.swift"
    ]

    private func consentSource(_ path: String) throws -> String {
        try securitySource("Consent/\(path)")
    }

    private func securitySource(_ path: String) throws -> String {
        try String(
            contentsOf: securityRoot().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private func securityRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Security"
        )
    }

    private func swiftFiles(below directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        return enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift" else {
                return nil
            }
            return url
        }
    }

    private func lineCount(_ source: String) -> Int {
        let newlineDelimitedLines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
        return newlineDelimitedLines - (source.hasSuffix("\n") ? 1 : 0)
    }

    private func assertExtractedProductionTypesRemainOwned() throws {
        let applicationRoot = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian"
        )
        let managerPath = "Core/Security/ConsentManager.swift"
        let realtimeCoordinatorPath =
            "Core/Security/Consent/Coordinators/ConsentRealtimeCoordinator.swift"
        let restorationCoordinatorPath =
            "Core/Security/Consent/Coordinators/RequiredConsentRestorationCoordinator.swift"
        let synchronizationCoordinatorPath =
            "Core/Security/Consent/Coordinators/ConsentSynchronizationCoordinator.swift"
        let synchronizationMergePolicyPath =
            "Core/Security/Consent/Policies/ConsentSynchronizationMergePolicy.swift"
        let liveRealtimeCoordinatorPath =
            "Core/Security/Consent/Services/ConsentRealtimeCoordinator+Live.swift"
        let ledgerRepositoryPath =
            "Core/Security/Consent/Repositories/ConsentLedgerRepository.swift"
        let policyAllowedPaths: [String: Set<String>] = [
            "ConsentAuthorityPolicy": [
                managerPath,
                "Core/Security/Consent/Policies/ConsentAuthorityPolicy.swift",
                synchronizationMergePolicyPath
            ],
            "ConsentLedgerOwnershipPolicy": [
                ledgerRepositoryPath,
                "Core/Security/Consent/Policies/ConsentLedgerOwnershipPolicy.swift"
            ],
            "ConsentRetryPolicy": [
                managerPath,
                realtimeCoordinatorPath,
                restorationCoordinatorPath,
                synchronizationCoordinatorPath,
                "Core/Security/Consent/Policies/ConsentRetryPolicy.swift"
            ],
            "ConsentSynchronizationMergePolicy": [
                managerPath,
                synchronizationCoordinatorPath,
                synchronizationMergePolicyPath
            ]
        ]
        let ledgerRepositoryAllowedPaths: Set<String> = [
            managerPath,
            ledgerRepositoryPath,
            synchronizationCoordinatorPath
        ]
        let serviceAllowedPaths: Set<String> = [
            managerPath,
            synchronizationCoordinatorPath,
            "Core/Security/Consent/Services/ConsentRemoteService.swift",
            "Core/Security/Consent/Services/ConsentRemoteService+Live.swift"
        ]
        let wireAllowedPaths: Set<String> = [
            "Core/Security/Consent/Services/ConsentRemoteModels.swift",
            "Core/Security/Consent/Services/ConsentRemoteService.swift",
            "Core/Security/Consent/Services/ConsentRemoteService+Live.swift"
        ]
        let realtimeCoordinatorAllowedPaths: Set<String> = [
            managerPath,
            realtimeCoordinatorPath,
            liveRealtimeCoordinatorPath
        ]
        let synchronizationCoordinatorAllowedPaths: Set<String> = [
            managerPath,
            synchronizationCoordinatorPath
        ]

        for file in try swiftFiles(below: applicationRoot) {
            let relativePath = String(
                file.path.dropFirst(applicationRoot.path.count + 1)
            )
            let source = try String(contentsOf: file, encoding: .utf8)
            for (policyName, allowedPaths) in policyAllowedPaths
            where !allowedPaths.contains(relativePath) {
                #expect(
                    !containsToken(policyName, in: source),
                    "\(relativePath) bypasses the reviewed Consent policy owners"
                )
            }
            if !ledgerRepositoryAllowedPaths.contains(relativePath) {
                #expect(
                    !containsToken("ConsentLedgerRepository", in: source),
                    "\(relativePath) bypasses the Consent ledger repository"
                )
            }
            if !serviceAllowedPaths.contains(relativePath) {
                #expect(
                    !containsToken("ConsentRemoteService", in: source),
                    "\(relativePath) bypasses the ConsentManager facade"
                )
            }
            if !wireAllowedPaths.contains(relativePath) {
                #expect(
                    !containsToken("ConsentRemoteWire", in: source),
                    "\(relativePath) bypasses the Consent remote-service boundary"
                )
            }
            if !realtimeCoordinatorAllowedPaths.contains(relativePath) {
                #expect(
                    !containsToken("ConsentRealtimeCoordinator", in: source),
                    "\(relativePath) bypasses the Consent Realtime coordinator"
                )
            }
            if !synchronizationCoordinatorAllowedPaths.contains(relativePath) {
                #expect(
                    !containsToken(
                        "ConsentSynchronizationCoordinator",
                        in: source
                    ),
                    "\(relativePath) bypasses the Consent synchronization coordinator"
                )
            }
        }
    }

    private func containsToken(_ token: String, in source: String) -> Bool {
        let escapedToken = NSRegularExpression.escapedPattern(for: token)
        let pattern = #"\b"# + escapedToken + #"\b"#
        return source.range(of: pattern, options: .regularExpression) != nil
    }

    private func occurrences(of token: String, in source: String) -> Int {
        source.components(separatedBy: token).count - 1
    }

    private func containsDeclaration(
        _ declaration: String,
        in source: String
    ) -> Bool {
        let escapedDeclaration = NSRegularExpression.escapedPattern(
            for: declaration
        )
        let pattern =
            #"(?m)^\s*(?:(?:private|fileprivate|internal|package|public)\s+)?"#
            + escapedDeclaration
            + #"(?:\s*[:{])"#
        return source.range(of: pattern, options: .regularExpression) != nil
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
