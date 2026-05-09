import MapKit
import SwiftUI

struct ScanInformationCard: View {
    @Environment(ProfileViewModel.self) private var profileViewModel

    let speciesData: SpeciesData?
    var timestamp: Date?
    var imageCount: Int = 1
    
    // Optional rendering fallbacks when speciesData is unvailable during live analysis
    var fallbackLocationName: String?
    var fallbackTemperature: Double?
    var fallbackCondition: String?
    var fallbackElevation: Double?
    var fallbackLatitude: Double?
    var fallbackLongitude: Double?
    
    var hasValidData: Bool {
        let nameValid = (speciesData?.locationName ?? fallbackLocationName).map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        let weatherValid = (speciesData?.weatherTemperatureF ?? fallbackTemperature) != nil && (speciesData?.weatherCondition ?? fallbackCondition) != nil
        let elev = speciesData?.gpsElevation ?? fallbackElevation
        let elevationValid = elev != nil && elev != 0
        let coordsValid: Bool = {
            let lat = speciesData?.gpsLatitude ?? fallbackLatitude
            let lon = speciesData?.gpsLongitude ?? fallbackLongitude
            guard let lat = lat, let lon = lon else { return false }
            let latValid = lat >= -90 && lat <= 90
            let lonValid = lon >= -180 && lon <= 180
            return latValid && lonValid && !(lat == 0 && lon == 0)
        }()
        let zoomValid = speciesData?.zoomFactor != nil
        return nameValid || weatherValid || elevationValid || coordsValid || zoomValid || timestamp != nil
    }
    
    var body: some View {
        let name: String? = speciesData?.locationName ?? fallbackLocationName
        let temp: Double? = speciesData?.weatherTemperatureF ?? fallbackTemperature
        let cond: String? = speciesData?.weatherCondition ?? fallbackCondition
        let elevation: Double? = speciesData?.gpsElevation ?? fallbackElevation
        let lat: Double? = speciesData?.gpsLatitude ?? fallbackLatitude
        let lon: Double? = speciesData?.gpsLongitude ?? fallbackLongitude
        let zoom: Double? = speciesData?.zoomFactor
        
        if hasValidData {
            VStack(alignment: .leading, spacing: 16) {
                InsightCardHeader(systemImage: "viewfinder", title: "Scan")
                
                VStack(spacing: 12) {
                    // Location
                    if let validName = name, !validName.trimmingCharacters(in: .whitespaces).isEmpty {
                        KeyValueRow(title: "LOCATION", value: validName)
                    }
                    
                    // Elevation
                    if let elev = elevation, elev != 0 {
                        KeyValueRow(title: "ELEVATION", value: "\(Int(elev))m")
                    }
                    
                    // Weather
                    if let validTemp = temp, let validCondition = cond {
                        KeyValueRow(
                            title: "WEATHER", 
                            value: "\(Int(validTemp))°F \(validCondition.capitalized)",
                            valueIcon: weatherIcon(for: validCondition)
                        )
                    }
                    
                    // Date & Time
                    if let ts = timestamp {
                        KeyValueRow(
                            title: "DATE",
                            value: ts.formatted(date: .abbreviated, time: .omitted)
                        )
                        
                        KeyValueRow(
                            title: "TIME",
                            value: ts.formatted(date: .omitted, time: .shortened)
                        )
                    }

                    // Image count (only shown when > 1)
                    if imageCount > 1 {
                        KeyValueRow(title: "IMAGES", value: "\(imageCount) photos")
                    }

                    // Zoom
                    if let z = zoom {
                        KeyValueRow(title: "CAMERA ZOOM", value: String(format: "%.1f×", z))
                    }
                    
                    // Map
                    let privacy = profileViewModel.defaultGeoprivacy
                    if privacy != "private", let lat = lat, let lon = lon, lat >= -90 && lat <= 90, lon >= -180 && lon <= 180, !(lat == 0 && lon == 0) {
                        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        let isObscured = privacy == "obscured"
                        let span = isObscured ? MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2) : MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        
                        Map(initialPosition: .region(MKCoordinateRegion(center: coord, span: span))) {
                            if isObscured {
                                MapCircle(center: coord, radius: CLLocationDistance(10000))
                                    .foregroundStyle(Color.accentColor.opacity(0.3))
                                    .stroke(Color.accentColor, lineWidth: 1)
                            } else {
                                Marker("Location", coordinate: coord)
                                    .tint(Color.accentColor)
                            }
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(UIColor.separator), lineWidth: 0.5)
                        )
                        .allowsHitTesting(false)
                        .padding(.top, 4)
                    }
                }
            }
            .card()
        }
    }
    
// Removed featureRow since KeyValueRow was extracted
    
    private func weatherIcon(for condition: String) -> String {
        let lower = condition.lowercased()
        if lower.contains("sun") || lower.contains("clear") { return "sun.max.fill" }
        if lower.contains("fog") || lower.contains("haze") { return "cloud.fog.fill" }
        if lower.contains("rain") || lower.contains("drizzle") || lower.contains("shower") { return "cloud.rain.fill" }
        if lower.contains("snow") || lower.contains("ice") { return "snowflake" }
        if lower.contains("thunder") || lower.contains("storm") { return "cloud.bolt.rain.fill" }
        if lower.contains("wind") || lower.contains("breeze") { return "wind" }
        if lower.contains("cloud") || lower.contains("overcast") { return "cloud.fill" }
        return "cloud.sun.fill"
    }
}
