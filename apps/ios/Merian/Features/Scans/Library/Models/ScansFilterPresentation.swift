import Foundation

enum ScansFilterPresentation {
    static func formattedTitle(_ title: String) -> String {
        let normalized = title
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstCharacter = normalized.first else { return normalized }
        return firstCharacter.uppercased() + String(normalized.dropFirst())
    }

    static func selectedSummary<Value: Hashable>(
        _ values: Set<Value>,
        title: (Value) -> String
    ) -> String {
        if values.isEmpty {
            return "None"
        }

        if values.count == 1, let value = values.first {
            return formattedTitle(title(value))
        }

        return "\(values.count) selected"
    }

    static func dateSummary(_ filters: ScanLibraryFilters) -> String {
        if filters.dateFilters.count == 1,
           filters.dateFilters.contains(.custom) {
            return "Custom range"
        }

        return selectedSummary(filters.dateFilters, title: \.rawValue)
    }

    static func naturalistSummary(_ filters: ScanLibraryFilters) -> String {
        let count = (filters.isInvasive ? 1 : 0)
            + filters.ecologyFilters.count
            + filters.hazardTypes.count
            + filters.conservationStatuses.count
            + filters.lifeStages.count

        guard count != 0 else { return "None" }
        guard count == 1 else { return "\(count) selected" }
        if filters.isInvasive { return "Invasive" }

        let selectedValue = filters.ecologyFilters.first?.rawValue
            ?? filters.hazardTypes.first
            ?? filters.conservationStatuses.first
            ?? filters.lifeStages.first
        return selectedValue.map(formattedTitle) ?? "None"
    }

    static func taxonomySummary(_ filters: ScanLibraryFilters) -> String {
        let count = filters.taxonomyClasses.count
            + filters.taxonomyOrders.count
            + filters.taxonomyFamilies.count
            + filters.taxonomyGenera.count

        guard count != 0 else { return "None" }
        guard count == 1 else { return "\(count) selected" }

        let selectedValue = filters.taxonomyClasses.first
            ?? filters.taxonomyOrders.first
            ?? filters.taxonomyFamilies.first
            ?? filters.taxonomyGenera.first
        return selectedValue.map(formattedTitle) ?? "None"
    }

    static func hasTaxonomyOptions(
        _ options: ScanLibraryFilterOptions
    ) -> Bool {
        !options.taxonomyClasses.isEmpty
            || !options.taxonomyOrders.isEmpty
            || !options.taxonomyFamilies.isEmpty
            || !options.taxonomyGenera.isEmpty
    }
}
