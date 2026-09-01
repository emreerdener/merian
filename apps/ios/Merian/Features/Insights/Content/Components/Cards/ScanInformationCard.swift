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

    var body: some View {
        let rawName: String? = speciesData?.locationName ?? fallbackLocationName
        let temp: Double? = speciesData?.weatherTemperatureF ?? fallbackTemperature
        let cond: String? = speciesData?.weatherCondition ?? fallbackCondition
        let elevation: Double? = speciesData?.gpsElevation ?? fallbackElevation
        let lat: Double? = speciesData?.gpsLatitude ?? fallbackLatitude
        let lon: Double? = speciesData?.gpsLongitude ?? fallbackLongitude
        let zoom: Double? = speciesData?.zoomFactor
        let privacy = profileViewModel.defaultGeoprivacy
        let isPrivate = privacy == "private"
        let isObscured = privacy == "obscured"
        let displayLocationName = visibleLocationName(rawName, privacy: privacy)
        let displayElevation = privacy == "open" ? elevation : nil
        let displayTemperature = isPrivate ? nil : temp
        let displayCondition = isPrivate ? nil : cond
        let mapCoordinate = visibleMapCoordinate(latitude: lat, longitude: lon, privacy: privacy)
        let hasVisibleData = hasVisibleScanData(
            locationName: displayLocationName,
            temperature: displayTemperature,
            condition: displayCondition,
            elevation: displayElevation,
            mapCoordinate: mapCoordinate,
            zoom: zoom
        )

        if hasVisibleData {
            VStack(alignment: .leading, spacing: 16) {
                MerianCardHeader(systemImage: "viewfinder", title: "Scan")

                VStack(spacing: 12) {
                    // Location
                    if let validName = displayLocationName,
                       !validName.trimmingCharacters(in: .whitespaces).isEmpty {
                        KeyValueRow(title: "LOCATION", value: validName)
                    }

                    // Elevation
                    if let elev = displayElevation, elev != 0 {
                        KeyValueRow(title: "ELEVATION", value: "\(Int(elev))m")
                    }

                    // Weather
                    if let validTemp = displayTemperature,
                       let validCondition = displayCondition {
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
                    if let coord = mapCoordinate {
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

    private func hasVisibleScanData(
        locationName: String?,
        temperature: Double?,
        condition: String?,
        elevation: Double?,
        mapCoordinate: CLLocationCoordinate2D?,
        zoom: Double?
    ) -> Bool {
        let nameValid = locationName.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        let weatherValid = temperature != nil && condition != nil
        let elevationValid = elevation != nil && elevation != 0
        let zoomValid = zoom != nil
        return nameValid || weatherValid || elevationValid || mapCoordinate != nil || zoomValid || timestamp != nil
    }

    private func visibleLocationName(_ rawName: String?, privacy: String) -> String? {
        switch privacy {
        case "private":
            return nil
        case "obscured":
            return ExploreLocationPrivacy.displayLabel(from: rawName)
        default:
            return rawName
        }
    }

    private func visibleMapCoordinate(latitude: Double?, longitude: Double?, privacy: String) -> CLLocationCoordinate2D? {
        guard privacy != "private",
              let latitude,
              let longitude,
              latitude >= -90,
              latitude <= 90,
              longitude >= -180,
              longitude <= 180,
              !(latitude == 0 && longitude == 0) else {
            return nil
        }

        if privacy == "obscured" {
            return CLLocationCoordinate2D(
                latitude: roundedPublicCoordinate(latitude),
                longitude: roundedPublicCoordinate(longitude)
            )
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func roundedPublicCoordinate(_ value: Double) -> Double {
        (value * 10).rounded() / 10
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
