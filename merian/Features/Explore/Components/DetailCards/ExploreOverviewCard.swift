import SwiftUI

struct ExploreOverviewCard: View {
    let iucnRedListStatus: String?
    let wikipediaOverview: String?

    private var normalizedIucnStatus: (text: String, isGood: Bool?)? {
        guard let rawStatus = iucnRedListStatus?.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rawStatus.isEmpty,
              rawStatus != "not applicable",
              rawStatus != "data deficient" else {
            return nil
        }

        let normalizedStatus = rawStatus.replacingOccurrences(of: "_", with: " ")

        switch normalizedStatus {
        case _ where normalizedStatus.contains("not evaluated"):
            return ("Not evaluated", nil)
        case _ where normalizedStatus.contains("least concern"):
            return ("Not at risk", true)
        case _ where normalizedStatus.contains("near threatened"):
            return ("Near threatened", false)
        case _ where normalizedStatus.contains("vulnerable"):
            return ("Vulnerable", false)
        case _ where normalizedStatus.contains("endangered") && !normalizedStatus.contains("critically"):
            return ("Endangered", false)
        case _ where normalizedStatus.contains("critically endangered"):
            return ("Critically endangered", false)
        case _ where normalizedStatus.contains("extinct in the wild"):
            return ("Extinct in the wild", false)
        case _ where normalizedStatus.contains("extinct"):
            return ("Extinct", false)
        default:
            return (capitalizeFirstLetter(normalizedStatus), true)
        }
    }

    private var trimmedWikipediaOverview: String? {
        guard let wikipediaOverview else { return nil }
        let trimmed = wikipediaOverview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 60 ? trimmed : nil
    }

    var body: some View {
        if normalizedIucnStatus != nil || trimmedWikipediaOverview != nil {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "book")
                        .foregroundColor(.secondary)
                    Text("Overview")
                        .font(.system(.headline))
                        .foregroundColor(.primary)
                }

                if let status = normalizedIucnStatus {
                    let iconName: String? = {
                        switch status.isGood {
                        case true?: return "checkmark.circle.fill"
                        case false?: return "exclamationmark.shield.fill"
                        case nil: return nil
                        }
                    }()

                    let iconColor: Color? = {
                        switch status.isGood {
                        case true?: return .green
                        case false?: return .red
                        case nil: return nil
                        }
                    }()

                    let textColor: Color? = {
                        switch status.isGood {
                        case false?: return .red
                        default: return nil
                        }
                    }()

                    KeyValueRow(
                        title: "CONSERVATION",
                        value: status.text,
                        valueIcon: iconName,
                        valueIconColor: iconColor,
                        valueTextColor: textColor
                    )
                }

                if let trimmedWikipediaOverview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WIKIPEDIA")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        Text(trimmedWikipediaOverview)
                            .font(.system(.body))
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func capitalizeFirstLetter(_ string: String) -> String {
        guard let first = string.first else { return "" }
        return String(first).uppercased() + string.dropFirst()
    }
}
