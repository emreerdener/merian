import Foundation

/// Versioned, immutable display allowlist. No notes, coordinates, media, tags
/// authored by the owner, review authority, or observation lifecycle state.
struct AnalysisDisplaySnapshot: Codable, Equatable {
    let version: Int
    let analysisID: UUID
    let speciesId: String
    let scientificName: String
    let commonName: String
    let semanticTags: [String]
    let hazardType: String
    let isBiological: Bool
    let isInvasive: Bool
    let invasiveStatusRegion: String?
    let invasiveRationale: String?
    let invasiveConfidence: Double?
    let ecologyType: String
    let wikipediaUrl: String?
    let wikipediaOverview: String?
    let referenceImageUrl: String?
    let confidenceScore: Double?
    let taxonomyKingdom: String?
    let taxonomyPhylum: String?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let taxonomyGenus: String?
    let iucnRedListStatus: String?
    let aiReasoning: String?
    let habitatDescription: String?
    let gbifTaxonKey: Int?
    let estimatedSizeCm: Double?
    let lifeStage: String?
    let reproductiveCondition: String?
    let sex: String?
    let sexConfidence: Double?
    let sexEvidence: String?
    let individualCount: Int?
    let ecologicalInteractions: [String]?
    let inferenceTier: String?
    let identificationProvenanceData: Data?
    let primaryIdentificationData: Data?
    let imageQualityScore: Int?
    let alternativeCommonNames: [String]?
    let petIdentificationData: Data?
    let candidatesData: Data?

    init(analysisID: UUID, record: LocalScanRecord) {
        self.version = 1
        self.analysisID = analysisID
        self.speciesId = record.speciesId
        self.scientificName = record.scientificName
        self.commonName = record.commonName
        self.semanticTags = record.semanticTags
        self.hazardType = record.hazardType
        self.isBiological = record.isBiological
        self.isInvasive = record.isInvasive
        self.invasiveStatusRegion = record.invasiveStatusRegion
        self.invasiveRationale = record.invasiveRationale
        self.invasiveConfidence = record.invasiveConfidence
        self.ecologyType = record.ecologyType
        self.wikipediaUrl = record.wikipediaUrl
        self.wikipediaOverview = record.wikipediaOverview
        self.referenceImageUrl = record.referenceImageUrl
        self.confidenceScore = record.confidenceScore
        self.taxonomyKingdom = record.taxonomyKingdom
        self.taxonomyPhylum = record.taxonomyPhylum
        self.taxonomyClass = record.taxonomyClass
        self.taxonomyOrder = record.taxonomyOrder
        self.taxonomyFamily = record.taxonomyFamily
        self.taxonomyGenus = record.taxonomyGenus
        self.iucnRedListStatus = record.iucnRedListStatus
        self.aiReasoning = record.aiReasoning
        self.habitatDescription = record.habitatDescription
        self.gbifTaxonKey = record.gbifTaxonKey
        self.estimatedSizeCm = record.estimatedSizeCm
        self.lifeStage = record.lifeStage
        self.reproductiveCondition = record.reproductiveCondition
        self.sex = record.sex
        self.sexConfidence = record.sexConfidence
        self.sexEvidence = record.sexEvidence
        self.individualCount = record.individualCount
        self.ecologicalInteractions = record.ecologicalInteractions
        self.inferenceTier = record.inferenceTier
        self.identificationProvenanceData = record.identificationProvenanceData
        self.primaryIdentificationData = record.primaryIdentificationData
        self.imageQualityScore = record.imageQualityScore
        self.alternativeCommonNames = record.alternativeCommonNames
        self.petIdentificationData = record.petIdentificationData
        self.candidatesData = record.candidatesData
    }

