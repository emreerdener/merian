struct ExploreMediaIncidentSummary: Equatable, Sendable {
    let unavailablePublishedScanIDs: Set<String>

    init(incidents: some Sequence<ExploreMediaIncident>) {
        unavailablePublishedScanIDs = Set(incidents.map(\.scanId))
    }

    var unavailablePublishedScanCount: Int {
        unavailablePublishedScanIDs.count
    }

    var overviewDismissalSignature: String? {
        guard !unavailablePublishedScanIDs.isEmpty else { return nil }
        return unavailablePublishedScanIDs
            .sorted()
            .map { "\($0.utf8.count):\($0)" }
            .joined()
    }
}
