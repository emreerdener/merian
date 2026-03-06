import Foundation
import SwiftData

@Model
final class OfflineQueuedScan {
    @Attribute(.unique) var id: String
    var timestamp: Date
    var localImagePaths: [String] // Paths in URL.documentsDirectory
    
    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var gpsElevation: Double?
    var weatherCondition: String?
    var weatherTemperatureF: Double?
    var blurScore: Double?
    
    var isDeleted: Bool
    
    init(id: String = UUID().uuidString,
         timestamp: Date = Date(),
         localImagePaths: [String] = [],
         gpsLatitude: Double? = nil,
         gpsLongitude: Double? = nil,
         gpsElevation: Double? = nil,
         weatherCondition: String? = nil,
         weatherTemperatureF: Double? = nil,
         blurScore: Double? = nil,
         isDeleted: Bool = false) {
        
        self.id = id
        self.timestamp = timestamp
        self.localImagePaths = localImagePaths
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsElevation = gpsElevation
        self.weatherCondition = weatherCondition
        self.weatherTemperatureF = weatherTemperatureF
        self.blurScore = blurScore
        self.isDeleted = isDeleted
    }
}
