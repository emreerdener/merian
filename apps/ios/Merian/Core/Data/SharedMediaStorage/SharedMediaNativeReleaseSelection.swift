import Foundation

extension SharedMediaNativeReceivingReleaseValues.Progress {
    /// Descriptive ordered selection only. A saved progress value never grants
    /// admission, file access, or a metadata mutation.
    func selectedIndex(_ stage: SharedMediaNativeReceivingReleaseValues.TargetProgress.Stage) throws -> Int {
        try validate()
        guard stage != .removed,
              let index = targets.firstIndex(where: { $0.stage != .removed }),
              targets[index].stage == stage,
              targets.prefix(index).allSatisfy({ $0.stage == .removed }),
              targets.dropFirst(index + 1).allSatisfy({ $0.stage == .readyPair }) else {
            throw SharedMediaStorageFailure.closed
        }
        return index
    }
}
