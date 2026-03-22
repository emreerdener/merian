import SwiftUI
import SwiftData

// MARK: - Gamification Database Engine
extension ProfileDatabaseActor {
    func calculateAwards() -> [AwardPayload] {
        var descriptor = FetchDescriptor<LocalScanRecord>()
        // CRITICAL SEC FIX: Severely drop V8/JetSam memory expansion bounds manually limit columns
        descriptor.propertiesToFetch = [
            \.scientificName, \.taxonomyKingdom, \.taxonomyClass, \.ecologyType,
            \.weatherTemperatureF, \.gpsElevation, \.timestamp, \.isInvasive,
            \.iucnRedListStatus, \.isPoisonous, \.confidenceScore
        ]
        
        guard let allRecords = try? modelContext.fetch(descriptor) else { return [] }
        
        var fungiSpecies = Set<String>()
        var plantsSpecies = Set<String>()
        var insectsSpecies = Set<String>()
        var urbanSpecies = Set<String>()
        var frostWalkerSpecies = Set<String>()
        var alpineSpecies = Set<String>()
        var nocturnalSpecies = Set<String>()
        var invasiveSpecies = Set<String>()
        var conservationSpecies = Set<String>()
        var poisonousSpecies = Set<String>()
        var perfectLensSpecies = Set<String>()
        var allSpecies = Set<String>()
        
        for record in allRecords {
            let name = record.scientificName
            allSpecies.insert(name)
            
            if let kingdom = record.taxonomyKingdom?.lowercased() {
                if kingdom == "fungi" { fungiSpecies.insert(name) }
                else if kingdom == "plantae" { plantsSpecies.insert(name) }
            }
            if let className = record.taxonomyClass?.lowercased() {
                if className == "insecta" || className == "arachnida" { insectsSpecies.insert(name) }
            }
            let ecology = record.ecologyType.lowercased()
            if ecology == "urban" || ecology == "domesticated" { urbanSpecies.insert(name) }
            
            if let temp = record.weatherTemperatureF, temp < 32.0 { frostWalkerSpecies.insert(name) }
            if let elevation = record.gpsElevation, elevation > 2500.0 { alpineSpecies.insert(name) }
            
            let hour = Calendar.current.component(.hour, from: record.timestamp)
            if hour >= 22 || hour <= 5 { nocturnalSpecies.insert(name) }
            if record.isInvasive { invasiveSpecies.insert(name) }
            if let status = record.iucnRedListStatus, !status.isEmpty, status != "LC", status != "NE", status != "DD" { conservationSpecies.insert(name) }
            if record.isPoisonous { poisonousSpecies.insert(name) }
            if let score = record.confidenceScore, score >= 0.98 { perfectLensSpecies.insert(name) }
        }
        
        let firstScanCount = allRecords.isEmpty ? 0 : 1
        let speciesCount = allSpecies.count
        
        return [
            AwardPayload(title: "The Observer", type: "first_scan", currentCount: firstScanCount, targetCount: 1),
            AwardPayload(title: "The Naturalist", type: "explorer", currentCount: speciesCount, targetCount: 5),
            AwardPayload(title: "The Botanist", type: "plantae", currentCount: plantsSpecies.count, targetCount: 10),
            AwardPayload(title: "The Zoologist", type: "insecta", currentCount: insectsSpecies.count, targetCount: 10),
            AwardPayload(title: "The Mycologist", type: "fungi", currentCount: fungiSpecies.count, targetCount: 10),
            AwardPayload(title: "The Urban Ecologist", type: "urban", currentCount: urbanSpecies.count, targetCount: 10),
            // Environmental & Impact Badges
            AwardPayload(title: "The Frost Walker", type: "frost_walker", currentCount: frostWalkerSpecies.count, targetCount: 5),
            AwardPayload(title: "The Alpine Naturalist", type: "alpine", currentCount: alpineSpecies.count, targetCount: 5),
            AwardPayload(title: "The Nocturnal Observer", type: "nocturnal", currentCount: nocturnalSpecies.count, targetCount: 10),
            AwardPayload(title: "The Guardian", type: "guardian", currentCount: invasiveSpecies.count, targetCount: 5),
            AwardPayload(title: "The Conservationist", type: "conservationist", currentCount: conservationSpecies.count, targetCount: 1),
            AwardPayload(title: "The Toxicologist", type: "toxicologist", currentCount: poisonousSpecies.count, targetCount: 5),
            AwardPayload(title: "The Perfect Lens", type: "perfect_lens", currentCount: perfectLensSpecies.count, targetCount: 25)
        ]
    }
}

// MARK: - Primary View
struct AwardsAndMilestones: View {
    let awards: [AwardPayload]
    @State private var sortOption: AwardSortOption = .smartSort
    
    private var sortedAwards: [AwardPayload] {
        switch sortOption {
        case .smartSort:
            return awards.sorted {
                if $0.isCompleted == $1.isCompleted {
                    if $0.progressFraction == $1.progressFraction {
                        // Secondary tie-breaker: mathematically organize identical 0% empty badges natively by difficulty
                        return $0.difficultyLevel < $1.difficultyLevel
                    }
                    // Primary tie-breaker places highest completion trajectory first
                    return $0.progressFraction > $1.progressFraction
                }
                return $0.isCompleted && !$1.isCompleted // Completed dynamically floated top
            }
        case .completedFirst:
            return awards.sorted {
                if $0.isCompleted == $1.isCompleted { return $0.difficultyLevel < $1.difficultyLevel }
                return $0.isCompleted && !$1.isCompleted
            }
        case .uncompletedFirst:
            return awards.sorted {
                if $0.isCompleted == $1.isCompleted { return $0.difficultyLevel < $1.difficultyLevel }
                return !$0.isCompleted && $1.isCompleted
            }
        case .easiestFirst:
            return awards.sorted {
                if $0.difficultyLevel == $1.difficultyLevel { return $0.isCompleted && !$1.isCompleted }
                return $0.difficultyLevel < $1.difficultyLevel
            }
        case .hardestFirst:
            return awards.sorted {
                if $0.difficultyLevel == $1.difficultyLevel { return $0.isCompleted && !$1.isCompleted }
                return $0.difficultyLevel > $1.difficultyLevel
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Text("Awards & milestones")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Menu {
                    ForEach(AwardSortOption.allCases) { option in
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                sortOption = option
                            }
                        }) {
                            Label(option.rawValue, systemImage: option.iconName)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.primary.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color(uiColor: .systemGray6))
                        )
                }
            }
            
            VStack(spacing: 12) {
                ForEach(sortedAwards) { award in
                    AwardCard(award: award)
                }
            }
        }
    }
}
