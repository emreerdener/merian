import SwiftUI

struct TaxonomyTreeCanvasView: View {
    let onOpenSpecies: (SpeciesDictionaryRoute) -> Void
    let showsNavigationTitle: Bool

    @StateObject private var viewModel = TaxonomyTreeCanvasViewModel()

    init(
        showsNavigationTitle: Bool = true,
        onOpenSpecies: @escaping (SpeciesDictionaryRoute) -> Void
    ) {
        self.showsNavigationTitle = showsNavigationTitle
        self.onOpenSpecies = onOpenSpecies
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.graph.nodes.isEmpty {
                stateWithScopeFilter { loadingState }
            } else if let errorMessage = viewModel.errorMessage, viewModel.graph.nodes.isEmpty {
                stateWithScopeFilter { errorState(message: errorMessage) }
            } else if viewModel.graph.nodes.isEmpty {
                stateWithScopeFilter { emptyState }
            } else {
                canvas
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .modifier(TaxonomyTreeCanvasTitleModifier(isEnabled: showsNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.selectedTreeScope) {
            await viewModel.loadTree()
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let visibleNodeIDs = viewModel.visibleNodeIDs
            let layout = TaxonomyConstellationLayout.make(
                graph: viewModel.graph,
                visibleNodeIDs: visibleNodeIDs,
                focusedNodeID: viewModel.focusedNodeID,
                minimumSize: proxy.size
            )
            let selectedNode = viewModel.selectedNode
            let spotlightIDs = viewModel.spotlightNodeIDs
            let visibleRect = viewModel.visibleContentRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ZStack(alignment: .topLeading) {
                    TaxonomyConstellationStarfield()
                        .frame(width: layout.size.width, height: layout.size.height)

                    TaxonomyConstellationClusterHalos(
                        graph: viewModel.graph,
                        positions: layout.positions,
                        visibleNodeIDs: visibleNodeIDs
                    )
                    .frame(width: layout.size.width, height: layout.size.height)

                    TaxonomyConstellationEdgesCanvas(
                        graph: viewModel.graph,
                        positions: layout.positions,
                        spotlightIDs: spotlightIDs,
                        selectedNodeID: viewModel.selectedNodeID
                    )
                    .frame(width: layout.size.width, height: layout.size.height)

                    ForEach(viewModel.graph.nodes.filter { node in
                        guard visibleNodeIDs.contains(node.id), let position = layout.positions[node.id] else {
                            return false
                        }
                        return visibleRect.insetBy(dx: -140, dy: -140).contains(position)
                    }) { node in
                        TaxonomyConstellationNodeView(
                            node: node,
                            scale: viewModel.scale,
                            branchTint: TaxonomyConstellationPalette.tint(for: node),
                            isSelected: selectedNode?.id == node.id,
                            isSpotlighted: spotlightIDs.isEmpty || spotlightIDs.contains(node.id),
                            isFocused: viewModel.focusedNodeID == node.id,
                            action: {
                                viewModel.select(node)
                            }
                        )
                        .position(layout.positions[node.id] ?? .zero)
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                .scaleEffect(viewModel.scale, anchor: .topLeading)
                .offset(viewModel.currentOffset)
                .contentShape(Rectangle())
                .gesture(viewModel.dragGesture)
                .animation(.snappy(duration: 0.22), value: viewModel.focusedNodeID)
                .animation(.snappy(duration: 0.22), value: viewModel.selectedNodeID)

                if viewModel.breadcrumbText != nil {
                    TaxonomyTreeControlBar(
                        breadcrumb: viewModel.breadcrumbText,
                        leadingInset: 30
                    )
                    .frame(width: proxy.size.width, alignment: .topLeading)
                    .padding(.top, 58)
                    .padding(.bottom, 12)
                }

                TaxonomyTreeScopeFilterBar(
                    activeScope: viewModel.selectedTreeScope,
                    onSelection: { scope in
                        viewModel.selectTreeScope(scope)
                    }
                )

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 82)
                        .padding(.trailing, 16)
                }

                TaxonomyTreeFloatingControls(
                    canClearFocus: viewModel.focusedNodeID != nil || viewModel.selectedNodeID != nil,
                    onZoomOut: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.zoom(by: 0.86, viewportSize: proxy.size)
                        }
                    },
                    onZoomIn: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.zoom(by: 1.18, viewportSize: proxy.size)
                        }
                    },
                    onReset: {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.resetView(positions: layout.positions, viewportSize: proxy.size)
                        }
                    }
                )
                .position(
                    x: max(58, proxy.size.width - 42),
                    y: max(220, proxy.size.height - 120)
                )
                .zIndex(4)

                if let selectedNode {
                    TaxonomyTreeSelectionDrawer(
                        node: selectedNode,
                        isFocused: viewModel.focusedNodeID == selectedNode.id,
                        onFocus: {
                            withAnimation(.snappy(duration: 0.22)) {
                                viewModel.focus(on: selectedNode.id)
                            }
                        },
                        onClearFocus: {
                            viewModel.clearFocus()
                        },
                        onOpen: { route in
                            onOpenSpecies(route)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .simultaneousGesture(viewModel.magnificationGesture(in: proxy.size))
            .onAppear {
                viewModel.positionInitialViewportIfNeeded(positions: layout.positions, viewportSize: proxy.size)
            }
            .onChange(of: layout.positions) { _, positions in
                if let focusedNodeID = viewModel.focusedNodeID {
                    viewModel.center(nodeID: focusedNodeID, positions: positions, viewportSize: proxy.size)
                } else {
                    viewModel.positionInitialViewportIfNeeded(positions: positions, viewportSize: proxy.size)
                }
            }
            .onChange(of: viewModel.focusedNodeID) { _, focusedNodeID in
                guard let focusedNodeID else { return }
                viewModel.center(nodeID: focusedNodeID, positions: layout.positions, viewportSize: proxy.size)
            }
            .onChange(of: proxy.size) { _, viewportSize in
                viewModel.positionInitialViewportIfNeeded(positions: layout.positions, viewportSize: viewportSize)
            }
        }
    }

    private func stateWithScopeFilter<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .topLeading) {
            content()

            TaxonomyTreeScopeFilterBar(
                activeScope: viewModel.selectedTreeScope,
                onSelection: { scope in
                    viewModel.selectTreeScope(scope)
                }
            )
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Mapping constellation")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        switch viewModel.selectedTreeScope {
        case .allSpecies:
            ContentUnavailableView(
                "No dictionary taxonomy yet",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("The public taxonomy constellation will appear here as species are added.")
            )
        case .myScans:
            ContentUnavailableView(
                "No scanned taxonomy yet",
                systemImage: "point.3.connected.trianglepath.dotted",
                description: Text("The constellation appears after your biological scans are matched to dictionary species.")
            )
        }
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label(errorTitle, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await viewModel.loadTree(force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var errorTitle: String {
        switch viewModel.selectedTreeScope {
        case .allSpecies: "Public tree unavailable"
        case .myScans: "Scanned tree unavailable"
        }
    }
}

@MainActor
final class TaxonomyTreeCanvasViewModel: ObservableObject {
    @Published private(set) var graph: TaxonomyTreeGraph = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedTreeScope: SpeciesDictionaryTreeScope = .allSpecies
    @Published var selectedNodeID: String?
    @Published var focusedNodeID: String?
    @Published var offset: CGSize = .zero
    @Published var dragOffset: CGSize = .zero
    @Published var scale: CGFloat = 0.82
    @Published var baseScale: CGFloat = 0.82

    private let minScale: CGFloat = 0.56
    private let maxScale: CGFloat = 2.25
    private let topRootViewportY: CGFloat = 96
    private var magnifyStartScale: CGFloat?
    private var magnifyStartOffset: CGSize = .zero
    private var hasPositionedInitialViewport = false
    private var cachedGraphsByScope: [SpeciesDictionaryTreeScope: TaxonomyTreeGraph] = [:]

    var selectedNode: TaxonomyTreeNode? {
        graph.node(id: selectedNodeID)
    }

    var visibleNodeIDs: Set<String> {
        graph.visibleNodeIDs(
            focusedNodeID: focusedNodeID,
            selectedNodeID: selectedNodeID,
            scale: scale
        )
    }

    var spotlightNodeIDs: Set<String> {
        guard let selectedNodeID else { return [] }
        var ids = graph.connectedIDs(for: selectedNodeID)
        ids.formUnion(graph.ancestorIDs(of: selectedNodeID))
        ids.formUnion(graph.descendantIDs(of: selectedNodeID))
        return ids
    }

    var breadcrumbText: String? {
        let anchorID = selectedNodeID ?? focusedNodeID
        guard let anchorID, let node = graph.node(id: anchorID) else { return nil }
        let titles = graph.ancestorIDs(of: anchorID)
            .compactMap { graph.node(id: $0) }
            .sorted { $0.rank.sortIndex < $1.rank.sortIndex }
            .map(\.title) + [node.title]
        return titles.joined(separator: " / ").nilIfEmpty
    }

    var currentOffset: CGSize {
        CGSize(width: offset.width + dragOffset.width, height: offset.height + dragOffset.height)
    }

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { [weak self] value in
                self?.dragOffset = value.translation
            }
            .onEnded { [weak self] value in
                guard let self else { return }
                offset.width += value.translation.width
                offset.height += value.translation.height
                dragOffset = .zero
            }
    }

    func magnificationGesture(in viewportSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { [weak self] value in
                guard let self else { return }
                if magnifyStartScale == nil {
                    magnifyStartScale = scale
                    magnifyStartOffset = currentOffset
                    dragOffset = .zero
                }

                let startScale = magnifyStartScale ?? scale
                let anchor = clampedAnchor(value.startLocation, in: viewportSize)
                applyScale(
                    clampedScale(startScale * value.magnification),
                    anchoredAt: anchor,
                    startingScale: startScale,
                    startingOffset: magnifyStartOffset
                )
            }
            .onEnded { [weak self] _ in
                guard let self else { return }
                baseScale = scale
                magnifyStartScale = nil
                magnifyStartOffset = offset
            }
    }

    func loadTree(force: Bool = false) async {
        let scope = selectedTreeScope
        if !force, let cachedGraph = cachedGraphsByScope[scope] {
            graph = cachedGraph
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            let response = try await MerianNetworkClient.shared.getSpeciesDictionaryTree(scope: scope)
            let loadedGraph = TaxonomyTreeGraphBuilder.build(from: response.data)
            cachedGraphsByScope[scope] = loadedGraph
            if selectedTreeScope == scope {
                graph = loadedGraph
                hasPositionedInitialViewport = false
            }
        } catch {
            if selectedTreeScope == scope {
                errorMessage = ExploreErrorFormatter.message(for: error)
            }
        }
        if selectedTreeScope == scope {
            isLoading = false
        }
    }

    func selectTreeScope(_ scope: SpeciesDictionaryTreeScope) {
        guard scope != selectedTreeScope else { return }
        selectedTreeScope = scope
        selectedNodeID = nil
        focusedNodeID = nil
        offset = .zero
        dragOffset = .zero
        errorMessage = nil
        hasPositionedInitialViewport = false

        if let cachedGraph = cachedGraphsByScope[scope] {
            graph = cachedGraph
            isLoading = false
        } else {
            graph = .empty
            isLoading = true
        }
    }

    func select(_ node: TaxonomyTreeNode) {
        selectedNodeID = node.id
        HapticManager.shared.triggerSelectionPulse()
    }

    func focus(on nodeID: String) {
        focusedNodeID = nodeID
        selectedNodeID = nodeID
        HapticManager.shared.triggerSelectionPulse()
    }

    func clearFocus() {
        focusedNodeID = nil
        selectedNodeID = nil
        hasPositionedInitialViewport = false
        HapticManager.shared.triggerSelectionPulse()
    }

    func resetView(positions: [String: CGPoint]? = nil, viewportSize: CGSize? = nil) {
        selectedNodeID = nil
        focusedNodeID = nil
        dragOffset = .zero
        scale = 0.82
        baseScale = scale
        if let positions, let viewportSize, centerTopRoot(positions: positions, viewportSize: viewportSize) {
            hasPositionedInitialViewport = true
        } else {
            offset = .zero
            hasPositionedInitialViewport = false
        }
    }

    func zoom(by multiplier: CGFloat, viewportSize: CGSize) {
        zoom(
            by: multiplier,
            anchoredAt: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        )
    }

    func zoom(by multiplier: CGFloat, anchoredAt anchor: CGPoint) {
        setScale(clampedScale(scale * multiplier), anchoredAt: anchor)
    }

    func setScale(_ value: CGFloat, anchoredAt anchor: CGPoint) {
        applyScale(
            clampedScale(value),
            anchoredAt: anchor,
            startingScale: scale,
            startingOffset: currentOffset
        )
        baseScale = scale
    }

    func setScale(_ value: CGFloat) {
        scale = clampedScale(value)
        baseScale = scale
    }

    func center(nodeID: String, positions: [String: CGPoint], viewportSize: CGSize) {
        guard let position = positions[nodeID] else { return }
        offset = CGSize(
            width: viewportSize.width / 2 - position.x * scale,
            height: viewportSize.height / 2 - position.y * scale
        )
        dragOffset = .zero
    }

    func centerTop(nodeID: String, positions: [String: CGPoint], viewportSize: CGSize) {
        guard let position = positions[nodeID] else { return }
        offset = CGSize(
            width: viewportSize.width / 2 - position.x * scale,
            height: topRootViewportY - position.y * scale
        )
        dragOffset = .zero
    }

    func positionInitialViewportIfNeeded(positions: [String: CGPoint], viewportSize: CGSize) {
        guard !hasPositionedInitialViewport else { return }
        guard centerTopRoot(positions: positions, viewportSize: viewportSize) else { return }
        hasPositionedInitialViewport = true
    }

    func visibleContentRect(in viewportSize: CGSize) -> CGRect {
        let offset = currentOffset
        return CGRect(
            x: -offset.width / scale,
            y: -offset.height / scale,
            width: viewportSize.width / scale,
            height: viewportSize.height / scale
        )
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(maxScale, max(minScale, value))
    }

    private func clampedAnchor(_ anchor: CGPoint, in viewportSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(anchor.x, 0), max(viewportSize.width, 0)),
            y: min(max(anchor.y, 0), max(viewportSize.height, 0))
        )
    }

    @discardableResult
    private func centerTopRoot(positions: [String: CGPoint], viewportSize: CGSize) -> Bool {
        guard let rootNodeID = graph.rootNodeIDs.first, positions[rootNodeID] != nil else {
            return false
        }
        centerTop(nodeID: rootNodeID, positions: positions, viewportSize: viewportSize)
        return true
    }

    private func applyScale(
        _ nextScale: CGFloat,
        anchoredAt anchor: CGPoint,
        startingScale: CGFloat,
        startingOffset: CGSize
    ) {
        guard startingScale > 0 else {
            scale = nextScale
            return
        }

        let anchoredContentPoint = CGPoint(
            x: (anchor.x - startingOffset.width) / startingScale,
            y: (anchor.y - startingOffset.height) / startingScale
        )
        scale = nextScale
        offset = CGSize(
            width: anchor.x - anchoredContentPoint.x * nextScale,
            height: anchor.y - anchoredContentPoint.y * nextScale
        )
        dragOffset = .zero
    }
}

