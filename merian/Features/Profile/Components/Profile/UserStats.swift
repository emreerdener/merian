import SwiftUI
import SwiftData

/// The fundamental anchor of the Offline-First Architecture. 
/// This completely isolates millions of SQLite computations physically off the UI thread 
/// guaranteeing flawless iOS 120Hz native Scroll geometries.
@ModelActor
actor ProfileDatabaseActor {
    func calculateProfileStats() -> (speciesCount: Int, streak: Int) {
        var descriptor = FetchDescriptor<LocalScanRecord>()
        // CRITICAL SEC FIX: Severely drop V8/JetSam memory expansion bounds manually limiting the 
        // fetch columns exactly to strictly required Strings and Dates. (Massive photo hashes ignored!)
        descriptor.propertiesToFetch = [\.scientificName, \.timestamp]
        
        guard let allRecords = try? modelContext.fetch(descriptor) else { return (0, 0) }
        
        let speciesCount = Set(allRecords.map { $0.scientificName }).count
        
        let calendar = Calendar.current
        let sortedDates = Array(Set(allRecords.map { calendar.startOfDay(for: $0.timestamp) })).sorted(by: >)
        
        var streak = 0
        let today = calendar.startOfDay(for: Date())
        var expectedDate = today
        
        if !sortedDates.contains(today) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), sortedDates.contains(yesterday) {
                expectedDate = yesterday
            } else {
                return (speciesCount, 0)
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
        
        return (speciesCount, streak)
    }
    
    func calculateAll() -> (speciesCount: Int, streak: Int, heatmap: ProfileHeatmapData, awards: [AwardPayload]) {
        var descriptor = FetchDescriptor<LocalScanRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.propertiesToFetch = [
            \.scientificName, \.taxonomyKingdom, \.taxonomyClass, \.ecologyType,
            \.weatherTemperatureF, \.gpsElevation, \.timestamp, \.isInvasive,
            \.iucnRedListStatus, \.isPoisonous, \.confidenceScore
        ]
        guard let allRecords = try? modelContext.fetch(descriptor) else {
            return (0, 0, ProfileHeatmapData(totalCaptures: 0, currentMonthCaptures: 0, yearString: "", weeks: []), [])
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        // Species count
        let speciesCount = Set(allRecords.map { $0.scientificName }).count

        // Streak
        let sortedDates = Array(Set(allRecords.map { calendar.startOfDay(for: $0.timestamp) })).sorted(by: >)
        var streak = 0
        var expectedDate = today
        streakCalc: do {
            if !sortedDates.contains(today) {
                guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      sortedDates.contains(yesterday) else { break streakCalc }
                expectedDate = yesterday
            }
            for date in sortedDates {
                if calendar.isDate(date, inSameDayAs: expectedDate) {
                    streak += 1
                    expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
                } else { break }
            }
        }

        // Heatmap
        var counts: [Date: Int] = [:]
        for record in allRecords {
            counts[calendar.startOfDay(for: record.timestamp), default: 0] += 1
        }
        let currentYear = calendar.component(.year, from: today)
        let daysToSaturday = 7 - calendar.component(.weekday, from: today)
        let heatmap: ProfileHeatmapData
        if let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today),
           let startDate = calendar.date(byAdding: .day, value: -(52 * 7 - 1), to: endOfWeek) {
            var weeks: [HeatmapWeek] = []
            let df = DateFormatter()
            df.dateFormat = "MMM"
            var currentMonth = -1
            var totalInHeatmap = 0
            var currentMonthCaptures = 0
            var currentDate = startDate
            for _ in 0..<52 {
                var days: [HeatmapDay] = []
                var monthLabel: String? = nil
                for dayIndex in 0..<7 {
                    if dayIndex == 0 {
                        let month = calendar.component(.month, from: currentDate)
                        if month != currentMonth {
                            currentMonth = month
                            monthLabel = df.string(from: currentDate)
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
            heatmap = ProfileHeatmapData(totalCaptures: totalInHeatmap, currentMonthCaptures: currentMonthCaptures, yearString: "\(currentYear)", weeks: weeks)
        } else {
            let total = counts.values.reduce(0, +)
            heatmap = ProfileHeatmapData(totalCaptures: total, currentMonthCaptures: 0, yearString: "\(currentYear)", weeks: [])
        }

        // Awards
        let awards = AchievementsCalculator.calculate(from: allRecords)

        return (speciesCount, streak, heatmap, awards)
    }

    func calculateHeatmapData() -> ProfileHeatmapData {
        var descriptor = FetchDescriptor<LocalScanRecord>()
        descriptor.propertiesToFetch = [\.timestamp]
        
        guard let allRecords = try? modelContext.fetch(descriptor) else { 
            return ProfileHeatmapData(totalCaptures: 0, currentMonthCaptures: 0, yearString: "", weeks: [])
        }
        
        let calendar = Calendar.current
        let now = Date()
        var counts: [Date: Int] = [:]
        
        for record in allRecords {
            let startOfDay = calendar.startOfDay(for: record.timestamp)
            counts[startOfDay, default: 0] += 1
        }
        
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: today)
        
        let weekday = calendar.component(.weekday, from: today)
        let daysToSaturday = 7 - weekday
        guard let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today) else {
            let total = counts.values.reduce(0, +)
            return ProfileHeatmapData(totalCaptures: total, currentMonthCaptures: 0, yearString: "\(currentYear)", weeks: [])
        }
        
        let columns = 52
        let totalDays = columns * 7
        guard let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: endOfWeek) else {
            let total = counts.values.reduce(0, +)
            return ProfileHeatmapData(totalCaptures: total, currentMonthCaptures: 0, yearString: "\(currentYear)", weeks: [])
        }
        
        var weeks: [HeatmapWeek] = []
        let df = DateFormatter()
        df.dateFormat = "MMM"
        
        var currentMonth = -1
        var totalInHeatmap = 0
        var currentMonthCaptures = 0
        
        var currentDate = startDate
        
        for _ in 0..<columns {
            var days: [HeatmapDay] = []
            var monthLabel: String? = nil
            
            for dayIndex in 0..<7 {
                if dayIndex == 0 {
                    let month = calendar.component(.month, from: currentDate)
                    if month != currentMonth {
                        currentMonth = month
                        monthLabel = df.string(from: currentDate)
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
        
        return ProfileHeatmapData(totalCaptures: totalInHeatmap, currentMonthCaptures: currentMonthCaptures, yearString: "\(currentYear)", weeks: weeks)
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



struct UserStats: View {
    let speciesCount: Int
    let streak: Int
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "Species discovered", value: "\(speciesCount)", icon: "leaf.fill", color: .green)
            StatCard(title: "Current streak", value: "\(streak) day\(streak == 1 ? "" : "s")", icon: "flame.fill", color: .orange)
        }
    }
}
