import SwiftUI
import UIKit

private extension View {
    func filterSheetOpaqueBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

private enum ScansFilterGroup: Hashable {
    case category
    case sort
    case date
    case location
    case media
    case tags
    case naturalist
    case ecology
    case hazardTypes
    case conservationStatus
    case lifeStage
    case quality
    case identification
    case weather
    case season
    case taxonomy
    case taxonomyClass
    case taxonomyOrder
    case taxonomyFamily
    case taxonomyGenus
    case explorePosts
}

struct ScansFilterSheet: View {
    @Bindable var searchManager: ScansManager
    let filterCategories: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var expandedGroups: Set<ScansFilterGroup> = []
    @State private var presentedActiveFilterCount: Int?

    private var options: ScanLibraryFilterOptions {
        searchManager.filterOptions
    }

    var body: some View {
        NavigationStack {
            Form {
                filterDisclosureGroup(
                    .sort,
                    title: "Sort",
                    summary: ScansFilterPresentation.formattedTitle(
                        searchManager.sortOption.rawValue
                    )
                ) {
                    ForEach(ScanSortOption.allCases) { option in
                        filterRow(title: option.rawValue, isSelected: searchManager.sortOption == option) {
                            searchManager.sortOption = option
                        }
                    }
                }

                filterDisclosureGroup(
                    .category,
                    title: "Species category",
                    summary: ScansFilterPresentation.formattedTitle(
                        searchManager.activeCategoryFilter
                    )
                ) {
                    ForEach(filterCategories, id: \.self) { category in
                        filterRow(
                            title: category,
                            isSelected: searchManager.activeCategoryFilter == category
                        ) {
                            searchManager.performSearch(
                                query: searchManager.searchQuery,
                                category: category
                            )
                        }
                    }
                }

                filterDisclosureGroup(.date, title: "Date", summary: dateSummary) {
                    ForEach(ScanDateFilter.allCases) { filter in
                        filterRow(
                            title: filter.rawValue,
                            isSelected: searchManager.filters.dateFilters.contains(filter)
                        ) {
                            toggleDateFilter(filter)
                        }
                    }

                    if searchManager.filters.dateFilters.contains(.custom) {
                        DatePicker(
                            "Start",
                            selection: customDateBinding(\.customStartDate),
                            displayedComponents: .date
                        )
                        DatePicker(
                            "End",
                            selection: customDateBinding(\.customEndDate),
                            displayedComponents: .date
                        )
                    }
                }

                filterDisclosureGroup(
                    .location,
                    title: "Location",
                    summary: selectedSummary(searchManager.filters.locationFilters, title: \.rawValue)
                ) {
                    multiSelectRows(
                        ScanLocationFilter.allCases,
                        keyPath: \.locationFilters,
                        title: \.rawValue
                    )
                }

                filterDisclosureGroup(
                    .media,
                    title: "Media",
                    summary: selectedSummary(searchManager.filters.mediaFilters, title: \.rawValue)
                ) {
                    multiSelectRows(
                        ScanMediaFilter.allCases,
                        keyPath: \.mediaFilters,
                        title: \.rawValue
                    )
                }

                if !options.customTags.isEmpty {
                    filterDisclosureGroup(
                        .tags,
                        title: "Tags",
                        summary: selectedStringSummary(searchManager.filters.customTags)
                    ) {
                        dynamicStringRows(options.customTags, keyPath: \.customTags)
                    }
                }

                filterDisclosureGroup(.naturalist, title: "Naturalist", summary: naturalistSummary) {
                    filterRow(title: "Invasive", isSelected: searchManager.filters.isInvasive) {
                        var updated = searchManager.filters
                        updated.isInvasive.toggle()
                        searchManager.filters = updated
                    }

                    nestedDisclosureGroup(
                        .ecology,
                        title: "Ecology",
                        summary: selectedSummary(searchManager.filters.ecologyFilters, title: \.rawValue)
                    ) {
                        multiSelectRows(
                            ScanEcologyFilter.allCases,
                            keyPath: \.ecologyFilters,
                            title: \.rawValue
                        )
                    }

                    if !options.hazardTypes.isEmpty {
                        nestedDisclosureGroup(
                            .hazardTypes,
                            title: "Hazards",
                            summary: selectedStringSummary(searchManager.filters.hazardTypes)
                        ) {
                            dynamicStringRows(options.hazardTypes, keyPath: \.hazardTypes)
                        }
                    }

                    if !options.conservationStatuses.isEmpty {
                        nestedDisclosureGroup(
                            .conservationStatus,
                            title: "Conservation",
                            summary: selectedStringSummary(searchManager.filters.conservationStatuses)
                        ) {
                            dynamicStringRows(options.conservationStatuses, keyPath: \.conservationStatuses)
                        }
                    }

                    if !options.lifeStages.isEmpty {
                        nestedDisclosureGroup(
                            .lifeStage,
                            title: "Life stage",
                            summary: selectedStringSummary(searchManager.filters.lifeStages)
                        ) {
                            dynamicStringRows(options.lifeStages, keyPath: \.lifeStages)
                        }
                    }
                }

                filterDisclosureGroup(
                    .quality,
                    title: "Image quality",
                    summary: selectedSummary(searchManager.filters.qualityFilters, title: \.rawValue)
                ) {
                    multiSelectRows(
                        ScanQualityFilter.allCases,
                        keyPath: \.qualityFilters,
                        title: \.rawValue
                    )
                }

                filterDisclosureGroup(
                    .identification,
                    title: "Identification",
                    summary: selectedSummary(searchManager.filters.identificationFilters, title: \.rawValue)
                ) {
                    multiSelectRows(
                        ScanIdentificationFilter.allCases,
                        keyPath: \.identificationFilters,
                        title: \.rawValue
                    )
                }

                if !options.weatherConditions.isEmpty {
                    filterDisclosureGroup(
                        .weather,
                        title: "Weather",
                        summary: selectedStringSummary(searchManager.filters.weatherConditions)
                    ) {
                        dynamicStringRows(options.weatherConditions, keyPath: \.weatherConditions)
                    }
                }

                filterDisclosureGroup(
                    .season,
                    title: "Season",
                    summary: selectedSummary(searchManager.filters.seasons, title: \.rawValue)
                ) {
                    multiSelectRows(
                        ScanSeasonFilter.allCases,
                        keyPath: \.seasons,
                        title: \.rawValue
                    )
                }

                if hasTaxonomyOptions {
                    filterDisclosureGroup(.taxonomy, title: "Taxonomy", summary: taxonomySummary) {
                        taxonomyDisclosureGroup(
                            .taxonomyClass,
                            title: "Class",
                            values: options.taxonomyClasses,
                            keyPath: \.taxonomyClasses
                        )
                        taxonomyDisclosureGroup(
                            .taxonomyOrder,
                            title: "Order",
                            values: options.taxonomyOrders,
                            keyPath: \.taxonomyOrders
                        )
                        taxonomyDisclosureGroup(
                            .taxonomyFamily,
                            title: "Family",
                            values: options.taxonomyFamilies,
                            keyPath: \.taxonomyFamilies
                        )
                        taxonomyDisclosureGroup(
                            .taxonomyGenus,
                            title: "Genus",
                            values: options.taxonomyGenera,
                            keyPath: \.taxonomyGenera
                        )
                    }
                }

                filterDisclosureGroup(
                    .explorePosts,
                    title: "Explore posts",
                    summary: selectedSummary(searchManager.filters.explorePostFilters, title: \.rawValue)
                ) {
                    multiSelectRows(
                        ScanExplorePostFilter.allCases,
                        keyPath: \.explorePostFilters,
                        title: \.rawValue
                    )
                }
            }
            .listSectionSpacing(12)
            .contentMargins(.top, 8, for: .scrollContent)
            .filterSheetOpaqueBackground()
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        searchManager.triggerMediumFeedback()
                        searchManager.clearFilters()
                        presentedActiveFilterCount = 0
                    }
                    .disabled(!searchManager.hasActiveFilters)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        searchManager.triggerLightFeedback()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .onAppear {
            presentedActiveFilterCount = searchManager.activeFilterCount
        }
    }

