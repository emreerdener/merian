import CoreLocation
import MapKit
import SwiftUI

struct PrivateScanMapView: View {
    private struct StartupIdentity: Equatable {
        let resetGeneration: UInt64
        let isSearching: Bool
        let isLocating: Bool
    }

    let onOpenInsight: (String) -> Void

    @Environment(EnvironmentContextManager.self)
    private var environmentContextManager
    @Environment(HapticManager.self) private var hapticManager
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(PrivateScanMapStore.self) private var privateScanMapStore
    @Environment(AppSettings.self) private var appSettings
    @Environment(SupabaseManager.self) private var mapAuth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var mapScope
    @State private var mapNavigation = MapNavigationModel()

    @State private var viewModel = PrivateScanMapViewModel()
    @State private var isShowingFilterSheet = false
    @State private var isShowingScanList = false
    @State private var sheetPointIDs: [String]?
    @State private var pendingInsightScanID: String?

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
        .overlay(alignment: .bottomTrailing) {
            MapScaleView(anchorEdge: .trailing, scope: mapScope)
                .mapControlVisibility(.visible)
                .padding(.trailing, 12)
                .padding(.bottom, 4)
                .allowsHitTesting(false)
        }
        .mapScope(mapScope)
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
        .task(id: StartupIdentity(
            resetGeneration: privateScanMapStore.sensitiveResetGeneration,
            isSearching: mapNavigation.isSearchPresented,
            isLocating: mapNavigation.isLocating
        )) {
            guard !mapNavigation.isSearchPresented, !mapNavigation.isLocating else { return }
            let resetGeneration =
                privateScanMapStore.sensitiveResetGeneration
            let navigationGeneration = mapNavigation.generation
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
                    resetGeneration == privateScanMapStore.sensitiveResetGeneration
                        && navigationGeneration == mapNavigation.generation
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
            mapNavigation.reset()
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
        .modifier(MapNavigationPresentation(
            navigation: mapNavigation,
            owner: mapAuth.currentUser?.id,
            onDestination: { viewModel.navigate(to: $0.item, region: $0.region) }
        ))
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
            Map(position: cameraPositionBinding, scope: mapScope) {
                if environmentContextManager.isAuthorized {
                    UserAnnotation(anchor: .bottom) {
                        MapUserLocationPin()
                    }
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
            .mapStyle(appSettings.mapAppearance == .satellite ? .imagery : .standard)
            .mapControls {
                MapCompass()
            }
            .accessibilityIdentifier("PrivateScanMapCanvas")
            .ignoresSafeArea(edges: .vertical)
            .transparentTopToolbar()
            .onAppear {
                viewModel.updateViewportSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, size in
                viewModel.updateViewportSize(size)
            }
            .onMapCameraChange(frequency: .continuous) { context in
                if viewModel.cameraPosition.positionedByUser {
                    viewModel.userDidMoveCamera(region: context.region)
                    mapNavigation.cancelNavigation()
                }
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
        .transparentTopToolbar()
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

            MapBottomControlRow {
                countButton
            } controls: {
                navigationToolbar
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 28)
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
            MapCountPillLabel(
                fullLabel: PrivateScanMapPresentation.discoveriesInViewLabel(count: viewModel.visiblePoints.count),
                compactLabel: "\(viewModel.visiblePoints.count.formatted()) in view"
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("PrivateScanMapVisibleCount")
    }

    private var navigationToolbar: some View {
        MapNavigationToolbar(
            appearance: appSettings.mapAppearance,
            isLocating: mapNavigation.isLocating,
            identifierPrefix: "PrivateScanMap",
            onToggleStyle: {
                appSettings.mapAppearance = appSettings.mapAppearance == .satellite ? .standard : .satellite
                triggerSelectionFeedback()
            },
            onSearch: {
                let owner = mapAuth.currentUser?.id
                let resetGeneration = privateScanMapStore.sensitiveResetGeneration
                mapNavigation.openSearch(owner: owner) {
                    owner == mapAuth.currentUser?.id
                        && resetGeneration == privateScanMapStore.sensitiveResetGeneration
                }
            },
            onLocate: {
                triggerSelectionFeedback()
                let owner = mapAuth.currentUser?.id
                let resetGeneration = privateScanMapStore.sensitiveResetGeneration
                mapNavigation.locate(
                    request: environmentContextManager.requestCurrentLocation,
                    authorization: { environmentContextManager.locationAuthorizationStatus },
                    isCurrent: {
                        owner == mapAuth.currentUser?.id
                            && resetGeneration == privateScanMapStore.sensitiveResetGeneration
                    },
                    onLocation: { location in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            viewModel.recenter(on: location)
                        }
                    }
                )
            }
        )
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

    private func triggerSelectionFeedback() {
        hapticManager.triggerSelectionPulse()
    }
}