    // Encode null explicitly: absence is corruption, not an empty result field.
    enum CodingKeys: String, CodingKey {
        case version, analysisID, speciesId, scientificName, commonName
        case semanticTags, hazardType, isBiological, isInvasive, invasiveStatusRegion
        case invasiveRationale, invasiveConfidence, ecologyType, wikipediaUrl, wikipediaOverview
        case referenceImageUrl, confidenceScore, taxonomyKingdom, taxonomyPhylum, taxonomyClass
        case taxonomyOrder, taxonomyFamily, taxonomyGenus, iucnRedListStatus, aiReasoning
        case habitatDescription, gbifTaxonKey, estimatedSizeCm, lifeStage, reproductiveCondition
        case sex, sexConfidence, sexEvidence, individualCount, ecologicalInteractions
        case inferenceTier, identificationProvenanceData, primaryIdentificationData, imageQualityScore, alternativeCommonNames
        case petIdentificationData, candidatesData
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(analysisID, forKey: .analysisID)
        try values.encode(speciesId, forKey: .speciesId)
        try values.encode(scientificName, forKey: .scientificName)
        try values.encode(commonName, forKey: .commonName)
        try values.encode(semanticTags, forKey: .semanticTags)
        try values.encode(hazardType, forKey: .hazardType)
        try values.encode(isBiological, forKey: .isBiological)
        try values.encode(isInvasive, forKey: .isInvasive)
        try values.encode(invasiveStatusRegion, forKey: .invasiveStatusRegion)
        try values.encode(invasiveRationale, forKey: .invasiveRationale)
        try values.encode(invasiveConfidence, forKey: .invasiveConfidence)
        try values.encode(ecologyType, forKey: .ecologyType)
        try values.encode(wikipediaUrl, forKey: .wikipediaUrl)
        try values.encode(wikipediaOverview, forKey: .wikipediaOverview)
        try values.encode(referenceImageUrl, forKey: .referenceImageUrl)
        try values.encode(confidenceScore, forKey: .confidenceScore)
        try values.encode(taxonomyKingdom, forKey: .taxonomyKingdom)
        try values.encode(taxonomyPhylum, forKey: .taxonomyPhylum)
        try values.encode(taxonomyClass, forKey: .taxonomyClass)
        try values.encode(taxonomyOrder, forKey: .taxonomyOrder)
        try values.encode(taxonomyFamily, forKey: .taxonomyFamily)
        try values.encode(taxonomyGenus, forKey: .taxonomyGenus)
        try values.encode(iucnRedListStatus, forKey: .iucnRedListStatus)
        try values.encode(aiReasoning, forKey: .aiReasoning)
        try values.encode(habitatDescription, forKey: .habitatDescription)
        try values.encode(gbifTaxonKey, forKey: .gbifTaxonKey)
        try values.encode(estimatedSizeCm, forKey: .estimatedSizeCm)
        try values.encode(lifeStage, forKey: .lifeStage)
        try values.encode(reproductiveCondition, forKey: .reproductiveCondition)
        try values.encode(sex, forKey: .sex)
        try values.encode(sexConfidence, forKey: .sexConfidence)
        try values.encode(sexEvidence, forKey: .sexEvidence)
        try values.encode(individualCount, forKey: .individualCount)
        try values.encode(ecologicalInteractions, forKey: .ecologicalInteractions)
        try values.encode(inferenceTier, forKey: .inferenceTier)
        try values.encode(identificationProvenanceData, forKey: .identificationProvenanceData)
        try values.encode(primaryIdentificationData, forKey: .primaryIdentificationData)
        try values.encode(imageQualityScore, forKey: .imageQualityScore)
        try values.encode(alternativeCommonNames, forKey: .alternativeCommonNames)
        try values.encode(petIdentificationData, forKey: .petIdentificationData)
        try values.encode(candidatesData, forKey: .candidatesData)
    }

    func storedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard version == 1, data.count <= LocalAnalysisRecord.maximumSnapshotBytes else { throw ValidationError.invalidSnapshot }
        return data
    }

    static func restore(_ data: Data, analysisID: UUID) throws -> Self {
        guard data.count <= LocalAnalysisRecord.maximumSnapshotBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == allowedKeys else { throw ValidationError.invalidSnapshot }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, value.analysisID == analysisID else { throw ValidationError.invalidSnapshot }
        return value
    }

    /// Prepared projection only; the fenced state transaction owns admission.
    /// Explicitly clear result-dependent enrichment so no fields leak from A to B.
    func apply(to record: LocalScanRecord) {
        record.speciesId = speciesId
        record.scientificName = scientificName
        record.commonName = commonName
        record.semanticTags = semanticTags
        record.hazardType = hazardType
        record.isBiological = isBiological
        record.isInvasive = isInvasive
        record.invasiveStatusRegion = invasiveStatusRegion
        record.invasiveRationale = invasiveRationale
        record.invasiveConfidence = invasiveConfidence
        record.ecologyType = ecologyType
        record.wikipediaUrl = wikipediaUrl
        record.wikipediaOverview = wikipediaOverview
        record.referenceImageUrl = referenceImageUrl
        record.confidenceScore = confidenceScore
        record.taxonomyKingdom = taxonomyKingdom
        record.taxonomyPhylum = taxonomyPhylum
        record.taxonomyClass = taxonomyClass
        record.taxonomyOrder = taxonomyOrder
        record.taxonomyFamily = taxonomyFamily
        record.taxonomyGenus = taxonomyGenus
        record.iucnRedListStatus = iucnRedListStatus
        record.aiReasoning = aiReasoning
        record.habitatDescription = habitatDescription
        record.gbifTaxonKey = gbifTaxonKey
        record.estimatedSizeCm = estimatedSizeCm
        record.lifeStage = lifeStage
        record.reproductiveCondition = reproductiveCondition
        record.sex = sex
        record.sexConfidence = sexConfidence
        record.sexEvidence = sexEvidence
        record.individualCount = individualCount
        record.ecologicalInteractions = ecologicalInteractions
        record.inferenceTier = inferenceTier
        record.identificationProvenanceData = identificationProvenanceData
        record.primaryIdentificationData = primaryIdentificationData
        record.imageQualityScore = imageQualityScore
        record.alternativeCommonNames = alternativeCommonNames
        record.petIdentificationData = petIdentificationData
        record.candidatesData = candidatesData
        record.similarSpecies = nil
        record.lookalikesData = nil
    }

    enum ValidationError: Error { case invalidSnapshot }
    private static let allowedKeys: Set<String> = [
        "speciesId", "scientificName", "commonName", "semanticTags",
        "hazardType", "isBiological", "isInvasive", "invasiveStatusRegion",
        "invasiveRationale", "invasiveConfidence", "ecologyType", "wikipediaUrl",
        "wikipediaOverview", "referenceImageUrl", "confidenceScore", "taxonomyKingdom",
        "taxonomyPhylum", "taxonomyClass", "taxonomyOrder", "taxonomyFamily",
        "taxonomyGenus", "iucnRedListStatus", "aiReasoning", "habitatDescription",
        "gbifTaxonKey", "estimatedSizeCm", "lifeStage", "reproductiveCondition",
        "sex", "sexConfidence", "sexEvidence", "individualCount",
        "ecologicalInteractions", "inferenceTier", "identificationProvenanceData", "primaryIdentificationData",
        "imageQualityScore", "alternativeCommonNames", "petIdentificationData", "candidatesData",
        "version", "analysisID"
    ]
}
