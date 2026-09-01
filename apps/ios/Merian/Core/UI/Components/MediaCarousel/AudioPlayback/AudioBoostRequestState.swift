import Foundation

enum AudioBoostFeedbackPolicy {
    static func shouldPresent(actionToken: UUID?) -> Bool {
        actionToken != nil
    }
}

struct AudioBoostRequestState: Equatable {
    private(set) var generation: UInt64 = 0
    private(set) var activeRequestID: UInt64?
    private(set) var isPreparing = false
    private(set) var isReverting = false
    private(set) var showsPreparationStatus = false

    mutating func begin(
        isBoostEnabled: Bool,
        shouldShowReverting: Bool,
        showsPreparationStatus: Bool
    ) -> UInt64 {
        generation &+= 1
        activeRequestID = generation
        isPreparing = isBoostEnabled
        isReverting = !isBoostEnabled && shouldShowReverting
        self.showsPreparationStatus = isBoostEnabled
            && showsPreparationStatus
        return generation
    }

    func owns(_ requestID: UInt64) -> Bool {
        activeRequestID == requestID
    }

    @discardableResult
    mutating func finish(_ requestID: UInt64) -> Bool {
        guard owns(requestID) else { return false }
        activeRequestID = nil
        isPreparing = false
        isReverting = false
        showsPreparationStatus = false
        return true
    }

    mutating func invalidate() {
        generation &+= 1
        activeRequestID = nil
        isPreparing = false
        isReverting = false
        showsPreparationStatus = false
    }
}
