import SwiftData
import SwiftUI

/// The fundamental anchor of the Offline-First Architecture. 
/// This completely isolates millions of SQLite computations physically off the UI thread 
/// guaranteeing flawless iOS 120Hz native Scroll geometries.
@ModelActor
actor ProfileDatabaseActor {
    private struct ProfileAnalyticsProjection: AchievementRecordRepresentable {
        let scientificName: String
        let taxonomyKingdom: String?
        let taxonomyClass: String?
        let ecologyType: String
        let weatherTemperatureF: Double?
        let gpsElevation: Double?
        let timestamp: Date
        let isInvasive: Bool
        let iucnRedListStatus: String?
        let hazardType: String
        let confidenceScore: Double?
    }

    private func fetchAnalyticsProjection() -> [ProfileAnalyticsProjection] {
        var descriptor = FetchDescriptor<LocalScanRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.propertiesToFetch = [
            \.scientificName, \.taxonomyKingdom, \.taxonomyClass, \.ecologyType,
            \.weatherTemperatureF, \.gpsElevation, \.timestamp, \.isInvasive,
            \.iucnRedListStatus, \.hazardType, \.confidenceScore
        ]

        guard let records = try? modelContext.fetch(descriptor) else { return [] }
        return records.map {
            ProfileAnalyticsProjection(
                scientificName: $0.scientificName,
                taxonomyKingdom: $0.taxonomyKingdom,
                taxonomyClass: $0.taxonomyClass,
                ecologyType: $0.ecologyType,
                weatherTemperatureF: $0.weatherTemperatureF,
                gpsElevation: $0.gpsElevation,
                timestamp: $0.timestamp,
                isInvasive: $0.isInvasive,
                iucnRedListStatus: $0.iucnRedListStatus,
                hazardType: $0.hazardType,
                confidenceScore: $0.confidenceScore
            )
        }
    }

    private func calculateStreak(from timestamps: [Date], now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let sortedDates = Array(Set(timestamps.map { calendar.startOfDay(for: $0) })).sorted(by: >)

        var streak = 0
        var expectedDate = today
        if !sortedDates.contains(today) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), sortedDates.contains(yesterday) {
                expectedDate = yesterday
            } else {
                return 0
            }
        }

        for date in sortedDates {
            if calendar.isDate(date, inSameDayAs: expectedDate) {
                streak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
            } else {
                break
            }
        }

        return streak
    }

    private func buildHeatmapData(from timestamps: [Date], now: Date = Date()) -> ProfileHeatmapData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var counts: [Date: Int] = [:]

        for timestamp in timestamps {
            counts[calendar.startOfDay(for: timestamp), default: 0] += 1
        }

        let currentYear = calendar.component(.year, from: today)
        let weekday = calendar.component(.weekday, from: today)
        let daysToSaturday = 7 - weekday
        guard let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today) else {
            let total = counts.values.reduce(0, +)
            return ProfileHeatmapData(totalCaptures: total, currentMonthCaptures: 0, yearString: "\(currentYear)", weeks: [])
        }

        let daysInWeek = 7
        let weeksInYear = 52
        let totalDays = weeksInYear * daysInWeek
        guard let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: endOfWeek) else {
            let total = counts.values.reduce(0, +)
            return ProfileHeatmapData(totalCaptures: total, currentMonthCaptures: 0, yearString: "\(currentYear)", weeks: [])
        }

        var weeks: [HeatmapWeek] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var currentMonth = -1
        var totalInHeatmap = 0
        var currentMonthCaptures = 0
        var currentDate = startDate

        for _ in 0..<weeksInYear {
            var days: [HeatmapDay] = []
            var monthLabel: String?

            for dayIndex in 0..<daysInWeek {
                if dayIndex == 0 {
                    let month = calendar.component(.month, from: currentDate)
                    if month != currentMonth {
                        currentMonth = month
                        monthLabel = formatter.string(from: currentDate)
                    }
                }

                let count: Int
                if currentDate > today {
                    count = -1
                } else {
                    count = counts[currentDate] ?? 0
                    totalInHeatmap += count
                    if calendar.isDate(currentDate, equalTo: now, toGranularity: .month) {
                        currentMonthCaptures += count
                    }
                }

                days.append(HeatmapDay(count: count, date: currentDate))
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }

            weeks.append(HeatmapWeek(days: days, monthLabel: monthLabel))
        }

        return ProfileHeatmapData(
            totalCaptures: totalInHeatmap,
            currentMonthCaptures: currentMonthCaptures,
            yearString: "\(currentYear)",
            weeks: weeks
        )
    }

    func calculateProfileStats() -> (speciesCount: Int, streak: Int) {
        var descriptor = FetchDescriptor<LocalScanRecord>()
        // CRITICAL SEC FIX: Severely drop V8/JetSam memory expansion bounds manually limiting the 
        // fetch columns exactly to strictly required Strings and Dates. (Massive photo hashes ignored!)
        descriptor.propertiesToFetch = [\.scientificName, \.timestamp]
        
        guard let allRecords = try? modelContext.fetch(descriptor) else { return (0, 0) }
        
        let speciesCount = Set(allRecords.map { $0.scientificName }).count
        let streak = calculateStreak(from: allRecords.map(\.timestamp))
        return (speciesCount, streak)
    }
    
    func calculateAll() -> ProfileAllStatsPayload {
        let allRecords = fetchAnalyticsProjection()
        guard !allRecords.isEmpty else {
            return ProfileAllStatsPayload(
                speciesCount: 0,
                streak: 0,
                heatmap: ProfileHeatmapData(totalCaptures: 0, currentMonthCaptures: 0, yearString: "", weeks: []),
                awards: []
            )
        }

        let now = Date()
        let speciesCount = Set(allRecords.map(\.scientificName)).count
        let streak = calculateStreak(from: allRecords.map(\.timestamp), now: now)
        let heatmap = buildHeatmapData(from: allRecords.map(\.timestamp), now: now)
        let awards = AchievementsCalculator.calculate(from: allRecords)

        return ProfileAllStatsPayload(
            speciesCount: speciesCount,
            streak: streak,
            heatmap: heatmap,
            awards: awards
        )
    }

    func calculateHeatmapData() -> ProfileHeatmapData {
        var descriptor = FetchDescriptor<LocalScanRecord>()
        descriptor.propertiesToFetch = [\.timestamp]
        
        guard let allRecords = try? modelContext.fetch(descriptor) else { 
            return ProfileHeatmapData(totalCaptures: 0, currentMonthCaptures: 0, yearString: "", weeks: [])
        }
        return buildHeatmapData(from: allRecords.map(\.timestamp))
    }

    func calculateAwardsProjection() -> [AwardPayload] {
        AchievementsCalculator.calculate(from: fetchAnalyticsProjection())
    }
    
}

// MARK: - Native Thread-Safe Architectures
// Explicit `Sendable` conformity fundamentally guarantees Apple's compiler instantly halts
// compilation if accidental memory-race conditions attempt to cross Thread boundaries.
public struct HeatmapDay: Sendable, Identifiable {
    public let id = UUID()
    public let count: Int
    public let date: Date
}

public struct HeatmapWeek: Sendable, Identifiable {
    public let id = UUID()
    public let days: [HeatmapDay]
    public let monthLabel: String?
}

public struct ProfileHeatmapData: Sendable {
    public let totalCaptures: Int
    public let currentMonthCaptures: Int
    public let yearString: String
    public let weeks: [HeatmapWeek]
}

public struct ProfileAllStatsPayload: Sendable {
    public let speciesCount: Int
    public let streak: Int
    public let heatmap: ProfileHeatmapData
    public let awards: [AwardPayload]
}

struct UserStats: View {
    let speciesCount: Int
    let streak: Int
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "Species discovered", value: "\(speciesCount)", imageName: "leaf", color: .green)
            StatCard(title: "Current streak", value: "\(streak) day\(streak == 1 ? "" : "s")", imageName: "fire", color: .orange)
        }
    }
}
