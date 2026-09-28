import Foundation
import SwiftData
import Testing

@testable import Merian

@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct OfflineQueueOpenAIPermissionTests {
    enum Scenario: CaseIterable, Equatable {
        case matching, otherAccount, missingAccount, missingFunding, releasedFunding
        case mismatchedScan, withdrawn, accountTransition
    }

    @Test(arguments: Scenario.allCases)
    func explicitRetryRequiresOwnedFundingAndCurrentPermission(scenario: Scenario) throws {
        let manager = OfflineQueueManager.shared
        let oldContext = manager.modelContext
        let oldOnline = manager.isOnline
        let oldCount = manager.unsyncedItemsCount
        let container = try ModelContainer(
            for: Schema(CurrentSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        manager.modelContext = context
        manager.isOnline = false
        defer {
            OfflineJobScheduler.shared.cancelScheduledWake(using: manager)
            manager.modelContext = oldContext
            manager.isOnline = oldOnline
            manager.unsyncedItemsCount = oldCount
        }
        let owner = UUID()
        let currentAccount: UUID? = scenario == .missingAccount ? nil
            : scenario == .otherAccount ? UUID() : owner
        let scanID = UUID().uuidString.lowercased()
        let scan = OfflineQueuedScan(
            id: scanID, scanState: .failed, inferenceImagePaths: ["synthetic-photo.webp"],
            queueAttemptCount: 3, queueLastErrorCode: "ai_openai_consent_required",
            queueNeedsAttention: true
        )
        var metadata = OfflineScanJobMetadataContract.json(
            generation: nil,
            funding: ScanFundingReservation(
                accountId: owner,
                scanId: scenario == .mismatchedScan ? UUID().uuidString.lowercased() : scanID,
                source: .complimentaryPro
            )
        )
        if scenario == .missingFunding { metadata = nil }
        if scenario == .releasedFunding {
            metadata = OfflineScanJobMetadataContract.markingFundingReleased(in: metadata)
        }
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanID),
            kind: .scanIngestion, subjectId: scanID, status: .needsAttention,
            lastErrorCode: "ai_openai_consent_required", metadataJSON: metadata
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let repository = ConsentLedgerRepository(store: FaultInjectingConsentLedgerStore())
        let permission = AIProcessingConsentCoordinator(
            repository: repository, mutationService: ConsentMutationService(ledgerRepository: repository),
            isOpenAICollectionEnabled: true
        )
        permission.setHandlers(contextProvider: {
            .init(observedUserId: currentAccount, sdkUserId: currentAccount, isAccountTransitionInProgress: false)
        }, synchronize: {})
        permission.refresh(ownerUserId: currentAccount)
        if currentAccount != nil {
            try permission.setOpenAIEnabled(true, expectedOwnerUserId: currentAccount)
            if scenario == .withdrawn {
                try permission.setOpenAIEnabled(false, expectedOwnerUserId: currentAccount)
            }
        }
        if scenario == .accountTransition {
            permission.setHandlers(contextProvider: {
                .init(observedUserId: currentAccount, sdkUserId: currentAccount, isAccountTransitionInProgress: true)
            }, synchronize: {})
        }
        if let currentAccount {
            let owned = manager.ownsOpenAIConsentPausedScan(scanId: scanID, accountId: currentAccount)
            #expect(owned == [.matching, .withdrawn, .accountTransition].contains(scenario))
        }
        let retried = manager.retryQueuedScanNow(scanId: scanID, openAIPermission: permission)
        #expect(retried == (scenario == .matching))
        #expect(scan.inferenceImagePaths == ["synthetic-photo.webp"])
        #expect(job.metadataJSON == metadata)
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        if scenario == .matching {
            #expect(scan.queueState == .pending)
            #expect(!scan.queueNeedsAttention)
            #expect(job.status == .pending)
        } else {
            #expect(scan.queueState == .failed)
            #expect(scan.queueNeedsAttention)
            #expect(scan.queueLastErrorCode == "ai_openai_consent_required")
            #expect(scan.queueAttemptCount == 3)
            #expect(job.status == .needsAttention)
            #expect(try context.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == 0)
        }
    }
}
