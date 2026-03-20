import SwiftUI

struct WeatherBadgeView: View {
    let temperatureF: Double?
    let condition: String?
    
    var body: some View {
        #if targetEnvironment(simulator)
        let temp: Double? = temperatureF ?? 64.0
        let cond: String? = condition ?? "Foggy"
        #else
        let temp: Double? = temperatureF
        let cond: String? = condition
        #endif
        
        if let validTemp = temp, let validCondition = cond {
            BadgeView(
                text: "\(Int(validTemp))°F \(validCondition.capitalized)",
                color: .primary,
                icon: weatherIcon(for: validCondition)
            )
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
