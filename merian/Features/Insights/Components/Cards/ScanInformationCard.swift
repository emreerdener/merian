import SwiftUI
import MapKit

struct ScanInformationCard: View {
    let speciesData: SpeciesData?
    var timestamp: Date? = nil
    
    var hasValidData: Bool {
        guard let sd = speciesData else { return false }
        let nameValid = sd.locationName.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        let weatherValid = sd.weatherTemperatureF != nil && sd.weatherCondition != nil
        // A mathematically exact `0.0` output from CoreLocation natively denotes a missing 
        // vertical altitude fix. Authentic sea-level topological readings always float (e.g., 0.3m, -1.2m).
        let elevationValid = sd.gpsElevation != nil && sd.gpsElevation != 0
        let coordsValid: Bool = {
            guard let lat = sd.gpsLatitude, let lon = sd.gpsLongitude else { return false }
            let latValid = lat >= -90 && lat <= 90
            let lonValid = lon >= -180 && lon <= 180
            return latValid && lonValid && !(lat == 0 && lon == 0)
        }()
        return nameValid || weatherValid || elevationValid || coordsValid || timestamp != nil
    }
    
    var body: some View {
        let name: String? = speciesData?.locationName
        let temp: Double? = speciesData?.weatherTemperatureF
        let cond: String? = speciesData?.weatherCondition
        let elevation: Double? = speciesData?.gpsElevation
        let lat: Double? = speciesData?.gpsLatitude
        let lon: Double? = speciesData?.gpsLongitude
        
        if hasValidData {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundColor(.secondary)
                    Text("Scan")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }
                
                VStack(spacing: 12) {
                    if let validName = name, !validName.trimmingCharacters(in: .whitespaces).isEmpty {
                        KeyValueRow(title: "LOCATION", value: validName)
                    }
                    
                    if let elev = elevation, elev != 0 {
                        KeyValueRow(title: "ELEVATION", value: "\(Int(elev))m")
                    }
                    
                    if let validTemp = temp, let validCondition = cond {
                        KeyValueRow(
                            title: "WEATHER", 
                            value: "\(Int(validTemp))°F \(validCondition.capitalized)",
                            valueIcon: weatherIcon(for: validCondition)
                        )
                    }
                    
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
                    
                    // Map
                    if let lat = lat, let lon = lon, (lat >= -90 && lat <= 90), (lon >= -180 && lon <= 180), !(lat == 0 && lon == 0) {
                        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                        Map(initialPosition: .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))) {
                            Marker("Location", coordinate: coord)
                                .tint(Color.accentColor)
                        }
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(radius: 0)
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
