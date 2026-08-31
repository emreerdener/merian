import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct UserTagsViewModelTests {
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        return ModelContext(container)
    }

    @Test func addAndRemoveCommitBeforePublishingEffects() throws {
        let context = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "tags_test",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        context.insert(record)
        try context.save()
        var effects: [String] = []
        let viewModel = UserTagsViewModel(
            dependencies: UserTagsDependencies(
                persistMutation: { modelContext, logContext in
                    effects.append("persist:\(logContext)")
                    do {
                        try modelContext.save()
                        return true
                    } catch {
                        return false
                    }
                },
                syncToCloud: { scanID, tags in
                    effects.append("sync:\(scanID):\(tags.joined(separator: ","))")
                },
                publishSearchInvalidation: { scanID in
                    effects.append("publish:\(scanID)")
                }
            )
        )

        viewModel.addTag("  backyard  ", to: record, modelContext: context)
        #expect(record.customTags == ["backyard"])
        #expect(effects == [
            "persist:add custom tag",
            "sync:\(record.id):backyard",
            "publish:\(record.id)"
        ])
        #expect(viewModel.errorMessage == nil)

        viewModel.addTag("backyard", to: record, modelContext: context)
        #expect(record.customTags == ["backyard"])
        #expect(effects.count == 3)

        viewModel.removeTag("backyard", from: record, modelContext: context)
        #expect(record.customTags.isEmpty)
        #expect(effects == [
            "persist:add custom tag",
            "sync:\(record.id):backyard",
            "publish:\(record.id)",
            "persist:remove custom tag",
            "sync:\(record.id):",
            "publish:\(record.id)"
        ])
    }

    @Test func boundsMatchTheServerContractWithoutStartingEffects() throws {
        let context = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "tag_bounds",
            scientificName: "Test species",
            commonName: "Test"
        )
        context.insert(record)
        try context.save()
        var mutationCount = 0
        let viewModel = UserTagsViewModel(
            dependencies: UserTagsDependencies(
                persistMutation: { _, _ in
                    mutationCount += 1
                    return true
                }
            )
        )

        let oversized = String(
            repeating: "a",
            count: UserTagValidation.maximumTagCharacters + 1
        )
        viewModel.addTag(oversized, to: record, modelContext: context)
        #expect(record.customTags.isEmpty)
        #expect(viewModel.errorMessage != nil)

        viewModel.addTag(
            "line\nbreak",
            to: record,
            modelContext: context
        )
        #expect(record.customTags.isEmpty)
        #expect(viewModel.errorMessage != nil)

        record.customTags = (0..<UserTagValidation.maximumTagCount).map {
            "tag-\($0)"
        }
        try context.save()
        viewModel.addTag("one-more", to: record, modelContext: context)
        #expect(record.customTags.count == UserTagValidation.maximumTagCount)
        #expect(mutationCount == 0)
    }

    @Test func failedPersistenceRestoresPriorTagsAndSuppressesEffects() throws {
        let context = try createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "tag_failure",
            scientificName: "Test species",
            commonName: "Test"
        )
        record.customTags = ["existing"]
        context.insert(record)
        try context.save()
        var syncCount = 0
        var publishCount = 0
        let viewModel = UserTagsViewModel(
            dependencies: UserTagsDependencies(
                persistMutation: { _, _ in false },
                syncToCloud: { _, _ in syncCount += 1 },
                publishSearchInvalidation: { _ in publishCount += 1 }
            )
        )

        viewModel.addTag("new", to: record, modelContext: context)

        #expect(record.customTags == ["existing"])
        #expect(
            viewModel.errorMessage ==
                "Tags are limited to 50 labels and 64 characters each."
        )
        #expect(syncCount == 0)
        #expect(publishCount == 0)

        viewModel.removeTag("existing", from: record, modelContext: context)

        #expect(record.customTags == ["existing"])
        #expect(viewModel.errorMessage == "Tag changes could not be saved.")
        #expect(syncCount == 0)
        #expect(publishCount == 0)
    }

    @Test func cloudSyncSnapshotsCompleteInMutationOrder() async {
        let firstUserID = UUID()
        let secondUserID = UUID()
        let firstRequest = UserTagsCloudSyncCoordinator.Request(
            scanID: "ordered-tags",
            tags: ["first"],
            expectedUserID: firstUserID
        )
        let secondRequest = UserTagsCloudSyncCoordinator.Request(
            scanID: "ordered-tags",
            tags: ["second"],
            expectedUserID: secondUserID
        )
        let firstRequestGate = UserTagsCloudSyncGate()
        var startedRequests: [UserTagsCloudSyncCoordinator.Request] = []
        var completedRequests: [UserTagsCloudSyncCoordinator.Request] = []
        let coordinator = UserTagsCloudSyncCoordinator { request in
            startedRequests.append(request)
            if request == firstRequest {
                await firstRequestGate.suspend()
            }
            completedRequests.append(request)
        }

        coordinator.enqueue(firstRequest)
        await firstRequestGate.waitUntilSuspended()
        coordinator.enqueue(secondRequest)

        #expect(startedRequests == [firstRequest])
        #expect(completedRequests.isEmpty)

        await firstRequestGate.resume()
        await coordinator.waitForPendingWork()

        #expect(startedRequests == [firstRequest, secondRequest])
        #expect(completedRequests == [firstRequest, secondRequest])
    }
}

private actor UserTagsCloudSyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isSuspended = false

    func suspend() async {
        isSuspended = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
