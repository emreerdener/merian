import Observation
import SwiftData

@MainActor
@Observable
final class UserTagsViewModel {
    private(set) var errorMessage: String?

    @ObservationIgnored private let dependencies: UserTagsDependencies

    init(dependencies: UserTagsDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func addTag(
        _ candidate: String,
        to record: LocalScanRecord,
        modelContext: ModelContext
    ) {
        switch UserTagValidation.additionDecision(
            for: candidate,
            existingTags: record.customTags
        ) {
        case .unchanged:
            errorMessage = nil
        case .rejected:
            errorMessage = Self.addErrorMessage
        case .add(let tag):
            let previousTags = record.customTags
            record.customTags.append(tag)
            commit(
                record: record,
                modelContext: modelContext,
                logContext: "add custom tag",
                failureMessage: Self.addErrorMessage,
                previousTags: previousTags
            )
        }
    }

    func removeTag(
        _ tag: String,
        from record: LocalScanRecord,
        modelContext: ModelContext
    ) {
        guard record.customTags.contains(tag) else {
            errorMessage = nil
            return
        }
        let previousTags = record.customTags
        record.customTags.removeAll { $0 == tag }
        commit(
            record: record,
            modelContext: modelContext,
            logContext: "remove custom tag",
            failureMessage: "Tag changes could not be saved.",
            previousTags: previousTags
        )
    }

    private func commit(
        record: LocalScanRecord,
        modelContext: ModelContext,
        logContext: String,
        failureMessage: String,
        previousTags: [String]
    ) {
        guard dependencies.persistMutation(modelContext, logContext) else {
            record.customTags = previousTags
            errorMessage = failureMessage
            return
        }

        errorMessage = nil
        dependencies.syncToCloud(record.id, record.customTags)
        dependencies.publishSearchInvalidation(record.id)
    }

    private static let addErrorMessage =
        "Tags are limited to 50 labels and 64 characters each."
}