    private var sheetTitle: String {
        let count = presentedActiveFilterCount ?? searchManager.activeFilterCount
        guard count > 0 else { return "Filter scans" }
        return count == 1 ? "1 active filter" : "\(count) active filters"
    }

    @ViewBuilder
    private func filterDisclosureGroup<Content: View>(
        _ group: ScansFilterGroup,
        title: String,
        summary: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Section {
            DisclosureGroup(isExpanded: expansionBinding(for: group)) {
                content()
            } label: {
                filterGroupLabel(title: title, summary: summary)
            }
        }
    }

    @ViewBuilder
    private func nestedDisclosureGroup<Content: View>(
        _ group: ScansFilterGroup,
        title: String,
        summary: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: group)) {
            content()
        } label: {
            filterGroupLabel(title: title, summary: summary)
        }
    }

    @ViewBuilder
    private func taxonomyDisclosureGroup(
        _ group: ScansFilterGroup,
        title: String,
        values: [String],
        keyPath: WritableKeyPath<ScanLibraryFilters, Set<String>>
    ) -> some View {
        if !values.isEmpty {
            nestedDisclosureGroup(
                group,
                title: title,
                summary: selectedStringSummary(searchManager.filters[keyPath: keyPath])
            ) {
                dynamicStringRows(values, keyPath: keyPath)
            }
        }
    }

    private func filterGroupLabel(title: String, summary: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }

    private func expansionBinding(
        for group: ScansFilterGroup
    ) -> Binding<Bool> {
        Binding {
            expandedGroups.contains(group)
        } set: { isExpanded in
            searchManager.triggerSelectionFeedback()
            if isExpanded {
                expandedGroups.insert(group)
            } else {
                expandedGroups.remove(group)
            }
        }
    }

    @ViewBuilder
    private func multiSelectRows<Value: Hashable>(
        _ values: [Value],
        keyPath: WritableKeyPath<ScanLibraryFilters, Set<Value>>,
        title: KeyPath<Value, String>
    ) -> some View {
        ForEach(values, id: \.self) { value in
            filterRow(
                title: value[keyPath: title],
                isSelected: searchManager.filters[keyPath: keyPath].contains(value)
            ) {
                toggle(value, keyPath: keyPath)
            }
        }
    }

    @ViewBuilder
    private func dynamicStringRows(
        _ values: [String],
        keyPath: WritableKeyPath<ScanLibraryFilters, Set<String>>
    ) -> some View {
        ForEach(values, id: \.self) { value in
            filterRow(
                title: value,
                isSelected: searchManager.filters[keyPath: keyPath].contains(value)
            ) {
                toggleString(value, keyPath: keyPath)
            }
        }
    }

    private func filterRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            searchManager.triggerSelectionFeedback()
            action()
        } label: {
            HStack {
                Text(ScansFilterPresentation.formattedTitle(title))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private var dateSummary: String {
        ScansFilterPresentation.dateSummary(searchManager.filters)
    }

    private var naturalistSummary: String {
        ScansFilterPresentation.naturalistSummary(searchManager.filters)
    }

    private var hasTaxonomyOptions: Bool {
        ScansFilterPresentation.hasTaxonomyOptions(options)
    }

    private var taxonomySummary: String {
        ScansFilterPresentation.taxonomySummary(searchManager.filters)
    }

    private func selectedSummary<Value: Hashable>(
        _ values: Set<Value>,
        title: KeyPath<Value, String>
    ) -> String {
        selectedStringSummary(values) { value in
            value[keyPath: title]
        }
    }

    private func selectedStringSummary<Value: Hashable>(
        _ values: Set<Value>,
        title: (Value) -> String
    ) -> String {
        ScansFilterPresentation.selectedSummary(values, title: title)
    }

    private func selectedStringSummary(_ values: Set<String>) -> String {
        selectedStringSummary(values) { $0 }
    }

    private func toggle<Value: Hashable>(
        _ value: Value,
        keyPath: WritableKeyPath<ScanLibraryFilters, Set<Value>>
    ) {
        var updated = searchManager.filters
        if updated[keyPath: keyPath].contains(value) {
            updated[keyPath: keyPath].remove(value)
        } else {
            updated[keyPath: keyPath].insert(value)
        }
        searchManager.filters = updated
    }

    private func toggleString(
        _ value: String,
        keyPath: WritableKeyPath<ScanLibraryFilters, Set<String>>
    ) {
        toggle(value, keyPath: keyPath)
    }

    private func toggleDateFilter(_ filter: ScanDateFilter) {
        var updated = searchManager.filters
        if updated.dateFilters.contains(filter) {
            updated.dateFilters.remove(filter)
            if filter == .custom {
                updated.customStartDate = nil
                updated.customEndDate = nil
            }
        } else {
            updated.dateFilters.insert(filter)
            if filter == .custom {
                let now = Date()
                updated.customStartDate = updated.customStartDate ?? now
                updated.customEndDate = updated.customEndDate ?? now
            }
        }
        searchManager.filters = updated
    }

    private func customDateBinding(_ keyPath: WritableKeyPath<ScanLibraryFilters, Date?>) -> Binding<Date> {
        Binding {
            searchManager.filters[keyPath: keyPath] ?? Date()
        } set: { newValue in
            searchManager.triggerSelectionFeedback()
            var updated = searchManager.filters
            updated.dateFilters.insert(.custom)
            updated[keyPath: keyPath] = newValue
            searchManager.filters = updated
        }
    }
}
