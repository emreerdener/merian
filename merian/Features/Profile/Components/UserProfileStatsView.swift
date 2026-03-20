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
