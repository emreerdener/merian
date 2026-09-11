import Foundation

protocol MilestoneToastClock: Sendable {
    func now() -> Date
    func sleep(for interval: TimeInterval) async throws
}

struct ContinuousMilestoneToastClock: MilestoneToastClock {
    func now() -> Date {
        Date()
    }

    func sleep(for interval: TimeInterval) async throws {
        let nanoseconds = UInt64(max(interval, 0) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
