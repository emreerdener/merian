import SwiftUI

enum ExploreOverviewCardAction {
    case wikipedia
    case speciesDictionary(SpeciesDictionaryRoute)
}

struct ExploreOverviewCard: View {
    let scientificName: String
    let iucnRedListStatus: String?
    let wikipediaOverview: String?
    let action: ExploreOverviewCardAction

    @State private var isSafariPresented = false
    @State private var selectedWikiURL: URL?

    init(
        scientificName: String,
        iucnRedListStatus: String?,
        wikipediaOverview: String?,
        action: ExploreOverviewCardAction = .wikipedia
    ) {
        self.scientificName = scientificName
        self.iucnRedListStatus = iucnRedListStatus
        self.wikipediaOverview = wikipediaOverview
        self.action = action
    }

    static func hasVisibleContent(
        iucnRedListStatus: String?,
        wikipediaOverview: String?
    ) -> Bool {
        normalizedIucnStatus(from: iucnRedListStatus) != nil
            || trimmedWikipediaOverview(from: wikipediaOverview) != nil
    }

    private static func normalizedIucnStatus(from iucnRedListStatus: String?) -> (text: String, isGood: Bool?)? {
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

    private static func trimmedWikipediaOverview(from wikipediaOverview: String?) -> String? {
        guard let wikipediaOverview else { return nil }
        let trimmed = wikipediaOverview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 60 ? trimmed : nil
    }

    private var normalizedIucnStatus: (text: String, isGood: Bool?)? {
        Self.normalizedIucnStatus(from: iucnRedListStatus)
    }

    private var trimmedWikipediaOverview: String? {
        Self.trimmedWikipediaOverview(from: wikipediaOverview)
    }

    var body: some View {
        if normalizedIucnStatus != nil || trimmedWikipediaOverview != nil {
            VStack(alignment: .leading, spacing: 16) {
                MerianCardHeader(systemImage: "book", title: "Overview")

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
                    WikipediaSummarySection(text: trimmedWikipediaOverview)
                }

                callToAction
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .sheet(isPresented: $isSafariPresented) {
                if let safeUrl = selectedWikiURL {
                    SafariView(url: safeUrl)
                        .ignoresSafeArea()
                }
            }
        }
    }

    @ViewBuilder
    private var callToAction: some View {
        switch action {
        case .wikipedia:
            if trimmedWikipediaOverview != nil,
               let wikiUrl = URL(string: "https://en.wikipedia.org/wiki/\(scientificName.replacingOccurrences(of: " ", with: "_"))") {
                WikipediaReadMoreButton {
                    selectedWikiURL = wikiUrl
                    isSafariPresented = true
                }
            }

        case .speciesDictionary(let route):
            NavigationLink(value: route) {
                Text("View species dictionary")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private static func capitalizeFirstLetter(_ string: String) -> String {
        guard let first = string.first else { return "" }
        return String(first).uppercased() + string.dropFirst()
    }
}
