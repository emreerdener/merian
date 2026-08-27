import SwiftData

@ModelActor
actor SearchDatabaseActor {
    private static func buildSearchString(
        commonName: String,
        scientificName: String,
        petLabel: String?,
        ecologyType: String,
        semanticTags: [String],
        customTags: [String],
        isInvasive: Bool,
        taxonomyClass: String?,
        taxonomyOrder: String?,
        taxonomyFamily: String?,
        aiReasoning: String?,
        locationName: String?,
        habitatDescription: String?,
        weatherCondition: String?,
        lifeStage: String?,
        reproductiveCondition: String?,
        sex: String?,
        sexEvidence: String?,
        similarSpecies: [String]?,
        iucnRedListStatus: String?,
        hazardType: String,
        ecologicalInteractions: [String]?
    ) -> String {
        let tags = semanticTags.joined(separator: " ")
        let petLabel = petLabel ?? ""
        let taxonomyTerms = [taxonomyClass, taxonomyOrder, taxonomyFamily]
            .compactMap { $0 }
            .joined(separator: " ")
        let groupName = commonGroupName(for: taxonomyClass)
        let hazard = hazardType == "none" ? "" : hazardType

        return "\(commonName) \(scientificName) \(petLabel) \(ecologyType) \(tags) \(customTags.joined(separator: " ")) \(isInvasive ? "invasive" : "") \(taxonomyTerms) \(groupName) \(aiReasoning ?? "") \(locationName ?? "") \(habitatDescription ?? "") \(weatherCondition ?? "") \(lifeStage ?? "") \(reproductiveCondition ?? "") \(sex ?? "") \(sexEvidence ?? "") \(similarSpecies?.joined(separator: " ") ?? "") \(iucnRedListStatus ?? "") \(hazard) \(ecologicalInteractions?.joined(separator: " ") ?? "")".lowercased()
    }

    /// Builds payloads from values already extracted on the SwiftData owner.
    static func buildSearchablePayloads(from snapshots: [RawScanSnapshot]) -> [SearchableScan] {
        var processed: [SearchableScan] = []
        processed.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            if Task.isCancelled { break }
            processed.append(SearchableScan(
                id: snapshot.id,
                searchString: Self.buildSearchString(
                    commonName: snapshot.commonName,
                    scientificName: snapshot.scientificName,
                    petLabel: snapshot.petLabel,
                    ecologyType: snapshot.ecologyType,
                    semanticTags: snapshot.semanticTags,
                    customTags: snapshot.customTags,
                    isInvasive: snapshot.isInvasive,
                    taxonomyClass: snapshot.taxonomyClass,
                    taxonomyOrder: snapshot.taxonomyOrder,
                    taxonomyFamily: snapshot.taxonomyFamily,
                    aiReasoning: snapshot.aiReasoning,
                    locationName: snapshot.locationName,
                    habitatDescription: snapshot.habitatDescription,
                    weatherCondition: snapshot.weatherCondition,
                    lifeStage: snapshot.lifeStage,
                    reproductiveCondition: snapshot.reproductiveCondition,
                    sex: snapshot.sex,
                    sexEvidence: snapshot.sexEvidence,
                    similarSpecies: snapshot.similarSpecies,
                    iucnRedListStatus: snapshot.iucnRedListStatus,
                    hazardType: snapshot.hazardType,
                    ecologicalInteractions: snapshot.ecologicalInteractions
                ),
                ecologyType: snapshot.ecologyType.lowercased(),
                kingdom: snapshot.taxonomyKingdom?.lowercased() ?? "",
                className: snapshot.taxonomyClass?.lowercased() ?? ""
            ))
        }
        return processed
    }

    /// Fetches a delta in one query and maps it into the detached search representation.
    func extractSearchablePayloads(from ids: [String]) -> [SearchableScan] {
        guard !ids.isEmpty else { return [] }

        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        descriptor.fetchLimit = ids.count

        let records = (try? modelContext.fetch(descriptor)) ?? []
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var processed: [SearchableScan] = []
        processed.reserveCapacity(ids.count)

        for id in ids {
            if Task.isCancelled { break }
            guard let record = recordMap[id] else { continue }

            processed.append(SearchableScan(
                id: record.id,
                searchString: Self.buildSearchString(
                    commonName: record.commonName,
                    scientificName: record.scientificName,
                    petLabel: record.petIdentification?.label,
                    ecologyType: record.ecologyType,
                    semanticTags: record.semanticTags,
                    customTags: record.customTags,
                    isInvasive: record.isInvasive,
                    taxonomyClass: record.taxonomyClass,
                    taxonomyOrder: record.taxonomyOrder,
                    taxonomyFamily: record.taxonomyFamily,
                    aiReasoning: record.aiReasoning,
                    locationName: record.locationName,
                    habitatDescription: record.habitatDescription,
                    weatherCondition: record.weatherCondition,
                    lifeStage: record.lifeStage,
                    reproductiveCondition: record.reproductiveCondition,
                    sex: record.sex,
                    sexEvidence: record.sexEvidence,
                    similarSpecies: record.similarSpecies,
                    iucnRedListStatus: record.iucnRedListStatus,
                    hazardType: record.hazardType,
                    ecologicalInteractions: record.ecologicalInteractions
                ),
                ecologyType: record.ecologyType.lowercased(),
                kingdom: record.taxonomyKingdom?.lowercased() ?? "",
                className: record.taxonomyClass?.lowercased() ?? ""
            ))
        }

        return processed
    }

    static func commonGroupName(for taxonomyClass: String?) -> String {
        switch taxonomyClass?.lowercased() {
        case "aves":
            "bird birds avian"
        case "mammalia":
            "mammal mammals"
        case "insecta", "entognatha":
            "insect insects bug bugs"
        case "arachnida":
            "spider spiders arachnid arachnids"
        case "reptilia", "squamata":
            "reptile reptiles"
        case "amphibia":
            "amphibian amphibians frog frogs toad toads"
        case "actinopterygii", "chondrichthyes", "sarcopterygii":
            "fish"
        default:
            ""
        }
    }
}

actor SearchFilterActor {
    func filter(
        text: String,
        searchIndex: SearchIndexSnapshot,
        catMatch: String
    ) -> [String] {
        let tokens = SearchIndexTokenizer.queryTokens(from: text)
        let categoryMatches = searchIndex.ids(matching: catMatch)

        if tokens.isEmpty {
            return Task.isCancelled ? [] : categoryMatches
        }

        let categorySet = catMatch == "all" ? nil : Set(categoryMatches)
        var candidateSet: Set<String>?

        for token in tokens {
            if Task.isCancelled { return [] }

            var tokenMatches = Set(searchIndex.candidateIDs(matching: token))
            guard !tokenMatches.isEmpty else { return [] }

            if let categorySet {
                tokenMatches.formIntersection(categorySet)
                guard !tokenMatches.isEmpty else { return [] }
            }

            if let existingCandidateSet = candidateSet {
                let narrowed = existingCandidateSet.intersection(tokenMatches)
                guard !narrowed.isEmpty else { return [] }
                candidateSet = narrowed
            } else {
                candidateSet = tokenMatches
            }
        }

        guard let candidateSet, !Task.isCancelled else { return [] }

        return candidateSet.filter { id in
            guard let scan = searchIndex.documentsById[id] else { return false }
            return tokens.allSatisfy { scan.searchString.contains($0) }
        }
    }
}
