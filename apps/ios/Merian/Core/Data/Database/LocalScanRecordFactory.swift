import Foundation

/// Maps one prepared inference result into the complete persisted scan model.
///
/// The factory is stateless. SwiftData insertion, replacement, and save
/// decisions remain isolated to `BackgroundDatabaseActor`.
enum LocalScanRecordFactory {
    static func makeRecord(
        from mappedData: SpeciesData,
        recordId: String,
        speciesId: String,
        timestamp: Date,
        captureDate: Date,
        capturedMediaJSON: String?,
        coverImagePath: String?,
        isLiveCapture: Bool,
        fieldNotes: String?
    ) -> LocalScanRecord {
        let petIdentificationData = mappedData.petIdentification.flatMap {
            try? JSONEncoder().encode($0)
        }
        let semanticPetTags = [mappedData.petIdentification?.label]
            .compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        let record = LocalScanRecord(
            id: recordId,
            speciesId: speciesId,
            scientificName: mappedData.scientificName,
            commonName: mappedData.commonName,
            timestamp: timestamp,
            captureDate: captureDate,
            capturedMediaJSON: capturedMediaJSON,
            coverImagePath: coverImagePath,
            semanticTags: [mappedData.commonName, mappedData.scientificName]
                + semanticPetTags
                + (mappedData.colors ?? [])
                + (mappedData.groupTags ?? []),
            hazardType: mappedData.insightData.hazardType,
            isBiological: mappedData.isBiological,
            isLiveCapture: isLiveCapture,
            isInvasive: mappedData.isInvasive,
            invasiveStatusRegion: mappedData.invasiveStatusRegion,
            invasiveRationale: mappedData.invasiveRationale,
            invasiveConfidence: mappedData.invasiveConfidence,
            ecologyType: mappedData.ecologyType,
            wikipediaUrl: mappedData.wikipediaUrl,
            referenceImageUrl: mappedData.referenceImageUrl,
            confidenceScore: mappedData.confidenceScore,
            taxonomyKingdom: mappedData.taxonomy?.kingdom,
            taxonomyPhylum: mappedData.taxonomy?.phylum,
            taxonomyClass: mappedData.taxonomy?.className,
            taxonomyOrder: mappedData.taxonomy?.order,
            taxonomyFamily: mappedData.taxonomy?.family,
            taxonomyGenus: mappedData.taxonomy?.genus,
            locationName: mappedData.locationName,
            weatherCondition: mappedData.weatherCondition,
            weatherTemperatureF: mappedData.weatherTemperatureF,
            similarSpecies: mappedData.similarSpecies?.lookalikes,
            candidatesData: mappedData.candidates.flatMap {
                try? JSONEncoder().encode($0)
            },
            iucnRedListStatus: mappedData.iucnRedListStatus,
            gpsLatitude: mappedData.gpsLatitude,
            gpsLongitude: mappedData.gpsLongitude,
            gpsElevation: mappedData.gpsElevation,
            zoomFactor: mappedData.zoomFactor,
            aiReasoning: mappedData.aiReasoning,
            habitatDescription: mappedData.habitatDescription,
            gbifTaxonKey: mappedData.gbifTaxonKey,
            estimatedSizeCm: mappedData.estimatedSizeCm,
            lifeStage: mappedData.lifeStage,
            reproductiveCondition: mappedData.reproductiveCondition,
            sex: mappedData.sex,
            sexConfidence: mappedData.sexConfidence,
            sexEvidence: mappedData.sexEvidence,
            individualCount: mappedData.individualCount,
            ecologicalInteractions: mappedData.ecologicalInteractions,
            inferenceTier: mappedData.inferenceTier,
            imageQualityScore: mappedData.imageQualityScore,
            alternativeCommonNames: mappedData.alternativeCommonNames,
            petIdentificationData: petIdentificationData,
            fieldNotes: fieldNotes
        )

        if let capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(
               jsonString: capturedMediaJSON
           ) {
            record.replaceCapturedMedia(with: items)
        } else {
            record.coverImagePath = coverImagePath
        }

        return record
    }
}
