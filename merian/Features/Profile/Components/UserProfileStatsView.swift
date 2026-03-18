import SwiftUI
import SwiftData

struct UserProfileStatsView: View {
    @Query private var allRecords: [LocalScanRecord]
    
    @State private var computedSpeciesCount: Int = 0
    @State private var computedStreak: Int = 0
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCardView(title: "Species", value: "\(computedSpeciesCount)", icon: "leaf.fill", color: .green)
            StatCardView(title: "Current streak", value: "\(computedStreak) Day\(computedStreak == 1 ? "" : "s")", icon: "flame.fill", color: .orange)
        }
        .task(id: allRecords.count) {
            await recalculateStats()
        }
    }
    
    private func recalculateStats() async {
        // Securely map properties into Sendable matrices to prevent SwiftData Thread violations natively
        struct ProfileStatPayload: Sendable {
            let scientificName: String
            let timestamp: Date
        }
        
        let payloads = allRecords.map { ProfileStatPayload(scientificName: $0.scientificName, timestamp: $0.timestamp) }
        
        let results = await Task.detached(priority: .userInitiated) { () -> (Int, Int) in
            let speciesCount = Set(payloads.map { $0.scientificName }).count
            
            let calendar = Calendar.current
            let sortedDates = Array(Set(payloads.map { calendar.startOfDay(for: $0.timestamp) })).sorted(by: >)
            
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
        }.value
        
        await MainActor.run {
            self.computedSpeciesCount = results.0
            self.computedStreak = results.1
        }
    }
}
