import Foundation
import Testing

@Suite("Native owner capability boundary")
struct SharedMediaNativeOwnerBoundaryTests {
    @Test func capabilityConstructorsRemainWithTheirSoleMintingOwner() throws {
        let owner = try source("SharedMediaNativeOriginalOwner.swift")
        let repository = try source("SharedMediaNativeStorageRepository.swift")
        #expect(owner.contains("private init(account:"))
        #expect(owner.components(separatedBy: "fileprivate init(owner:").count == 7)
        #expect(repository.contains("private init(container:"))
        #expect(repository.contains("fileprivate init(binding:"))
        #expect(repository.contains("fileprivate init(bytes:"))
        #expect(!repository.contains("final class SharedMediaNativeOriginalOwner"))
        #expect(!owner.contains("func mutationAuthority"))
        let files = try DatabaseActorTestSupport.swiftSources(below: "apps/ios/Merian")
        for file in files where !file.relativePath.hasSuffix("SharedMediaNativeOriginalOwner.swift") {
            #expect(!file.contents.contains("SharedMediaNativeDispatchGrant(owner:"), "Dispatch grant escaped its owner: \(file.relativePath)")
            #expect(!file.contents.contains("SharedMediaNativeSettlementGrant(owner:"), "Settlement grant escaped its owner: \(file.relativePath)")
            #expect(!file.contents.contains("SharedMediaNativeAppGrant(owner:"), "App grant escaped its owner: \(file.relativePath)")
            #expect(!file.contents.contains("SharedMediaNativeAppDispatchGrant(owner:"), "App dispatch grant escaped its owner: \(file.relativePath)")
            #expect(!file.contents.contains("SharedMediaNativeAppSettlementGrant(owner:"), "App settlement grant escaped its owner: \(file.relativePath)")
            #expect(!file.contents.contains("SharedMediaNativeScopedReadGrant(owner:"), "Scoped read grant escaped its owner: \(file.relativePath)")
        }
    }

    @Test func repositoryOperationsRequireDispatchAndSettlementCannotDispatch() throws {
        let repository = try source("SharedMediaNativeStorageRepository.swift")
        let names = ["originalAdmission", "inspectOriginals", "qualificationOperations"]
        for name in names {
            let start = try #require(repository.range(of: "func " + name + "("))
            let tail = repository[start.lowerBound...]
            let end = try #require(tail.firstIndex(of: "{"))
            #expect(tail[..<end].contains("SharedMediaNativeDispatchGrant"), "Unguarded repository API: \(name)")
        }
        let operations = try source("SharedMediaNativeQualificationOperations.swift")
        #expect(operations.contains("private let authority: SharedMediaNativeMutationAuthority"))
        #expect(operations.contains("private let checkDispatch: () throws -> Void"))
        #expect(repository.contains("checkDispatch: { try self.requireDispatch(grant) }"))
        let start = try #require(repository.range(of: "func settleOriginal("))
        let end = try #require(repository.range(of: "    private func metadataBoundary(", range: start.upperBound..<repository.endIndex))
        let settlement = String(repository[start.lowerBound..<end.lowerBound])
        #expect(settlement.contains("SharedMediaNativeSettlementGrant"))
        #expect(settlement.contains("try requireSettlement(grant)"))
        #expect(settlement.contains("SharedMediaNativeQualificationPersistence.settle("))
        let persistence = try source("SharedMediaNativeQualificationPersistence.swift")
        let helperStart = try #require(persistence.range(of: "static func settle("))
        let helperEnd = try #require(persistence.range(of: "    static func metadata(", range: helperStart.upperBound..<persistence.endIndex))
        let helper = String(persistence[helperStart.lowerBound..<helperEnd.lowerBound])
        #expect(helper.contains("SharedMediaNativeSettlementGrant"))
        #expect(helper.contains("SharedMediaNativeMutationAuthority"))
        #expect(helper.contains("SharedMediaNativeAcquisitionMutation.hold("))
        for forbidden in ["originalIO", "reserveOriginal(", "dispatchAuthority(", "preparationOperations(", "lifecycleOperations(", "Task {"] {
            #expect(!settlement.contains(forbidden) && !helper.contains(forbidden), "Settlement gained dispatch authority: \(forbidden)")
        }
    }

    @Test func qualificationIdleRejectionKeepsItsExistingErrorContract() throws {
        let mutation = try source("SharedMediaNativeAcquisitionMutation.swift")
        #expect(mutation.contains("if isApp { try SharedMediaNativePreparationGraph.requireIdleFiles(context, scopedInventory: inventory, allowSavedOriginalRetirements: true) }"))
        #expect(mutation.contains("guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,"))
        #expect(mutation.contains("$0.cleanupStateRaw != \"ready\""))
        #expect(mutation.contains("throw PhotoPreparationFailure.cleanupPending"))
        let preparation = try source("SharedMediaNativePreparationGraph.swift")
        #expect(preparation.contains("allowSavedOriginalRetirements: Bool = false"))
    }