private struct TaxonomyConstellationStarfield: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<180 {
                let xFraction = CGFloat((index * 89 + 17) % 997) / 997
                let yFraction = CGFloat((index * 149 + 31) % 991) / 991
                let diameter = CGFloat(1 + (index % 3)) * 0.72
                let rect = CGRect(
                    x: xFraction * size.width,
                    y: yFraction * size.height,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color.secondary.opacity(index.isMultiple(of: 5) ? 0.16 : 0.08))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TaxonomyConstellationClusterHalos: View {
    let graph: TaxonomyTreeGraph
    let positions: [String: CGPoint]
    let visibleNodeIDs: Set<String>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleRoots) { root in
                if let position = positions[root.id] {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    TaxonomyConstellationPalette.tint(for: root).opacity(0.13),
                                    TaxonomyConstellationPalette.tint(for: root).opacity(0.035),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 12,
                                endRadius: 170
                            )
                        )
                        .frame(width: 340, height: 340)
                        .position(position)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var visibleRoots: [TaxonomyTreeNode] {
        graph.rootNodeIDs.compactMap { rootID in
            guard visibleNodeIDs.contains(rootID) else { return nil }
            return graph.node(id: rootID)
        }
    }
}

private struct TaxonomyConstellationEdgesCanvas: View {
    let graph: TaxonomyTreeGraph
    let positions: [String: CGPoint]
    let spotlightIDs: Set<String>
    let selectedNodeID: String?

