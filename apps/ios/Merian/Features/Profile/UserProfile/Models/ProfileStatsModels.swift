import Foundation

struct HeatmapDay: Sendable, Identifiable {
    let id = UUID()
    let count: Int
    let date: Date
}

struct HeatmapWeek: Sendable, Identifiable {
    let id = UUID()
    let days: [HeatmapDay]
    let monthLabel: String?
}

struct ProfileHeatmapData: Sendable {
    let totalCaptures: Int
    let currentMonthCaptures: Int
    let yearString: String
    let weeks: [HeatmapWeek]
}

struct ProfileAllStatsPayload: Sendable {
    let speciesCount: Int
    let streak: Int
    let heatmap: ProfileHeatmapData
    let awards: [AwardPayload]
}
