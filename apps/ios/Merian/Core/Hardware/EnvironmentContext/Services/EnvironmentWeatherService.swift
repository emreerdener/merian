import CoreLocation
import Foundation
import WeatherKit

struct EnvironmentWeatherService {
    let current:
        @MainActor (_ location: CLLocation) async throws
            -> EnvironmentWeatherReading
    let historical:
        @MainActor (_ location: CLLocation, _ date: Date) async throws
            -> EnvironmentWeatherReading?

    @MainActor static var live: Self {
        let weatherService = WeatherService.shared
        return Self(
            current: { location in
                let weather = try await weatherService.weather(for: location)
                return EnvironmentWeatherReading(
                    condition: weather.currentWeather.condition.description,
                    temperatureFahrenheit: weather.currentWeather.temperature
                        .converted(to: .fahrenheit).value
                )
            },
            historical: { location, date in
                let weather = try await weatherService.weather(
                    for: location,
                    including: .hourly(
                        startDate: date,
                        endDate: date.addingTimeInterval(3_600)
                    )
                )
                guard let targetHour = weather.first else { return nil }
                return EnvironmentWeatherReading(
                    condition: targetHour.condition.description,
                    temperatureFahrenheit: targetHour.temperature
                        .converted(to: .fahrenheit).value
                )
            }
        )
    }
}
