import Foundation

@MainActor
protocol AppRouteRequesting: AnyObject {
    @discardableResult
    func request(
        _ route: AppRoute,
        source: AppRouteSource,
        id: UUID,
        now: Date
    ) -> UUID
}

extension AppRouteRequesting {
    @discardableResult
    func request(
        _ route: AppRoute,
        source: AppRouteSource
    ) -> UUID {
        request(route, source: source, id: UUID(), now: Date())
    }
}

@MainActor
protocol AppRouteConsuming: AnyObject {
    var nextRequestID: UUID? { get }
    func claimNext(now: Date) -> AppRouteEnvelope?
    func resolve(
        _ requestID: UUID,
        outcome: AppRouteOutcome,
        now: Date
    )
    func resumeDeferredRequest(_ requestID: UUID)
}

@MainActor
protocol AppRouteSessionControlling: AnyObject {
    var accountGeneration: UInt64 { get }
    func beginAccountSession(
        accountID: String?,
        origin: AppRouteAccountSessionOrigin,
        now: Date
    )
    func advanceSession(now: Date)
    func shouldSuppressTimeoutReset(now: Date) -> Bool
}

extension AppRouteSessionControlling {
    func beginAccountSession(accountID: String?, now: Date) {
        beginAccountSession(
            accountID: accountID,
            origin: .runtimeTransition,
            now: now
        )
    }
}
