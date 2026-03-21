import SwiftUI
import SwiftData

@ModelActor
actor ProfileDatabaseActor {
    func calculateProfileStats() -> (speciesCount: Int, streak: Int) {
        var descriptor = FetchDescriptor<LocalScanRecord>()
        // CRITICAL SEC FIX: Severely drop V8/JetSam memory expansion bounds manually limiting the fetch columns to strings and dates
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
    
    func calculateHeatmapData() -> ProfileHeatmapData {
        var descriptor = FetchDescriptor<LocalScanRecord>()
        descriptor.propertiesToFetch = [\.timestamp]
        
        guard let allRecords = try? modelContext.fetch(descriptor) else { 
            return ProfileHeatmapData(totalCaptures: 0, yearString: "", weeks: [])
        }
        
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        
        for record in allRecords {
            let startOfDay = calendar.startOfDay(for: record.timestamp)
            counts[startOfDay, default: 0] += 1
        }
        
        let today = calendar.startOfDay(for: Date())
        let currentYear = calendar.component(.year, from: today)
        
        // Find the most recent Saturday (end of the current week)
        // In Gregorian, Sunday is 1, Saturday is 7.
        let weekday = calendar.component(.weekday, from: today)
        let daysToSaturday = 7 - weekday
        guard let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today) else {
            return ProfileHeatmapData(totalCaptures: counts.values.reduce(0, +), yearString: "\(currentYear)", weeks: [])
        }
        
        let columns = 52
        let totalDays = columns * 7
        guard let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: endOfWeek) else {
            return ProfileHeatmapData(totalCaptures: counts.values.reduce(0, +), yearString: "\(currentYear)", weeks: [])
        }
        
        var weeks: [HeatmapWeek] = []
        let df = DateFormatter()
        df.dateFormat = "MMM"
        
        var currentMonth = -1
        var totalInHeatmap = 0
        
        for weekIndex in 0..<columns {
            var days: [HeatmapDay] = []
            var monthLabel: String? = nil
            
            for dayIndex in 0..<7 {
                guard let currentDate = calendar.date(byAdding: .day, value: (weekIndex * 7) + dayIndex, to: startDate) else { continue }
                
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
                }
                
                days.append(HeatmapDay(count: count, date: currentDate))
            }
            weeks.append(HeatmapWeek(days: days, monthLabel: monthLabel))
        }
        
        return ProfileHeatmapData(totalCaptures: totalInHeatmap, yearString: "\(currentYear)", weeks: weeks)
    }
}

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
    public let yearString: String
    public let weeks: [HeatmapWeek]
}

struct UserProfileStatsView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var computedSpeciesCount: Int = 0
    @State private var computedStreak: Int = 0
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], spacing: 16) {
            StatCardView(title: "Species discovered", value: "\(computedSpeciesCount)", icon: "leaf.fill", color: .green)
            StatCardView(title: "Current streak", value: "\(computedStreak) day\(computedStreak == 1 ? "" : "s")", icon: "flame.fill", color: .orange)
        }
        .task {
            let container = modelContext.container
            let actor = ProfileDatabaseActor(modelContainer: container)
            let (species, streak) = await actor.calculateProfileStats()
            
            await MainActor.run {
                self.computedSpeciesCount = species
                self.computedStreak = streak
            }
        }
    }
}
