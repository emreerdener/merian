import SwiftUI

struct ScanInformationCard: View {
    let speciesData: SpeciesData?
    var timestamp: Date? = nil
    
    var hasValidData: Bool {
        guard let sd = speciesData else { return false }
        let nameValid = sd.locationName != nil && !sd.locationName!.trimmingCharacters(in: .whitespaces).isEmpty
        let weatherValid = sd.weatherTemperatureF != nil && sd.weatherCondition != nil
        // A mathematically exact `0.0` output from CoreLocation natively denotes a missing 
        // vertical altitude fix. Authentic sea-level topological readings always float (e.g., 0.3m, -1.2m).
        let elevationValid = sd.gpsElevation != nil && sd.gpsElevation != 0
        return nameValid || weatherValid || elevationValid || timestamp != nil
    }
    
    var body: some View {
        let name: String? = speciesData?.locationName
        let temp: Double? = speciesData?.weatherTemperatureF
        let cond: String? = speciesData?.weatherCondition
        let elevation: Double? = speciesData?.gpsElevation
        
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
                        featureRow(title: "LOCATION", value: validName)
                    }
                    
                    if let elev = elevation, elev != 0 {
                        featureRow(title: "ELEVATION", value: "\(Int(elev))m")
                    }
                    
                    if let validTemp = temp, let validCondition = cond {
                        featureRow(
                            title: "WEATHER", 
                            value: "\(Int(validTemp))°F \(validCondition.capitalized)",
                            valueIcon: weatherIcon(for: validCondition)
                        )
                    }
                    
                    if let ts = timestamp {
                        featureRow(
                            title: "TIME",
                            value: ts.formatted(date: .omitted, time: .shortened)
                        )
                    }
                }
            }
            .card()
        }
    }
    
    @ViewBuilder
    private func featureRow(title: String, value: String, valueIcon: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .tracking(1)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 6) {
                if let vIcon = valueIcon {
                    Image(systemName: vIcon)
                        .foregroundColor(.secondary)
                }
                Text(value)
            }
            .font(.system(.subheadline))
            .fontWeight(.medium)
            .foregroundColor(.primary)
            .multilineTextAlignment(.trailing)
        }
    }
    
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
