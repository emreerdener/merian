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
                loadingState
            } else if let errorMessage = viewModel.errorMessage, viewModel.graph.nodes.isEmpty {
                errorState(message: errorMessage)
            } else if viewModel.graph.nodes.isEmpty {
                emptyState
            } else {
                canvas
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .modifier(TaxonomyTreeCanvasTitleModifier(isEnabled: showsNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadTree()
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let visibleNodeIDs = viewModel.visibleNodeIDs
            let layout = TaxonomyTreeLayout.make(
                graph: viewModel.graph,
                visibleNodeIDs: visibleNodeIDs,
                minimumSize: proxy.size
            )
            let selectedNode = viewModel.selectedNode
            let spotlightIDs = viewModel.spotlightNodeIDs
            let visibleRect = viewModel.visibleContentRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ZStack(alignment: .topLeading) {
                    TaxonomyTreeEdgesCanvas(
                        graph: viewModel.graph,
                        positions: layout.positions,
                        scale: viewModel.scale,
                        spotlightIDs: spotlightIDs,
                        selectedNodeID: viewModel.selectedNodeID
                    )
                    .frame(width: layout.size.width, height: layout.size.height)

                    ForEach(viewModel.graph.nodes.filter { node in
                        guard visibleNodeIDs.contains(node.id), let position = layout.positions[node.id] else {
                            return false
                        }
                        return visibleRect.insetBy(dx: -180, dy: -120).contains(position)
                    }) { node in
                        TaxonomyTreeNodeView(
                            node: node,
                            scale: viewModel.scale,
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

                VStack(spacing: 8) {
                    TaxonomyTreeControlBar(
                        searchText: $viewModel.searchText,
                        breadcrumb: viewModel.breadcrumbText
                    )

                    let searchResults = viewModel.searchResults
                    if !searchResults.isEmpty {
                        TaxonomyTreeSearchResultsView(results: searchResults) { node in
                            let targetScale = node.isSpecies && viewModel.scale < 1.05 ? 1.08 : viewModel.scale
                            let targetVisibleNodeIDs = viewModel.graph.visibleNodeIDs(
                                focusedNodeID: viewModel.focusedNodeID,
                                selectedNodeID: node.id,
                                scale: targetScale
                            )
                            let targetLayout = TaxonomyTreeLayout.make(
                                graph: viewModel.graph,
                                visibleNodeIDs: targetVisibleNodeIDs,
                                minimumSize: proxy.size
                            )
                            withAnimation(.snappy(duration: 0.22)) {
                                viewModel.select(node)
                                viewModel.setScale(targetScale)
                                viewModel.center(nodeID: node.id, positions: targetLayout.positions, viewportSize: proxy.size)
                            }
                        }
                    }
                }
                .frame(width: max(0, proxy.size.width - 28), alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(width: proxy.size.width, alignment: .topLeading)
                .background(alignment: .top) {
                    Color(uiColor: .systemGroupedBackground)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.black.opacity(0.07))
                                .frame(height: 1 / UIScreen.main.scale)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
                        .ignoresSafeArea(edges: .top)
                }

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
                            viewModel.resetView()
                        }
                    }
                )
                .position(
                    x: max(58, proxy.size.width - 42),
                    y: max(220, proxy.size.height - (selectedNode == nil ? 120 : 244))
                )
                .zIndex(4)

                if let selectedNode {
                    TaxonomyTreeSelectionDrawer(
                        node: selectedNode,
                        isFocused: viewModel.focusedNodeID == selectedNode.id,
                        onFocus: {
                            withAnimation(.snappy(duration: 0.22)) {
                                viewModel.focus(on: selectedNode.id)
                                viewModel.center(nodeID: selectedNode.id, positions: layout.positions, viewportSize: proxy.size)
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
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Building taxonomy")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No scanned taxonomy yet",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text("The tree appears after your biological scans are matched to dictionary species.")
        )
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Tree unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await viewModel.loadTree(force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

@MainActor
final class TaxonomyTreeCanvasViewModel: ObservableObject {
    @Published private(set) var graph: TaxonomyTreeGraph = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var selectedNodeID: String?
    @Published var focusedNodeID: String?
    @Published var offset: CGSize = .zero
    @Published var dragOffset: CGSize = .zero
    @Published var scale: CGFloat = 0.78
    @Published var baseScale: CGFloat = 0.78
    @Published var searchText = ""

    private let minScale: CGFloat = 0.46
    private let maxScale: CGFloat = 2.25
    private var magnifyStartScale: CGFloat?
    private var magnifyStartOffset: CGSize = .zero

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
        return ids
    }

    var searchResults: [TaxonomyTreeNode] {
        graph.searchResults(for: searchText)
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
                let anchor = CGPoint(
                    x: value.startAnchor.x * viewportSize.width,
                    y: value.startAnchor.y * viewportSize.height
                )
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
        guard force || graph.nodes.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await MerianNetworkClient.shared.getSpeciesDictionaryTree()
            graph = TaxonomyTreeGraphBuilder.build(from: response.data)
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
        isLoading = false
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
        HapticManager.shared.triggerSelectionPulse()
    }

    func resetView() {
        selectedNodeID = nil
        focusedNodeID = nil
        searchText = ""
        offset = .zero
        dragOffset = .zero
        scale = 0.78
        baseScale = scale
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

private struct TaxonomyTreeEdgesCanvas: View {
    let graph: TaxonomyTreeGraph
    let positions: [String: CGPoint]
    let scale: CGFloat
    let spotlightIDs: Set<String>
    let selectedNodeID: String?

    var body: some View {
        Canvas { context, _ in
            for edge in graph.edges {
                guard let startNode = graph.node(id: edge.from),
                      let endNode = graph.node(id: edge.to),
                      let startCenter = positions[edge.from],
                      let endCenter = positions[edge.to] else { continue }
                let isSpotlighted = spotlightIDs.isEmpty ||
                    (spotlightIDs.contains(edge.from) && spotlightIDs.contains(edge.to))
                let isSelectedEdge = selectedNodeID == edge.from || selectedNodeID == edge.to
                let endpoints = edgeEndpoints(
                    from: startCenter,
                    fromSize: TaxonomyTreeNodeStyle.style(for: startNode, scale: scale).renderedSize,
                    to: endCenter,
                    toSize: TaxonomyTreeNodeStyle.style(for: endNode, scale: scale).renderedSize
                )
                var path = Path()
                path.move(to: endpoints.start)
                let midpointX = (endpoints.start.x + endpoints.end.x) / 2
                path.addCurve(
                    to: endpoints.end,
                    control1: CGPoint(x: midpointX, y: endpoints.start.y),
                    control2: CGPoint(x: midpointX, y: endpoints.end.y)
                )
                context.stroke(
                    path,
                    with: .color(isSpotlighted ? Color.accentColor.opacity(isSelectedEdge ? 0.72 : 0.42) : Color.secondary.opacity(0.12)),
                    style: StrokeStyle(lineWidth: isSpotlighted ? 1.8 : 0.9, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .drawingGroup()
    }

    private func edgeEndpoints(
        from start: CGPoint,
        fromSize startSize: CGSize,
        to end: CGPoint,
        toSize endSize: CGSize
    ) -> (start: CGPoint, end: CGPoint) {
        let startsToRight = end.x >= start.x
        let startX = start.x + (startsToRight ? startSize.width / 2 : -startSize.width / 2)
        let endX = end.x + (startsToRight ? -endSize.width / 2 : endSize.width / 2)
        return (
            CGPoint(x: startX, y: start.y),
            CGPoint(x: endX, y: end.y)
        )
    }
}

private struct TaxonomyTreeControlBar: View {
    @Binding var searchText: String
    let breadcrumb: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let breadcrumb {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(breadcrumb)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField("Search taxonomy", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit {
                    isSearchFocused = false
                }
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .clipped()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear search")
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

private struct TaxonomyTreeFloatingControls: View {
    let canClearFocus: Bool
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            controlButton(systemImage: "plus.magnifyingglass", action: onZoomIn, label: "Zoom in")
            controlButton(systemImage: "minus.magnifyingglass", action: onZoomOut, label: "Zoom out")
            controlButton(systemImage: "scope", action: onReset, label: canClearFocus ? "Locate tree origin" : "Recenter tree")
        }
    }

    private func controlButton(systemImage: String, action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 50, height: 50)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct TaxonomyTreeSearchResultsView: View {
    let results: [TaxonomyTreeNode]
    let onSelect: (TaxonomyTreeNode) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(results) { node in
                    Button {
                        onSelect(node)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(node.rank.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(width: 132, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct TaxonomyTreeNodeView: View {
    let node: TaxonomyTreeNode
    let scale: CGFloat
    let isSelected: Bool
    let isSpotlighted: Bool
    let isFocused: Bool
    let action: () -> Void

    private var style: TaxonomyTreeNodeStyle {
        TaxonomyTreeNodeStyle.style(for: node, scale: scale)
    }

    var body: some View {
        Button(action: action) {
            content
                .frame(width: style.size.width, height: style.size.height)
                .padding(.horizontal, style.horizontalPadding)
                .opacity(isSpotlighted ? 1 : 0.36)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isSelected || isFocused ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .compact:
            VStack(spacing: 3) {
                Text(node.title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(node.speciesCount) species")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .readable:
            VStack(spacing: 4) {
                Text(node.title)
                    .font(node.isSpecies ? .caption.weight(.semibold) : .caption2.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.74)

                Text(node.isSpecies ? (node.subtitle ?? "Species") : "\(node.rank.title) - \(node.speciesCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
        case .species:
            HStack(spacing: 8) {
                thumbnail
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    if let subtitle = node.subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .italic()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let urlString = node.species?.referenceImageUrl,
               let url = URL(string: urlString) {
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
        .frame(width: 42, height: 42)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(rankTint.opacity(0.14))
            .overlay {
                Image(systemName: node.isSpecies ? "leaf" : "point.3.connected.trianglepath.dotted")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rankTint)
            }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: node.isSpecies ? .secondarySystemGroupedBackground : .systemBackground))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(rankTint.opacity(0.75))
                    .frame(width: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(isSelected || isFocused ? 0.16 : 0.06), radius: isSelected || isFocused ? 8 : 3, x: 0, y: 2)
    }

    private var borderColor: Color {
        if isSelected || isFocused { return .accentColor }
        return rankTint.opacity(isSpotlighted ? 0.34 : 0.14)
    }

    private var rankTint: Color {
        switch node.rank {
        case .kingdom: Color.green
        case .phylum: Color.teal
        case .className: Color.blue
        case .order: Color.indigo
        case .family: Color.orange
        case .genus: Color.pink
        case .species: Color.accentColor
        }
    }

    private var accessibilityLabel: String {
        if node.isSpecies {
            return "\(node.title), \(node.subtitle ?? "Species")"
        }
        return "\(node.title), \(node.rank.title), \(node.speciesCount) species"
    }
}

private enum TaxonomyTreeNodeStyle {
    case compact
    case readable
    case species

    var size: CGSize {
        switch self {
        case .compact: CGSize(width: 106, height: 42)
        case .readable: CGSize(width: 142, height: 56)
        case .species: CGSize(width: 190, height: 68)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .compact: 6
        case .readable: 8
        case .species: 8
        }
    }

    var renderedSize: CGSize {
        CGSize(width: size.width + horizontalPadding * 2, height: size.height)
    }

    static func style(for node: TaxonomyTreeNode, scale: CGFloat) -> TaxonomyTreeNodeStyle {
        if node.isSpecies && scale >= 1.05 {
            return .species
        }
        if scale < 0.72 {
            return .compact
        }
        return .readable
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
                        onOpen(route)
                    } label: {
                        Label("Open", systemImage: "book")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: onFocus) {
                        Label(isFocused ? "Focused" : "Focus", systemImage: isFocused ? "scope" : "scope")
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
                .accessibilityLabel(isFocused ? "Clear focus" : "Focus branch")
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
            if let urlString = (node.species ?? node.representativeSpecies)?.referenceImageUrl,
               let url = URL(string: urlString) {
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
