import Foundation
import Testing

@Suite("Native owner capability boundary")
struct SharedMediaNativeOwnerBoundaryTests {
    @Test func capabilityConstructorsRemainWithTheirSoleMintingOwner() throws {
        let owner = try source("SharedMediaNativeOriginalOwner.swift")
        let repository = try source("SharedMediaNativeStorageRepository.swift")
        #expect(owner.contains("private init(account:"))
        #expect(owner.components(separatedBy: "fileprivate init(owner:").count == 6)
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
            #expect(!file.contents.contains("SharedMediaNativeScopedReadGrant(owner:"), "Scoped read grant escaped its owner: \(file.relativePath)")
        }
    }

    @Test func repositoryOperationsRequireDispatchAndSettlementCannotDispatch() throws {
        let repository = try source("SharedMediaNativeStorageRepository.swift")
        let names = ["originalAdmission", "inspectOriginals", "originalReadback", "originalReceipt", "reservedState",
                     "reserveOriginal", "writeOriginal", "loadOriginal", "completeOriginal", "metadata",
                     "saveMetadata", "preparationOperations", "lifecycleOperations"]
        for name in names {
            let start = try #require(repository.range(of: "func " + name + "("))
            let tail = repository[start.lowerBound...]
            let end = try #require(tail.firstIndex(of: "{"))
            #expect(tail[..<end].contains("SharedMediaNativeDispatchGrant"), "Unguarded repository API: \(name)")
        }
        let start = try #require(repository.range(of: "func settleOriginal("))
        let end = try #require(repository.range(of: "    func metadata(", range: start.upperBound..<repository.endIndex))
        let settlement = String(repository[start.lowerBound..<end.lowerBound])
        #expect(settlement.contains("SharedMediaNativeSettlementGrant"))
        #expect(settlement.contains("SharedMediaNativeAcquisitionMutation.hold("))
        for forbidden in ["originalIO", "reserveOriginal(", "dispatchAuthority(", "preparationOperations(", "lifecycleOperations(", "Task {"] {
            #expect(!settlement.contains(forbidden), "Settlement gained dispatch authority: \(forbidden)")
        }
    }

    private func source(_ name: String) throws -> String {
        try DatabaseActorTestSupport.loadRepositorySource(at: "apps/ios/Merian/Core/Data/SharedMediaStorage/" + name)
    }
}
