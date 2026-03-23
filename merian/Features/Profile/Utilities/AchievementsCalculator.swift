import Foundation

struct AchievementsCalculator {
    static func calculate(from allRecords: [LocalScanRecord]) -> [AwardPayload] {
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
