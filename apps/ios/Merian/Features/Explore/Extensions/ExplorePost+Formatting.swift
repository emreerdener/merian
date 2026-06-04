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

    var publicAuthorDisplayName: String {
        Self.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }

    func authorDisplayName(preferUsername: Bool) -> String {
        Self.publicAuthorDisplayName(
            from: authorName,
            username: authorUsername,
            preferUsername: preferUsername
        )
    }

    static func publicAuthorDisplayName(
        from rawName: String,
        username: String? = nil,
        preferUsername: Bool = false
    ) -> String {
        if preferUsername, let displayUsername = publicUsernameDisplayValue(username) {
            return displayUsername
        }

        let normalizedName = rawName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if let displayUsername = publicUsernameDisplayValue(username),
           normalizedName.isEmpty || normalizedName == username {
            return displayUsername
        }

        guard !normalizedName.isEmpty else { return rawName }

        var parts = normalizedName.split(separator: " ").map(String.init)
        guard let lastPart = parts.last,
              lastPart.count == 2,
              lastPart.last == ".",
              lastPart.first?.isLetter == true else {
            return normalizedName
        }

        parts.removeLast()
        return parts.isEmpty ? normalizedName : parts.joined(separator: " ")
    }

    static func publicUsernameDisplayValue(_ rawUsername: String?) -> String? {
        guard let rawUsername else { return nil }
        let trimmedUsername = rawUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = trimmedUsername.hasPrefix("@")
            ? String(trimmedUsername.dropFirst())
            : trimmedUsername
        guard !username.isEmpty else { return nil }
        return "@\(username)"
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

extension ExploreComment {
    var displayAuthorName: String {
        ExplorePost.publicAuthorDisplayName(from: authorName, username: authorUsername)
    }
}
