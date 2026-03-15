import SwiftUI
import SwiftData

struct UserProfileStatsView: View {
    @Query private var allRecords: [LocalScanRecord]
    
    private var uniqueSpeciesCount: Int {
        Set(allRecords.map { $0.scientificName }).count
    }
    
    private var currentStreak: Int {
        let calendar = Calendar.current
        let sortedDates = Array(Set(allRecords.map { calendar.startOfDay(for: $0.timestamp) })).sorted(by: >)
        
        var streak = 0
        let today = calendar.startOfDay(for: Date())
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
    
    private var rareFindsCount: Int {
        allRecords.filter { $0.ecologyType.lowercased() == "wild" && $0.isBiological }.count
    }
    
    private var persona: String {
        let count = uniqueSpeciesCount
        if count == 0 { return "Observer" }
        else if count < 10 { return "Novice Botanist" }
        else if count < 50 { return "Field Explorer" }
        else if count < 100 { return "Avid Naturalist" }
        else { return "Master Biologist" }
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCardView(title: "Species", value: "\(uniqueSpeciesCount)", icon: "leaf.fill", color: .green)
            StatCardView(title: "Current Streak", value: "\(currentStreak) Day\(currentStreak == 1 ? "" : "s")", icon: "flame.fill", color: .orange)
            StatCardView(title: "Rare Finds", value: "\(rareFindsCount)", icon: "sparkles", color: .purple)
            StatCardView(title: "Explorer Rank", value: persona, icon: "tree.fill", color: .teal)
        }
    }
}
