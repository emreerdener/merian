import Foundation

@MainActor
protocol MilestoneToastSessionControlling: AnyObject {
    func beginAccountSession(
        accountID: String?,
        origin: AppRouteAccountSessionOrigin,
        now: Date
    )

    func advanceSession(now: Date)
}