    @Test func receivingRequiresTheSealedCoordinatorGrant() throws {
        let wrapper = try source("SharedMediaNativeOriginalOwner+AppReceiving.swift")
        let owner = try source("SharedMediaNativeOriginalOwner.swift")
        let repository = try source("SharedMediaNativeStorageRepository.swift")
        #expect(wrapper.contains("fileprivate init() {}"))
        #expect(wrapper.contains("private func withReceivingLocks"))
        #expect(owner.contains("func appReceivingWorkflow<T: Sendable>(lock: SharedMediaNativeReceivingLockGrant,"))
        #expect(repository.contains("func appReceiving(grant: SharedMediaNativeAppDispatchGrant, lock: SharedMediaNativeReceivingLockGrant)"))
        let start = try #require(repository.range(of: "    func appReceiving("))
        let end = try #require(repository.range(of: "    func appAcquisition", range: start.upperBound..<repository.endIndex))
        let receiving = String(repository[start.lowerBound..<end.lowerBound])
        #expect(receiving.contains("{ try lock.validate(); try self.requireApp(grant); return try self.appHeader() }"))
        let files = try DatabaseActorTestSupport.swiftSources(below: "apps/ios/Merian")
        for file in files where !file.relativePath.hasSuffix("SharedMediaNativeOriginalOwner+AppReceiving.swift") {
            #expect(!file.contents.contains("SharedMediaNativeReceivingLockGrant()"), "Receiving lock grant escaped: \(file.relativePath)")
        }
    }

    @Test func durableReceivingCodecCannotConstructWriterRequests() throws {
        let operation = try source("SharedMediaNativeAppReceivingOperations.swift")
        let codec = try source("SharedMediaNativeReceivingIntent.swift")
        #expect(operation.contains("fileprivate init(profile: SharedMediaNativeAppProfile"))
        #expect(codec.contains("func descriptorForTransaction(header: SharedMediaNativeAppEligibility.Header) throws -> Transaction"))
        #expect(codec.contains("func reconstruct(_ prepared: Prepared) throws -> Transaction"))
        #expect(!codec.contains("SharedMediaNativeAppReceivingRequest(profile:"))
        #expect(!codec.contains("receiveAppPhotos("))
        let wrapper = try source("SharedMediaNativeOriginalOwner+AppReceiving.swift")
        #expect(!wrapper.contains("SharedMediaNativeReceivingIntent.Transaction"))
    }

    @Test func appPendingCleanupRequiresSealedScopeAndFinalAbsence() throws {
        let operation = try source("SharedMediaNativeAppPendingOperations.swift")
        #expect(operation.contains("fileprivate init(state: SharedMediaNativePendingState, binding: SharedMediaNativeBinding)"))
        #expect(operation.contains("private init(container:"))
        #expect(operation.contains("requireAbsence: releasing"))
        #expect(operation.contains("SharedMediaNativeScopedAudit(app:"))
        #expect(!operation.contains("SharedMediaNativeMutationAuthority"))
        let wrapper = try source("SharedMediaNativeOriginalOwner+AppPendingCleanup.swift")
        #expect(wrapper.contains("appPendingWorkflow"))
        let files = try DatabaseActorTestSupport.swiftSources(below: "apps/ios/Merian")
        for file in files where !file.relativePath.hasSuffix("SharedMediaNativeAppPendingOperations.swift") {
            #expect(!file.contents.contains("SharedMediaNativeAppPendingDisposalWitness(state:"), "Pending capability escaped: \(file.relativePath)")
        }
    }

    @Test func appOriginalLifecycleKeepsDisposalAndPoststatesSealed() throws {
        let operation = try source("SharedMediaNativeAppOriginalOperations.swift")
        #expect(operation.contains("fileprivate init(state: SharedMediaNativeRetirementState, binding: SharedMediaNativeBinding)"))
        #expect(operation.contains("private init(container:"))
        #expect(operation.contains("SharedMediaNativeScopedAudit(app:"))
        #expect(operation.contains("try files.requireNativeAbsence(state.file"))
        #expect(!operation.contains("SharedMediaNativeMutationAuthority"))
        let repository = try source("SharedMediaNativeStorageRepository.swift")
        #expect(repository.contains("func appOriginal(grant: SharedMediaNativeAppDispatchGrant)"))
        let files = try DatabaseActorTestSupport.swiftSources(below: "apps/ios/Merian")
        for file in files where !file.relativePath.hasSuffix("SharedMediaNativeAppOriginalOperations.swift") {
            #expect(!file.contents.contains("SharedMediaNativeAppOriginalDisposalWitness(state:"), "Original disposal escaped its owner: \(file.relativePath)")
        }
    }

    private func source(_ name: String) throws -> String {
        try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/Core/Data/SharedMediaStorage/" + name)
    }
}
