import Foundation

extension ExplorePost {
    private static let exploreTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var publicDayPartLabel: String? {
        guard let timeOfDay,
              let time = Self.exploreTimeFormatter.date(from: timeOfDay) else {
            return nil
        }

        let hour = Calendar.current.component(.hour, from: time)
        switch hour {
        case 5..<12:
            return "Morning"
        case 12..<17:
            return "Afternoon"
        case 17..<21:
            return "Evening"
        default:
            return "Night"
        }
    }

    var publicMonthLabel: String? {
        guard let currentMonth, (1...12).contains(currentMonth) else { return nil }
        return Calendar.current.monthSymbols[currentMonth - 1]
    }

    var observationContextLabel: String? {
        let rawValues: [String?] = [publicDayPartLabel, publicMonthLabel]
        let values = rawValues.reduce(into: [String]()) { partialResult, value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else {
                return
            }
            partialResult.append(value)
        }

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }

    var publicWeatherLabel: String? {
        let normalizedCondition = weatherCondition?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized

        let normalizedTemperature = weatherTemperatureF.map { "\($0.formatted(.number.precision(.fractionLength(0))))°F" }

        let rawValues: [String?] = [normalizedCondition, normalizedTemperature]
        let values = rawValues.reduce(into: [String]()) { partialResult, value in
            guard let value, !value.isEmpty else { return }
            partialResult.append(value)
        }

        guard !values.isEmpty else { return nil }
        return values.joined(separator: " • ")
    }

    var sharedDateLabel: String? {
        guard let sharedAtDate else { return nil }
        return sharedAtDate.formatted(date: .abbreviated, time: .omitted)
    }
}
