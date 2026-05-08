import SwiftUI

struct ExploreObservationContextCard: View {
    let post: ExplorePost
    let detail: ExplorePostDetail?

    private var rows: [ExploreObservationContextRow] {
        var rows: [ExploreObservationContextRow] = []

        if let location = post.publicLocationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty {
            rows.append(
                ExploreObservationContextRow(
                    title: "LOCATION",
                    value: location,
                    valueIcon: nil
                )
            )
        }

        if let observationContext = post.observationContextLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "OBSERVED",
                    value: observationContext,
                    valueIcon: nil
                )
            )
        }

        if let weatherLabel = post.publicWeatherLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "WEATHER",
                    value: weatherLabel,
                    valueIcon: weatherIcon(for: post.weatherCondition)
                )
            )
        }

        if let sharedDateLabel = post.sharedDateLabel {
            rows.append(
                ExploreObservationContextRow(
                    title: "SHARED",
                    value: sharedDateLabel,
                    valueIcon: nil
                )
            )
        }

        return rows
    }

    var body: some View {
        let fieldNotes = detail?.trimmedFieldNotes

        if fieldNotes != nil || !rows.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .foregroundColor(.secondary)
                    Text("Observation")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        KeyValueRow(
                            title: row.title,
                            value: row.value,
                            valueIcon: row.valueIcon
                        )
                    }
                }

                if let fieldNotes {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FIELD NOTES")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text(fieldNotes)
                            .font(.system(.body))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
            }
            .card()
        }
    }

    private func weatherIcon(for condition: String?) -> String? {
        guard let condition else { return nil }

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

struct ExploreObservationContextRow: Identifiable {
    let title: String
    let value: String
    let valueIcon: String?

    var id: String {
        "\(title)-\(value)-\(valueIcon ?? "none")"
    }
}
