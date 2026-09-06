import Foundation

enum ConsentRetryPolicy {
    static func requiredConsentRestorationDelay(attempt: Int) -> Double {
        let boundedExponent = min(max(attempt - 1, 0), 3)
        return min(5 * pow(2, Double(boundedExponent)), 30)
    }

    static func analyticsConsentDelay(attempt: Int) -> Double {
        let boundedExponent = min(max(attempt - 1, 0), 5)
        return min(pow(2, Double(boundedExponent)), 30)
    }

    static func isSynchronizationContextCurrent(
        expectedUserId: UUID,
        expectedGeneration: UInt,
        observedUserId: UUID?,
        sdkUserId: UUID?,
        currentGeneration: UInt,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && observedUserId == expectedUserId
            && sdkUserId == expectedUserId
            && currentGeneration == expectedGeneration
    }
}

extension ConsentManager {
    static func requiredConsentRestorationRetryDelay(attempt: Int) -> Double {
        ConsentRetryPolicy.requiredConsentRestorationDelay(attempt: attempt)
    }

    static func analyticsConsentRetryDelay(attempt: Int) -> Double {
        ConsentRetryPolicy.analyticsConsentDelay(attempt: attempt)
    }

    nonisolated static func isSynchronizationContextCurrent(
        expectedUserId: UUID,
        expectedGeneration: UInt,
        observedUserId: UUID?,
        sdkUserId: UUID?,
        currentGeneration: UInt,
        isCancelled: Bool
    ) -> Bool {
        ConsentRetryPolicy.isSynchronizationContextCurrent(
            expectedUserId: expectedUserId,
            expectedGeneration: expectedGeneration,
            observedUserId: observedUserId,
            sdkUserId: sdkUserId,
            currentGeneration: currentGeneration,
            isCancelled: isCancelled
        )
    }
}