    var body: some View {
        Canvas { context, _ in
            for edge in graph.edges {
                guard let endNode = graph.node(id: edge.to),
                      let startCenter = positions[edge.from],
                      let endCenter = positions[edge.to] else { continue }
                let isSpotlighted = spotlightIDs.isEmpty ||
                    (spotlightIDs.contains(edge.from) && spotlightIDs.contains(edge.to))
                let isSelectedEdge = selectedNodeID == edge.from || selectedNodeID == edge.to
                var path = Path()
                path.move(to: startCenter)
                path.addLine(to: endCenter)
                let tint = TaxonomyConstellationPalette.tint(for: endNode)
                let lineageWeight = min(2.4, 0.72 + CGFloat(log10(Double(max(1, endNode.speciesCount)))) * 0.58)
                if isSelectedEdge {
                    context.stroke(
                        path,
                        with: .color(tint.opacity(0.14)),
                        style: StrokeStyle(lineWidth: lineageWeight + 6, lineCap: .round)
                    )
                }
                context.stroke(
                    path,
                    with: .color(isSpotlighted ? tint.opacity(isSelectedEdge ? 0.82 : 0.38) : Color.secondary.opacity(0.09)),
                    style: StrokeStyle(
                        lineWidth: isSpotlighted ? lineageWeight : 0.72,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

private enum TaxonomyConstellationPalette {
    static func tint(for node: TaxonomyTreeNode) -> Color {
        let kingdom = (node.lineage?.kingdom ?? (node.rank == .kingdom ? node.title : ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch kingdom {
        case "animalia": return Color.blue
        case "plantae": return Color.green
        case "fungi": return Color.purple
        case "chromista": return Color.teal
        case "bacteria": return Color.cyan
        case "protozoa": return Color.indigo
        case "amoebozoa": return Color.pink
        default: return Color.accentColor
        }
    }
}

private struct TaxonomyTreeScopeFilterBar: View {
    let activeScope: SpeciesDictionaryTreeScope
    let onSelection: (SpeciesDictionaryTreeScope) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpeciesDictionaryTreeScope.allCases, id: \.self) { scope in
                    scopePill(scope)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func scopePill(_ scope: SpeciesDictionaryTreeScope) -> some View {
        Button {
            HapticManager.shared.triggerSelectionPulse()
            onSelection(scope)
        } label: {
            Text(scope.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .foregroundStyle(activeScope == scope ? Color(uiColor: .systemBackground) : Color.primary)
                .background {
                    if activeScope == scope {
                        Capsule().fill(Color.primary)
                    } else {
                        Capsule().fill(.regularMaterial)
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activeScope == scope ? .isSelected : [])
    }
}

private struct TaxonomyTreeControlBar: View {
    let breadcrumb: String?
    let leadingInset: CGFloat

    var body: some View {
        if let breadcrumb {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(breadcrumb)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, leadingInset)
                    .padding(.trailing, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
    }
}

private struct TaxonomyTreeFloatingControls: View {
    let canClearFocus: Bool
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            controlButton(systemImage: "plus.magnifyingglass", action: onZoomIn, label: "Zoom in")
            controlButton(systemImage: "minus.magnifyingglass", action: onZoomOut, label: "Zoom out")
            controlButton(
                systemImage: "scope",
                action: onReset,
                label: canClearFocus ? "Return to constellation overview" : "Recenter constellation"
            )
        }
    }

    private func controlButton(systemImage: String, action: @escaping () -> Void, label: String) -> some View {
        Button {
            HapticManager.shared.triggerLightImpact(intensity: 0.48)
            action()
        } label: {
            controlIcon(systemImage)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                .circularMaterialControl(
                    size: 46,
                    material: .ultraThinMaterial,
                    colorScheme: .dark,
                    borderColor: .white.opacity(0.18),
                    borderWidth: 0.75
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(label)
    }

    private func controlIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
    }
}

private struct TaxonomyConstellationNodeView: View {
    let node: TaxonomyTreeNode
    let scale: CGFloat
    let branchTint: Color
    let isSelected: Bool
    let isSpotlighted: Bool
    let isFocused: Bool
    let action: () -> Void

    private var style: TaxonomyConstellationNodeStyle {
        TaxonomyConstellationNodeStyle.style(for: node, scale: scale)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                nodeMark

                Text(node.title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(node.isSpecies ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)

                if style.showsMetadata || isSelected || isFocused {
                    Text(metadataText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic(node.isSpecies)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .frame(width: style.labelWidth)
            .contentShape(Rectangle())
            .opacity(isSpotlighted ? 1 : 0.24)
            .scaleEffect(isSelected || isFocused ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(node.isSpecies ? "Opens selection details" : "Reveals this branch")
    }

    @ViewBuilder
    private var nodeMark: some View {
        ZStack {
            if node.isSpecies && style.showsSpeciesImage {
                thumbnail
            } else {
                TaxonomyConstellationGlyph(
                    node: node,
                    tint: branchTint,
                    diameter: style.diameter
                )
            }

            if isSelected || isFocused {
                Circle()
                    .stroke(branchTint.opacity(0.2), lineWidth: 8)
                    .padding(-7)
                Circle()
                    .strokeBorder(branchTint, lineWidth: isFocused ? 2.6 : 2)
            }
        }
        .frame(width: style.diameter, height: style.diameter)
        .shadow(
            color: branchTint.opacity(isSelected || isFocused ? 0.34 : 0.12),
            radius: isSelected || isFocused ? 13 : 5
        )
    }

    private var thumbnail: some View {
        Group {
            if let url = ExternalReferenceImagePolicy.url(from: node.species?.referenceImageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderThumbnail
                    }
                }
            } else {
                placeholderThumbnail
            }
        }
        .frame(width: style.diameter, height: style.diameter)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(branchTint.opacity(0.5), lineWidth: 1.2)
        }
    }

    private var placeholderThumbnail: some View {
        Circle()
            .fill(branchTint.opacity(0.16))
            .overlay {
                Image(systemName: "leaf.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(branchTint)
            }
    }

    private var titleFont: Font {
        switch node.rank {
        case .kingdom: .caption.weight(.bold)
        case .phylum, .className: .caption2.weight(.bold)
        case .order, .family, .genus, .species: .caption2.weight(.semibold)
        }
    }

    private var metadataText: String {
        if node.isSpecies {
            return node.subtitle ?? "Species"
        }
        return "\(node.rank.title) · \(node.speciesCount)"
    }

    private var accessibilityLabel: String {
        if node.isSpecies {
            return "\(node.title), \(node.subtitle ?? "Species")"
        }
        return "\(node.title), \(node.rank.title), \(node.speciesCount) species"
    }
}

private struct TaxonomyConstellationGlyph: View {
    let node: TaxonomyTreeNode
    let tint: Color
    let diameter: CGFloat

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            context.fill(Path(ellipseIn: bounds), with: .color(tint.opacity(0.16)))
            context.stroke(
                Path(ellipseIn: bounds.insetBy(dx: 1, dy: 1)),
                with: .color(tint.opacity(0.68)),
                lineWidth: 1.35
            )

            let ringInset = max(7, radius * 0.25)
            context.stroke(
                Path(ellipseIn: bounds.insetBy(dx: ringInset, dy: ringInset)),
                with: .color(tint.opacity(0.22)),
                lineWidth: 0.9
            )

            let rayCount = max(3, min(8, node.childCount))
            let phase = phaseAngle
            for index in 0..<rayCount {
                let angle = phase + CGFloat(index) * 2 * CGFloat.pi / CGFloat(rayCount)
                let innerRadius = radius * 0.22
                let outerRadius = radius * 0.63
                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y + sin(angle) * innerRadius
                ))
                path.addLine(to: CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                ))
                context.stroke(path, with: .color(tint.opacity(0.32)), lineWidth: 0.85)
            }

            let dotCount = max(1, min(6, node.childCount))
            for index in 0..<dotCount {
                let angle = phase + CGFloat(index) * 2 * CGFloat.pi / CGFloat(dotCount)
                let dotRadius = radius * 0.64
                let dotCenter = CGPoint(
                    x: center.x + cos(angle) * dotRadius,
                    y: center.y + sin(angle) * dotRadius
                )
                let dotDiameter = max(3.5, diameter * 0.075)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: dotCenter.x - dotDiameter / 2,
                        y: dotCenter.y - dotDiameter / 2,
                        width: dotDiameter,
                        height: dotDiameter
                    )),
                    with: .color(tint.opacity(0.9))
                )
            }

            let coreDiameter = radius * 0.34
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - coreDiameter / 2,
                    y: center.y - coreDiameter / 2,
                    width: coreDiameter,
                    height: coreDiameter
                )),
                with: .color(tint.opacity(0.9))
            )
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private var phaseAngle: CGFloat {
        let scalarSum = node.id.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        return CGFloat(scalarSum % 360) * CGFloat.pi / 180
    }
}

private struct TaxonomyConstellationNodeStyle {
    let diameter: CGFloat
    let labelWidth: CGFloat
    let showsMetadata: Bool
    let showsSpeciesImage: Bool

    static func style(for node: TaxonomyTreeNode, scale: CGFloat) -> TaxonomyConstellationNodeStyle {
        let baseDiameter: CGFloat
        switch node.rank {
        case .kingdom: baseDiameter = 78
        case .phylum: baseDiameter = 70
        case .className: baseDiameter = 64
        case .order: baseDiameter = 58
        case .family: baseDiameter = 54
        case .genus: baseDiameter = 50
        case .species: baseDiameter = scale >= 2 ? 74 : 52
        }

        return TaxonomyConstellationNodeStyle(
            diameter: baseDiameter,
            labelWidth: node.isSpecies ? 124 : max(104, baseDiameter + 34),
            showsMetadata: scale >= 0.82,
            showsSpeciesImage: node.isSpecies && scale >= 2
        )
    }
}

private struct TaxonomyTreeSelectionDrawer: View {
    let node: TaxonomyTreeNode
    let isFocused: Bool
    let onFocus: () -> Void
    let onClearFocus: () -> Void
    let onOpen: (SpeciesDictionaryRoute) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.24))
                .frame(width: 36, height: 4)

            HStack(spacing: 12) {
                thumbnail

                VStack(alignment: .leading, spacing: 5) {
                    Text(node.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    if let subtitle = node.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 10) {
                if let route = node.dictionaryRoute {
                    Button {
                        HapticManager.shared.triggerSelectionPulse()
                        onOpen(route)
                    } label: {
                        Label("Open", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: onFocus) {
                        Label(isFocused ? "Exploring" : "Explore branch", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFocused)
                }

                Button(action: isFocused ? onClearFocus : onFocus) {
                    Image(systemName: isFocused ? "xmark" : "scope")
                        .frame(width: 42, height: 34)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(isFocused ? "Return to overview" : "Explore branch")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var thumbnail: some View {
        Group {
            if let url = ExternalReferenceImagePolicy.url(
                from: (node.species ?? node.representativeSpecies)?.referenceImageUrl
            ) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholderThumbnail
                    }
                }
            } else {
                placeholderThumbnail
            }
        }
        .frame(width: 68, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            .overlay {
                Image(systemName: node.isSpecies ? "leaf" : "point.3.connected.trianglepath.dotted")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var summaryText: String {
        if node.isSpecies {
            return lineageSummary.nilIfEmpty ?? "Species"
        }
        return "\(node.rank.title) branch - \(node.speciesCount) species - \(node.childCount) direct branches"
    }

    private var chips: [String] {
        var values: [String] = [node.rank.title]
        if node.speciesCount > 1 {
            values.append("\(node.speciesCount) species")
        }
        if let hazard = normalizedHazard {
            values.append(hazard)
        }
        if let status = node.species?.iucnRedListStatus?.trimmedNonEmpty {
            values.append(status.capitalized)
        }
        if let quality = node.species?.contentQuality {
            values.append(quality.label)
        }
        return Array(values.prefix(4))
    }

    private var lineageSummary: String {
        [
            node.lineage?.kingdom,
            node.lineage?.className,
            node.lineage?.family,
            node.lineage?.genus
        ]
        .compactMap { $0?.trimmedNonEmpty }
        .joined(separator: " / ")
    }

    private var normalizedHazard: String? {
        guard let hazard = node.species?.hazardType?.trimmedNonEmpty else { return nil }
        let normalized = hazard.replacingOccurrences(of: "_", with: " ").lowercased()
        guard normalized != "none" else { return nil }
        return normalized.capitalized
    }
}

private struct TaxonomyTreeCanvasTitleModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.navigationTitle("Tree of Life")
        } else {
            content
        }
    }
}

private extension SpeciesDictionaryContentQuality {
    var label: String {
        switch self {
        case .complete: "Complete"
        case .sparse: "Limited"
        case .needsEnrichment: "Early entry"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
