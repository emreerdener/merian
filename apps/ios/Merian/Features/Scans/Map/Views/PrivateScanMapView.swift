import CoreLocation
import MapKit
import SwiftUI

struct PrivateScanMapView: View {
    let onOpenInsight: (String) -> Void

    @Environment(EnvironmentContextManager.self)
    private var environmentContextManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(PrivateScanMapStore.self) private var privateScanMapStore
    @Environment(\.openURL) private var openURL

    @State private var viewModel = PrivateScanMapViewModel()
    @State private var isShowingFilterSheet = false
    @State private var isShowingScanList = false
    @State private var sheetPointIDs: [String]?
    @State private var pendingInsightScanID: String?
    @State private var isResolvingLocation = false
    @State private var isLocationSettingsAlertPresented = false
    @State private var isLocationUnavailableAlertPresented = false
    @State private var locationRequestGeneration: UInt64 = 0

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
        .onAppear {
            viewModel.setViewportProjectionSuspended(false)
        }
        .onDisappear {
            viewModel.setViewportProjectionSuspended(true)
        }
        .task(id: privateScanMapStore.sensitiveResetGeneration) {
            let resetGeneration =
                privateScanMapStore.sensitiveResetGeneration
            await PrivateScanMapStartupSequence.run(
                refresh: privateScanMapStore.refresh,
                updateSnapshot: {
                    viewModel.update(
                        snapshot:
                            privateScanMapStore.snapshot.interactiveSnapshot
                    )
                },
                needsInitialCamera: { !viewModel.didSetInitialCamera },
                isCurrent: {
                    resetGeneration
                        == privateScanMapStore.sensitiveResetGeneration
                },
                requestCurrentLocation:
                    environmentContextManager.requestCurrentLocation,
                setInitialCamera: viewModel.setInitialCamera
            )
        }
        .onChange(of: privateScanMapStore.snapshot.revision) {
            viewModel.update(
                snapshot: privateScanMapStore.snapshot.interactiveSnapshot
            )
        }
        .onChange(of: privateScanMapStore.sensitiveResetGeneration) {
            viewModel.resetSensitiveState()
            sheetPointIDs = nil
            pendingInsightScanID = nil
            isShowingFilterSheet = false
            isShowingScanList = false
            locationRequestGeneration &+= 1
            isResolvingLocation = false
            isLocationSettingsAlertPresented = false
            isLocationUnavailableAlertPresented = false
        }
        .sheet(isPresented: $isShowingFilterSheet) {
            PrivateScanMapFilterSheet(
                viewModel: viewModel,
                isPresented: $isShowingFilterSheet
            )
        }
        .sheet(
            isPresented: $isShowingScanList,
            onDismiss: handleScanListDismissal
        ) {
            PrivateScanMapScanListSheet(
                points: pointsPresentedInSheet,
                isOnline: offlineQueueManager.isOnline,
                onSelectPoint: { pointID in
                    pendingInsightScanID = pointID
                    isShowingScanList = false
                },
                onReferenceImageNeeded: requestReferenceImageFallback,
                isPresented: $isShowingScanList
            )
        }
        .alert("Turn On Location", isPresented: $isLocationSettingsAlertPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Settings") {
                guard let settingsURL = URL(
                    string: UIApplication.openSettingsURLString
                ) else {
                    return
                }
                openURL(settingsURL)
            }
        } message: {
            Text("Location access lets Scan map center on your current position. Your saved scans remain available without it.")
        }
        .alert(
            "Location Unavailable",
            isPresented: $isLocationUnavailableAlertPresented
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We couldn’t determine your location right now. Your saved scan locations are still available.")
        }
    }

    private var cameraPositionBinding: Binding<MapCameraPosition> {
        Binding(
            get: { viewModel.cameraPosition },
            set: { viewModel.cameraPosition = $0 }
        )
    }

    private var mapLayer: some View {
        let isOnline = offlineQueueManager.isOnline

        return GeometryReader { geometry in
            Map(position: cameraPositionBinding) {
                if environmentContextManager.isAuthorized {
                    UserAnnotation()
                }

                ForEach(viewModel.annotations) { annotation in
                    switch annotation {
                    case .point(let point):
                        waypointAnnotation(for: point, isOnline: isOnline)
                    case .cluster(let cluster):
                        Annotation("", coordinate: cluster.coordinate, anchor: .center) {
                            Button {
                                triggerSelectionFeedback()
                                viewModel.selectPoint(nil)
                                if viewModel.focusRegion(for: cluster) != nil {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        viewModel.focus(on: cluster)
                                    }
                                } else {
                                    showScanList(
                                        pointIDs: cluster.points.map(\.id)
                                    )
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
            .accessibilityIdentifier("PrivateScanMapCanvas")
            .ignoresSafeArea(edges: .bottom)
            .onAppear {
                viewModel.updateViewportSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, size in
                viewModel.updateViewportSize(size)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                viewModel.updateVisibleRegion(context.region)
            }
        }
    }

    private func waypointAnnotation(
        for point: PrivateScanMapPoint,
        isOnline: Bool
    ) -> some MapContent {
        Annotation("", coordinate: point.coordinate, anchor: .bottom) {
            Button {
                triggerSelectionFeedback()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewModel.selectPoint(point.id)
                }
            } label: {
                PrivateScanMapWaypoint(
                    point: point,
                    isSelected: viewModel.selectedPointID == point.id,
                    showsThumbnail: viewModel.showsThumbnailWaypoints,
                    isOnline: isOnline,
                    onReferenceImageNeeded: {
                        requestReferenceImageFallback(for: point.id)
                    }
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
            } else if viewModel.didSetInitialCamera,
                      viewModel.filteredPoints.isEmpty {
                mapStateBanner(
                    icon: "line.3.horizontal.decrease.circle",
                    message: "No scans match these filters.",
                    actionTitle: "Reset filters",
                    action: viewModel.clearFilters
                )
            } else if viewModel.didSetInitialCamera,
                      !viewModel.filteredPoints.isEmpty,
                      !viewModel.isProjectingViewport,
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
        .animation(
            .easeInOut(duration: 0.18),
            value: viewModel.visiblePoints.isEmpty
        )
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
                    isSelected: !viewModel.hasActiveFilters,
                    action: viewModel.clearFilters
                )

                ForEach(viewModel.categoryCounts) { categoryCount in
                    filterPill(
                        title: categoryCount.category.title,
                        systemImage: nil,
                        isSelected: viewModel.selectedCategories.contains(
                            categoryCount.category
                        )
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
            triggerSelectionFeedback()
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
            .foregroundStyle(
                isSelected ? Color(uiColor: .systemBackground) : Color.primary
            )
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
                    isOnline: offlineQueueManager.isOnline,
                    onOpen: { openInsight(scanID: selectedPoint.id) },
                    onReferenceImageNeeded: {
                        requestReferenceImageFallback(for: selectedPoint.id)
                    }
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
            triggerSelectionFeedback()
            showScanList(pointIDs: nil)
        } label: {
            Text(PrivateScanMapPresentation.discoveriesInViewLabel(
                count: viewModel.visiblePoints.count
            ))
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
            triggerSelectionFeedback()
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

    private var pointsPresentedInSheet: [PrivateScanMapPoint] {
        guard let sheetPointIDs else { return viewModel.visiblePoints }
        let ids = Set(sheetPointIDs)
        return viewModel.filteredPoints.filter { ids.contains($0.id) }
    }

    private func showScanList(pointIDs: [String]?) {
        sheetPointIDs = pointIDs
        isShowingScanList = true
    }

    private func handleScanListDismissal() {
        sheetPointIDs = nil
        guard let pendingInsightScanID else { return }
        let resetGeneration = privateScanMapStore.sensitiveResetGeneration
        self.pendingInsightScanID = nil

        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  resetGeneration
                    == privateScanMapStore.sensitiveResetGeneration else {
                return
            }
            openInsight(scanID: pendingInsightScanID)
        }
    }

    private func openInsight(scanID: String) {
        onOpenInsight(scanID)
    }

    private func requestReferenceImageFallback(for scanID: String) {
        privateScanMapStore.requestReferenceImageFallback(for: scanID)
    }

    private func recenterOnCurrentLocation() async {
        guard !isResolvingLocation else { return }
        locationRequestGeneration &+= 1
        let requestGeneration = locationRequestGeneration
        let resetGeneration = privateScanMapStore.sensitiveResetGeneration
        isResolvingLocation = true
        defer {
            if requestGeneration == locationRequestGeneration {
                isResolvingLocation = false
            }
        }

        let result = await PrivateScanMapLocationRequestSequence.run(
            isCurrent: {
                requestGeneration == locationRequestGeneration
                    && resetGeneration
                        == privateScanMapStore.sensitiveResetGeneration
            },
            requestCurrentLocation:
                environmentContextManager.requestCurrentLocation
        )

        switch result {
        case .invalidated:
            return
        case .location(let location):
            withAnimation(.easeInOut(duration: 0.25)) {
                viewModel.recenter(on: location)
            }
        case .unavailable:
            switch environmentContextManager.locationAuthorizationStatus {
            case .denied:
                isLocationSettingsAlertPresented = true
            default:
                isLocationUnavailableAlertPresented = true
            }
        }
    }

    private func triggerSelectionFeedback() {
        hapticManager.triggerSelectionPulse()
    }
}
