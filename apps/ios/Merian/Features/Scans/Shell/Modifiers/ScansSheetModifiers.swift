import SwiftData
import SwiftUI
import UIKit

struct ScansSheetModifiers: ViewModifier {
    @Bindable var searchManager: ScansManager
    @Binding var activeTab: ScansTab
    @Binding var isSearchFocused: Bool
    
    @Binding var showNewCollectionAlert: Bool
    @Binding var newCollectionName: String
    
    @Binding var scanToDelete: String?
    @Binding var showDeleteConfirmation: Bool
    @Binding var showBatchDeleteConfirmation: Bool
    @Binding var showSelectionLimitAlert: Bool
    
    @Binding var toastMessage: String?
    @Binding var isDownloading: Bool
    
    let dismiss: DismissAction
    let modelContext: ModelContext
    let onBatchDelete: () -> Void
    var onCollectionCreated: ((ScanCollection) -> Void)?
    
    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: activeTab) { _, newValue in
                if !searchManager.searchQuery.isEmpty {
                    searchManager.searchQuery = ""
                    isSearchFocused = false
                    if newValue == .library {
                        searchManager.performSearch(query: "")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchManager.searchQuery,
                isPresented: $isSearchFocused,
                placement: .toolbar,
                prompt: activeTab == .library ? "Search scans" : "Search collections"
            )
            .onChange(of: searchManager.searchQuery) { _, newValue in
                if activeTab == .library {
                    searchManager.performSearch(query: newValue)
                }
            }
            .newCollectionAlert(
                isPresented: $showNewCollectionAlert,
                newCollectionName: $newCollectionName,
                modelContext: modelContext,
                onCreated: { onCollectionCreated?($0) }
            )
            .scanDeletionDialog(
                isPresented: $showDeleteConfirmation,
                scanId: scanToDelete,
                modelContext: modelContext
            ) {
                scanToDelete = nil
            }
            .alert(
                "Delete \(searchManager.selectedScans.count) selected scans?",
                isPresented: $showBatchDeleteConfirmation
            ) {
                Button("Delete permanently", role: .destructive) {
                    onBatchDelete()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently removes these discoveries and their visuals. Any published Explore posts, likes, and comments linked to them will also be permanently removed.")
            }
            .alert(
                "Selection limit reached",
                isPresented: $showSelectionLimitAlert
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You can only select up to 20 items at a time to ensure optimal system performance during export and deletion workloads.")
            }
            .overlay(alignment: .bottom) {
                if let message = toastMessage {
                    Text(message)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .adaptiveToastSurface(
                            in: Capsule(),
                            shadowRadius: 10,
                            shadowY: 5
                        )
                        .padding(.bottom, 60)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(100)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isDownloading {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Downloading...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
    }
}

private extension View {
    func filterSheetOpaqueBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(FilterSheetStyle.background)
    }
}

private enum FilterSheetStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
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
                    summary: formattedFilterTitle(searchManager.sortOption.rawValue)
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
                    summary: formattedFilterTitle(searchManager.activeCategoryFilter)
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
                        HapticManager.shared.triggerMediumPulse()
                        searchManager.clearFilters()
                        presentedActiveFilterCount = 0
                    }
                    .disabled(!searchManager.hasActiveFilters)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticManager.shared.triggerLightImpact(intensity: 0.5)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(FilterSheetStyle.background)
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

    private func expansionBinding(for group: ScansFilterGroup) -> Binding<Bool> {
        Binding {
            expandedGroups.contains(group)
        } set: { isExpanded in
            HapticManager.shared.triggerSelectionPulse()
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
            HapticManager.shared.triggerSelectionPulse()
            action()
        } label: {
            HStack {
                Text(formattedFilterTitle(title))
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

    private func formattedFilterTitle(_ title: String) -> String {
        let normalized = title
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstCharacter = normalized.first else { return normalized }
        return firstCharacter.uppercased() + String(normalized.dropFirst())
    }

    private var dateSummary: String {
        let filters = searchManager.filters.dateFilters

        if filters.isEmpty {
            return "None"
        }

        if filters.count == 1, filters.contains(.custom) {
            return "Custom range"
        }

        return selectedSummary(filters, title: \.rawValue)
    }

    private var naturalistSummary: String {
        let count = (searchManager.filters.isInvasive ? 1 : 0)
            + searchManager.filters.ecologyFilters.count
            + searchManager.filters.hazardTypes.count
            + searchManager.filters.conservationStatuses.count
            + searchManager.filters.lifeStages.count

        if count == 0 {
            return "None"
        }

        if count == 1 {
            if searchManager.filters.isInvasive {
                return "Invasive"
            }

            return selectedNaturalistValueSummary
        }

        return "\(count) selected"
    }

    private var selectedNaturalistValueSummary: String {
        if let ecology = searchManager.filters.ecologyFilters.first {
            return formattedFilterTitle(ecology.rawValue)
        }

        if let hazardType = searchManager.filters.hazardTypes.first {
            return formattedFilterTitle(hazardType)
        }

        if let conservationStatus = searchManager.filters.conservationStatuses.first {
            return formattedFilterTitle(conservationStatus)
        }

        if let lifeStage = searchManager.filters.lifeStages.first {
            return formattedFilterTitle(lifeStage)
        }

        return "None"
    }

    private var hasTaxonomyOptions: Bool {
        !options.taxonomyClasses.isEmpty
            || !options.taxonomyOrders.isEmpty
            || !options.taxonomyFamilies.isEmpty
            || !options.taxonomyGenera.isEmpty
    }

    private var taxonomySummary: String {
        let count = searchManager.filters.taxonomyClasses.count
            + searchManager.filters.taxonomyOrders.count
            + searchManager.filters.taxonomyFamilies.count
            + searchManager.filters.taxonomyGenera.count

        if count == 0 {
            return "None"
        }

        if count == 1 {
            return selectedTaxonomyValueSummary
        }

        return "\(count) selected"
    }

    private var selectedTaxonomyValueSummary: String {
        if let taxonomyClass = searchManager.filters.taxonomyClasses.first {
            return formattedFilterTitle(taxonomyClass)
        }

        if let taxonomyOrder = searchManager.filters.taxonomyOrders.first {
            return formattedFilterTitle(taxonomyOrder)
        }

        if let taxonomyFamily = searchManager.filters.taxonomyFamilies.first {
            return formattedFilterTitle(taxonomyFamily)
        }

        if let taxonomyGenus = searchManager.filters.taxonomyGenera.first {
            return formattedFilterTitle(taxonomyGenus)
        }

        return "None"
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
        if values.isEmpty {
            return "None"
        }

        if values.count == 1, let value = values.first {
            return formattedFilterTitle(title(value))
        }

        return "\(values.count) selected"
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
            HapticManager.shared.triggerSelectionPulse()
            var updated = searchManager.filters
            updated.dateFilters.insert(.custom)
            updated[keyPath: keyPath] = newValue
            searchManager.filters = updated
        }
    }
}
