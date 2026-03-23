import SwiftUI
import SwiftData

// MARK: - Gamification Database Engine
extension ProfileDatabaseActor {
    func calculateAwards() -> [AwardPayload] {
        var descriptor = FetchDescriptor<LocalScanRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        // CRITICAL SEC FIX: Severely drop V8/JetSam memory expansion bounds manually limit columns
        descriptor.propertiesToFetch = [
            \.scientificName, \.taxonomyKingdom, \.taxonomyClass, \.ecologyType,
            \.weatherTemperatureF, \.gpsElevation, \.timestamp, \.isInvasive,
            \.iucnRedListStatus, \.isPoisonous, \.confidenceScore
        ]
        
        guard let allRecords = try? modelContext.fetch(descriptor) else { return [] }
        
        var fungiSpecies = Set<String>(); var fungiDate: Date?
        var plantsSpecies = Set<String>(); var plantsDate: Date?
        var insectsSpecies = Set<String>(); var insectsDate: Date?
        var urbanSpecies = Set<String>(); var urbanDate: Date?
        var frostWalkerSpecies = Set<String>(); var frostDate: Date?
        var alpineSpecies = Set<String>(); var alpineDate: Date?
        var nocturnalSpecies = Set<String>(); var nocturnalDate: Date?
        var invasiveSpecies = Set<String>(); var invasiveDate: Date?
        var conservationSpecies = Set<String>(); var conservationDate: Date?
        var poisonousSpecies = Set<String>(); var poisonousDate: Date?
        var perfectLensSpecies = Set<String>(); var perfectLensDate: Date?
        var allSpecies = Set<String>(); var explorerDate: Date?
        let firstScanDate: Date? = allRecords.first?.timestamp
        
        for record in allRecords {
            let name = record.scientificName
            let timestamp = record.timestamp
            
            if !allSpecies.contains(name) {
                allSpecies.insert(name)
                explorerDate = explorerDate ?? timestamp
            }
            
            if let kingdom = record.taxonomyKingdom?.lowercased() {
                if kingdom == "fungi" && !fungiSpecies.contains(name) { 
                    fungiSpecies.insert(name); fungiDate = fungiDate ?? timestamp 
                } else if kingdom == "plantae" && !plantsSpecies.contains(name) { 
                    plantsSpecies.insert(name); plantsDate = plantsDate ?? timestamp 
                }
            }
            if let className = record.taxonomyClass?.lowercased() {
                if (className == "insecta" || className == "arachnida") && !insectsSpecies.contains(name) { 
                    insectsSpecies.insert(name); insectsDate = insectsDate ?? timestamp 
                }
            }
            let ecology = record.ecologyType.lowercased()
            if (ecology == "urban" || ecology == "domesticated") && !urbanSpecies.contains(name) { 
                urbanSpecies.insert(name); urbanDate = urbanDate ?? timestamp 
            }
            
            if let temp = record.weatherTemperatureF, temp < 32.0, !frostWalkerSpecies.contains(name) { 
                frostWalkerSpecies.insert(name); frostDate = frostDate ?? timestamp 
            }
            if let elevation = record.gpsElevation, elevation > 2500.0, !alpineSpecies.contains(name) { 
                alpineSpecies.insert(name); alpineDate = alpineDate ?? timestamp 
            }
            
            let hour = Calendar.current.component(.hour, from: timestamp)
            if (hour >= 22 || hour <= 5) && !nocturnalSpecies.contains(name) { 
                nocturnalSpecies.insert(name); nocturnalDate = nocturnalDate ?? timestamp 
            }
            if record.isInvasive && !invasiveSpecies.contains(name) { 
                invasiveSpecies.insert(name); invasiveDate = invasiveDate ?? timestamp 
            }
            if let status = record.iucnRedListStatus, !status.isEmpty, status != "LC", status != "NE", status != "DD", !conservationSpecies.contains(name) { 
                conservationSpecies.insert(name); conservationDate = conservationDate ?? timestamp 
            }
            if record.isPoisonous && !poisonousSpecies.contains(name) { 
                poisonousSpecies.insert(name); poisonousDate = poisonousDate ?? timestamp 
            }
            if let score = record.confidenceScore, score >= 0.98, !perfectLensSpecies.contains(name) { 
                perfectLensSpecies.insert(name); perfectLensDate = perfectLensDate ?? timestamp 
            }
        }
        
        let firstScanCount = allRecords.isEmpty ? 0 : 1
        
        return [
            AwardPayload(title: "The Observer", type: "first_scan", currentCount: firstScanCount, targetCount: 1, lastInteractionDate: firstScanDate),
            AwardPayload(title: "The Naturalist", type: "explorer", currentCount: allSpecies.count, targetCount: 5, lastInteractionDate: explorerDate),
            AwardPayload(title: "The Botanist", type: "plantae", currentCount: plantsSpecies.count, targetCount: 10, lastInteractionDate: plantsDate),
            AwardPayload(title: "The Zoologist", type: "insecta", currentCount: insectsSpecies.count, targetCount: 10, lastInteractionDate: insectsDate),
            AwardPayload(title: "The Mycologist", type: "fungi", currentCount: fungiSpecies.count, targetCount: 10, lastInteractionDate: fungiDate),
            AwardPayload(title: "The Urban Ecologist", type: "urban", currentCount: urbanSpecies.count, targetCount: 10, lastInteractionDate: urbanDate),
            // Environmental & Impact Badges
            AwardPayload(title: "The Frost Walker", type: "frost_walker", currentCount: frostWalkerSpecies.count, targetCount: 5, lastInteractionDate: frostDate),
            AwardPayload(title: "The Alpine Naturalist", type: "alpine", currentCount: alpineSpecies.count, targetCount: 5, lastInteractionDate: alpineDate),
            AwardPayload(title: "The Nocturnal Observer", type: "nocturnal", currentCount: nocturnalSpecies.count, targetCount: 10, lastInteractionDate: nocturnalDate),
            AwardPayload(title: "The Guardian", type: "guardian", currentCount: invasiveSpecies.count, targetCount: 5, lastInteractionDate: invasiveDate),
            AwardPayload(title: "The Conservationist", type: "conservationist", currentCount: conservationSpecies.count, targetCount: 1, lastInteractionDate: conservationDate),
            AwardPayload(title: "The Toxicologist", type: "toxicologist", currentCount: poisonousSpecies.count, targetCount: 5, lastInteractionDate: poisonousDate),
            AwardPayload(title: "The Perfect Lens", type: "perfect_lens", currentCount: perfectLensSpecies.count, targetCount: 25, lastInteractionDate: perfectLensDate)
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
            return awards.sorted { a, b in
                // Heuristic priority scoring:
                // >= 3.0: Freshly Completed (Within last 7 days)
                // 2.01 - 2.99: In Progress (Mathematically scales by closeness to completion)
                // 1.0: Legacy Completed (Older than 7 days)
                // 0.0: Conceptually empty (0%)
                func smartScore(for award: AwardPayload) -> Double {
                    if award.isCompleted {
                        if let date = award.lastInteractionDate, Date().timeIntervalSince(date) < 86400 * 7 {
                            return 3.0 // Hero status! Recently accomplished!
                        }
                        return 1.0 // Sink legacy accomplishments below active goals
                    }
                    if award.progressFraction > 0 {
                        return 2.0 + award.progressFraction // Organical float "close to being done" (e.g. 2.9) to the top of the In-Progress pile!
                    }
                    return 0.0 // Empty goals sink completely to the bottom
                }
                
                let scoreA = smartScore(for: a)
                let scoreB = smartScore(for: b)
                
                // If mathematically tied across the exact same heuristic tier boundaries...
                if abs(scoreA - scoreB) < 0.001 {
                    // Tie-breaker 1: Explicitly float the most recently interacted award logically!
                    if let dateA = a.lastInteractionDate, let dateB = b.lastInteractionDate {
                        return dateA > dateB
                    }
                    if a.lastInteractionDate != nil { return true }
                    if b.lastInteractionDate != nil { return false }
                    
                    // Tie-breaker 2: Fallback to difficulty geometry mapping (Green -> Amber -> Crimson)
                    return a.difficultyLevel < b.difficultyLevel
                }
                // Primary evaluator: float highest priority scores dynamically!
                return scoreA > scoreB
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.75))
                        .frame(width: 34, height: 34)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial) // Liquid Glass frost
                        }
                        .overlay {
                            Circle()
                                // Inner specular glow replicating premium iOS reflections
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }
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
