import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct PrivateScanMapView: View {
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse)
    private var allScans: [LocalScanRecord]

    @Environment(EnvironmentContextManager.self)
    private var environmentContextManager
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.openURL) private var openURL

    @State private var viewModel = PrivateScanMapViewModel()
    @State private var isShowingFilterSheet = false
    @State private var isShowingScanList = false
    @State private var sheetPointIDs: [String]?
    @State private var selectedInsightRoute: ScanInsightRoute?
    @State private var pendingInsightScanID: String?
    @State private var ignoresNextBackgroundTap = false
    @State private var continuousZoomLevel: Double?
    @State private var isResolvingLocation = false
    @State private var isLocationSettingsAlertPresented = false
    @State private var isLocationUnavailableAlertPresented = false
    @State private var isScanUnavailableAlertPresented = false

    var body: some View {
        ZStack {
            mapLayer

            topChrome
            bottomChrome

            if !viewModel.didSetInitialCamera {
                ProgressView()
                    .controlSize(.large)
                    .padding(18)
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .accessibilityLabel("Finding your location")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Scan map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .bottomBar)
        .task {
            refreshSnapshot()
            let currentLocation = await environmentContextManager.requestCurrentLocation()
            guard !Task.isCancelled else { return }
            viewModel.setInitialCamera(currentLocation: currentLocation)
        }
        .task(id: sourceIdentity) {
            refreshSnapshot()
        }
        .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
            guard case .scanLibraryChanged = event else { return }
            refreshSnapshot()
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            filterSheet
        }
        .sheet(
            isPresented: $isShowingScanList,
            onDismiss: handleScanListDismissal
        ) {
            scanListSheet
        }
        .navigationDestination(item: $selectedInsightRoute) { route in
            InsightSheetView(
                isPresented: Binding(
                    get: { selectedInsightRoute != nil },
                    set: { if !$0 { selectedInsightRoute = nil } }
                ),
                initialScanId: route.scanId,
                inferenceEngine: inferenceEngine,
                presentationStyle: .embeddedInScansLibrary
            )
        }
        .alert("Turn On Location", isPresented: $isLocationSettingsAlertPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Settings") {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                openURL(settingsURL)
            }
        } message: {
            Text("Location access lets Scan map center on your current position. Your saved scans remain available without it.")
        }
        .alert("Location Unavailable", isPresented: $isLocationUnavailableAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn’t determine your location right now. Your saved scan locations are still available.")
        }
        .alert("Scan Unavailable", isPresented: $isScanUnavailableAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This scan is no longer in your library.")
        }
    }

    private var cameraPositionBinding: Binding<MapCameraPosition> {
        Binding(
            get: { viewModel.cameraPosition },
            set: { viewModel.cameraPosition = $0 }
        )
    }

    private var effectiveZoomLevel: Double {
        continuousZoomLevel ?? viewModel.effectiveZoomLevel
    }

    private var mapLayer: some View {
        GeometryReader { geometry in
            Map(position: cameraPositionBinding) {
                if environmentContextManager.isAuthorized {
                    UserAnnotation()
                }

                ForEach(viewModel.annotations) { annotation in
                    switch annotation {
                    case .point(let point):
                        waypointAnnotation(for: point)
                    case .cluster(let cluster):
                        Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                            Button {
                                registerAnnotationTap()
                                HapticManager.shared.triggerSelectionPulse()
                                if viewModel.focusRegion(for: cluster) != nil {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        viewModel.focus(on: cluster)
                                    }
                                } else {
                                    showScanList(pointIDs: cluster.points.map(\.id))
                                }
                            } label: {
                                PrivateScanMapClusterBubble(count: cluster.count)
                            }
                            .buttonStyle(.plain)
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.standard)
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                viewModel.updateViewportSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, size in
                viewModel.updateViewportSize(size)
            }
            .onTapGesture {
                dismissSelectedPointIfNeeded()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                let longitudeDelta = max(context.region.span.longitudeDelta, 0.000_01)
                continuousZoomLevel = max(0, min(log2(360 / longitudeDelta), 20))
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.updateVisibleRegion(context.region)
                continuousZoomLevel = nil
            }
        }
    }

    private func waypointAnnotation(
        for point: PrivateScanMapPoint
    ) -> some MapContent {
        Annotation("", coordinate: point.coordinate, anchor: .bottom) {
            Button {
                registerAnnotationTap()
                HapticManager.shared.triggerSelectionPulse()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.selectPoint(point.id)
                }
            } label: {
                PrivateScanMapWaypoint(
                    point: point,
                    isSelected: viewModel.selectedPointID == point.id,
                    showsThumbnail: effectiveZoomLevel >= 11.5
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("PrivateScanMapPoint-\(point.id)")
        }
        .annotationTitles(.hidden)
    }

    private var topChrome: some View {
        VStack(spacing: 8) {
            filterBar

            if viewModel.didSetInitialCamera, viewModel.points.isEmpty {
                mapStateBanner(
                    icon: "mappin.slash",
                    message: "Your mapped scans will appear here.",
                    actionTitle: nil,
                    action: {}
                )
            } else if viewModel.didSetInitialCamera, viewModel.filteredPoints.isEmpty {
                mapStateBanner(
                    icon: "line.3.horizontal.decrease.circle",
                    message: "No scans match these filters.",
                    actionTitle: "Reset filters",
                    action: viewModel.clearFilters
                )
            } else if viewModel.didSetInitialCamera,
                      !viewModel.filteredPoints.isEmpty,
                      viewModel.visiblePoints.isEmpty {
                mapStateBanner(
                    icon: "map",
                    message: "No scans are visible in this area.",
                    actionTitle: "Show scans",
                    action: viewModel.showAllFilteredScans
                )
                .accessibilityIdentifier("PrivateScanMapShowScansBanner")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.18), value: viewModel.visiblePoints.isEmpty)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill(
                    title: viewModel.hasActiveFilters
                        ? "Filters \(viewModel.activeFilterCount.formatted())"
                        : "Filters",
                    systemImage: "line.3.horizontal.decrease",
                    isSelected: viewModel.hasActiveFilters
                ) {
                    isShowingFilterSheet = true
                }
                .accessibilityLabel("Map filters")
                .accessibilityIdentifier("PrivateScanMapFilters")

                filterPill(
                    title: "All",
                    systemImage: nil,
                    isSelected: !viewModel.hasActiveFilters
                ) {
                    viewModel.clearFilters()
                }

                ForEach(viewModel.categoryCounts) { categoryCount in
                    filterPill(
                        title: categoryCount.category.title,
                        systemImage: nil,
                        isSelected: viewModel.selectedCategories.contains(categoryCount.category)
                    ) {
                        viewModel.toggleCategory(categoryCount.category)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private func filterPill(
        title: String,
        systemImage: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.primary)
            .background {
                if isSelected {
                    Capsule().fill(Color.primary)
                } else {
                    Capsule().fill(.regularMaterial)
                }
            }
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func mapStateBanner(
        icon: String,
        message: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote)
                .fontWeight(.medium)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 4)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            if let selectedPoint = viewModel.selectedPoint {
                PrivateScanMapPreviewCard(
                    point: selectedPoint,
                    onOpen: { openInsight(scanID: selectedPoint.id) }
                )
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 12) {
                countButton

                Spacer(minLength: 16)

                locateButton
            }
            .padding(.horizontal, 30)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(
            .spring(response: 0.28, dampingFraction: 0.84),
            value: viewModel.selectedPointID
        )
    }

    private var countButton: some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            showScanList(pointIDs: nil)
        } label: {
            Text(discoveriesInViewLabel(count: viewModel.visiblePoints.count))
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("PrivateScanMapVisibleCount")
    }

    private var locateButton: some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            Task { await recenterOnCurrentLocation() }
        } label: {
            Group {
                if isResolvingLocation {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "location")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .background(.regularMaterial)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isResolvingLocation)
        .accessibilityLabel("Locate me")
        .accessibilityIdentifier("PrivateScanMapLocate")
    }

    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    filterSectionTitle("Species")

                    Button {
                        viewModel.clearCategories()
                    } label: {
                        FilterSheetSelectionRow(
                            title: "All species",
                            subtitle: scanCountLabel(viewModel.points.count),
                            systemImage: "map",
                            isSelected: viewModel.selectedCategories.isEmpty
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.categoryCounts) { categoryCount in
                        Button {
                            viewModel.toggleCategory(categoryCount.category)
                        } label: {
                            FilterSheetSelectionRow(
                                title: categoryCount.category.title,
                                subtitle: scanCountLabel(categoryCount.count),
                                systemImage: categoryCount.category.privateMapSymbolName,
                                isSelected: viewModel.selectedCategories.contains(categoryCount.category)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(
                            "PrivateScanMapCategory-\(categoryCount.category.rawValue)"
                        )
                    }

                    filterSectionTitle("Media type")
                        .padding(.top, 8)

                    Button {
                        viewModel.clearMediaFilters()
                    } label: {
                        FilterSheetSelectionRow(
                            title: "All media",
                            subtitle: scanCountLabel(viewModel.points.count),
                            systemImage: "rectangle.stack",
                            isSelected: viewModel.selectedMediaFilters.isEmpty
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(viewModel.mediaCounts) { mediaCount in
                        Button {
                            viewModel.toggleMediaFilter(mediaCount.mediaFilter)
                        } label: {
                            FilterSheetSelectionRow(
                                title: mediaCount.mediaFilter.rawValue,
                                subtitle: scanCountLabel(mediaCount.count),
                                systemImage: mediaCount.mediaFilter.privateMapSymbolName,
                                isSelected: viewModel.selectedMediaFilters.contains(
                                    mediaCount.mediaFilter
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Map filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        viewModel.clearFilters()
                    }
                    .disabled(!viewModel.hasActiveFilters)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private var scanListSheet: some View {
        NavigationStack {
            Group {
                if pointsPresentedInSheet.isEmpty {
                    ContentUnavailableView(
                        "No scans in view",
                        systemImage: "map",
                        description: Text("Pan the map or choose Show scans to find your saved locations.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(pointsPresentedInSheet) { point in
                                Button {
                                    pendingInsightScanID = point.id
                                    isShowingScanList = false
                                } label: {
                                    PrivateScanMapSheetRow(point: point)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("PrivateScanMapSheetRow-\(point.id)")
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Your scans")
                            .font(.headline)
                        Label("Private", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("PrivateScanMapSheetHeader")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isShowingScanList = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    private var pointsPresentedInSheet: [PrivateScanMapPoint] {
        guard let sheetPointIDs else { return viewModel.visiblePoints }
        let ids = Set(sheetPointIDs)
        return viewModel.filteredPoints.filter { ids.contains($0.id) }
    }

    private var sourceIdentity: String {
        PrivateScanMapSnapshot.sourceIdentity(for: allScans)
    }

    private func refreshSnapshot() {
        viewModel.update(snapshot: PrivateScanMapSnapshot(records: allScans))
    }

    private func showScanList(pointIDs: [String]?) {
        sheetPointIDs = pointIDs
        isShowingScanList = true
    }

    private func handleScanListDismissal() {
        sheetPointIDs = nil
        guard let pendingInsightScanID else { return }
        self.pendingInsightScanID = nil

        Task { @MainActor in
            await Task.yield()
            openInsight(scanID: pendingInsightScanID)
        }
    }

    private func openInsight(scanID: String) {
        guard let record = allScans.first(where: { $0.id == scanID }) else {
            isScanUnavailableAlertPresented = true
            return
        }
        inferenceEngine.load(from: record)
        selectedInsightRoute = ScanInsightRoute(scanId: scanID)
    }

    private func registerAnnotationTap() {
        ignoresNextBackgroundTap = true
        Task { @MainActor in
            await Task.yield()
            ignoresNextBackgroundTap = false
        }
    }

    private func dismissSelectedPointIfNeeded() {
        guard !ignoresNextBackgroundTap, viewModel.selectedPointID != nil else {
            return
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            viewModel.selectPoint(nil)
        }
    }

    private func recenterOnCurrentLocation() async {
        guard !isResolvingLocation else { return }
        isResolvingLocation = true
        defer { isResolvingLocation = false }

        if let location = await environmentContextManager.requestCurrentLocation() {
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.recenter(on: location)
            }
            return
        }

        switch environmentContextManager.locationAuthorizationStatus {
        case .denied:
            isLocationSettingsAlertPresented = true
        default:
            isLocationUnavailableAlertPresented = true
        }
    }

    private func filterSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private func discoveriesInViewLabel(count: Int) -> String {
        let noun = count == 1 ? "discovery" : "discoveries"
        return "\(count.formatted()) \(noun) in view"
    }

    private func scanCountLabel(_ count: Int) -> String {
        let noun = count == 1 ? "scan" : "scans"
        return "\(count.formatted()) \(noun)"
    }
}

private struct PrivateScanMapPreviewCard: View {
    let point: PrivateScanMapPoint
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ScanThumbnail(
                imagePath: point.thumbnail.imagePath,
                fallbackImageUrl: point.thumbnail.fallbackImageUrl,
                audioPath: point.thumbnail.audioPath,
                hasVideo: point.thumbnail.hasVideo,
                hasAudio: point.thumbnail.hasAudio,
                prefersReferenceForAudio: true,
                maxDimension: 180,
                placeholderStyle: point.thumbnail.placeholderStyle
            )
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(point.privateMapDisplayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(point.scientificName)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(point.privateMapMetadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("View scan", action: onOpen)
                .font(.footnote)
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("PrivateScanMapPreview")
    }
}

private struct PrivateScanMapSheetRow: View {
    let point: PrivateScanMapPoint

    var body: some View {
        HStack(spacing: 12) {
            ScanThumbnail(
                imagePath: point.thumbnail.imagePath,
                fallbackImageUrl: point.thumbnail.fallbackImageUrl,
                audioPath: point.thumbnail.audioPath,
                hasVideo: point.thumbnail.hasVideo,
                hasAudio: point.thumbnail.hasAudio,
                prefersReferenceForAudio: true,
                maxDimension: 180,
                placeholderStyle: point.thumbnail.placeholderStyle
            )
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(point.privateMapDisplayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(point.scientificName)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(point.privateMapMetadata)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension PrivateScanMapPoint {
    var privateMapDisplayName: String {
        let trimmed = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? scientificName : trimmed
    }

    var privateMapMetadata: String {
        let date = timestamp.formatted(date: .abbreviated, time: .omitted)
        guard let locationName,
              !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return date
        }
        return "\(locationName) · \(date)"
    }
}

private extension SearchCategoryBucket {
    var privateMapSymbolName: String {
        switch self {
        case .plants: return "leaf"
        case .fungi: return "circle.hexagongrid"
        case .insects: return "ant"
        case .birds: return "bird"
        case .mammals: return "pawprint"
        case .reptiles: return "lizard"
        case .other: return "sparkles"
        }
    }
}

private extension ScanMediaFilter {
    var privateMapSymbolName: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        }
    }
}
