import Foundation
import SwiftData

@Model
final class LocalScanRecord {
    @Attribute(.unique) var id: String
    var speciesId: String
    var scientificName: String
    var commonName: String
    var insightDescription: String
    var timestamp: Date
    var localImagePath: String?
    
    // The Semantic Index explicitly driven by Gemini tags, enabling full Natural Language queries completely off-network.
    var semanticTags: [String]
    var isPoisonous: Bool
    var isBiological: Bool
    var isLiveCapture: Bool
    var isInvasive: Bool
    var ecologyType: String
    var wikipediaUrl: String?
    var referenceImageUrl: String?
    var additionalImagePaths: [String]?
    var confidenceScore: Double?
    
    init(id: String = UUID().uuidString,
         speciesId: String,
         scientificName: String,
         commonName: String,
         insightDescription: String,
         timestamp: Date = Date(),
         localImagePath: String? = nil,
         semanticTags: [String] = [],
         isPoisonous: Bool = false,
         isBiological: Bool = true,
         isLiveCapture: Bool = true,
         isInvasive: Bool = false,
         ecologyType: String = "unknown",
         wikipediaUrl: String? = nil,
         referenceImageUrl: String? = nil,
         additionalImagePaths: [String]? = nil,
         confidenceScore: Double? = nil) {
        
        self.id = id
        self.speciesId = speciesId
        self.scientificName = scientificName
        self.commonName = commonName
        self.insightDescription = insightDescription
        self.timestamp = timestamp
        self.localImagePath = localImagePath
        self.semanticTags = semanticTags
        self.isPoisonous = isPoisonous
        self.isBiological = isBiological
        self.isLiveCapture = isLiveCapture
        self.isInvasive = isInvasive
        self.ecologyType = ecologyType
        self.wikipediaUrl = wikipediaUrl
        self.referenceImageUrl = referenceImageUrl
        self.additionalImagePaths = additionalImagePaths
        self.confidenceScore = confidenceScore
    }
}
