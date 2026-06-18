import SwiftUI

struct TaxonomyTreeCanvasView: View {
    let onOpenSpecies: (SpeciesDictionaryRoute) -> Void
    let showsNavigationTitle: Bool

    @State private var items: [SpeciesDictionaryCatalogItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedNodeID: String?
    @State private var offset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1

    private var graph: TaxonomyTreeGraph {
        TaxonomyTreeGraphBuilder.build(from: items)
    }

    init(
        showsNavigationTitle: Bool = true,
        onOpenSpecies: @escaping (SpeciesDictionaryRoute) -> Void
    ) {
        self.showsNavigationTitle = showsNavigationTitle
        self.onOpenSpecies = onOpenSpecies
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                loadingState
            } else if let errorMessage, items.isEmpty {
                errorState(message: errorMessage)
            } else if items.isEmpty {
                emptyState
            } else {
                canvas
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .modifier(TaxonomyTreeCanvasTitleModifier(isEnabled: showsNavigationTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCatalog()
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            let positions = nodePositions(in: graph, size: proxy.size)
            let selectedNeighborIDs = selectedNeighborIDs(in: graph)

            ZStack(alignment: .topLeading) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ZStack {
                    ForEach(graph.edges) { edge in
                        if let start = positions[edge.from], let end = positions[edge.to] {
                            Path { path in
                                path.move(to: start)
                                let midpointX = (start.x + end.x) / 2
                                path.addCurve(
                                    to: end,
                                    control1: CGPoint(x: midpointX, y: start.y),
                                    control2: CGPoint(x: midpointX, y: end.y)
                                )
                            }
                            .stroke(
                                edgeColor(edge, selectedNeighborIDs: selectedNeighborIDs),
                                style: StrokeStyle(lineWidth: selectedNeighborIDs.contains(edge.from) && selectedNeighborIDs.contains(edge.to) ? 2.2 : 1.1)
                            )
                        }
                    }

                    ForEach(graph.nodes) { node in
                        if let position = positions[node.id] {
                            TaxonomyTreeNodeView(
                                node: node,
                                isSelected: selectedNodeID == node.id,
                                isNeighbor: selectedNeighborIDs.contains(node.id),
                                action: { handleNodeTap(node) }
                            )
                            .position(position)
                        }
                    }
                }
                .frame(width: max(proxy.size.width, canvasSize(for: graph).width), height: max(proxy.size.height, canvasSize(for: graph).height))
                .scaleEffect(scale)
                .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                .gesture(dragGesture)
                .simultaneousGesture(magnificationGesture)
            }
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
            "No taxonomy yet",
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text("The tree appears when catalog species have loaded.")
        )
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label("Tree unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await loadCatalog() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                offset.width += value.translation.width
                offset.height += value.translation.height
                dragOffset = .zero
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(1.8, max(0.55, baseScale * value))
            }
            .onEnded { _ in
                baseScale = scale
            }
    }

    @MainActor
    private func loadCatalog() async {
        isLoading = true
        errorMessage = nil
        do {
            let response = try await MerianNetworkClient.shared.getSpeciesDictionaryCatalog(limit: 100)
            items = response.data
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
        isLoading = false
    }

    private func handleNodeTap(_ node: TaxonomyTreeNode) {
        selectedNodeID = node.id
        HapticManager.shared.triggerSelectionPulse()
        if let route = node.dictionaryRoute {
            onOpenSpecies(route)
        }
    }

    private func canvasSize(for graph: TaxonomyTreeGraph) -> CGSize {
        let maxRankCount = Dictionary(grouping: graph.nodes, by: \.rank)
            .values
            .map(\.count)
            .max() ?? 1
        return CGSize(
            width: CGFloat(TaxonomyTreeRank.allCases.count) * 170 + 80,
            height: CGFloat(maxRankCount) * 76 + 120
        )
    }

    private func nodePositions(in graph: TaxonomyTreeGraph, size: CGSize) -> [String: CGPoint] {
        let canvasSize = canvasSize(for: graph)
        let width = max(size.width, canvasSize.width)
        let rankGroups = Dictionary(grouping: graph.nodes, by: \.rank)
        var positions: [String: CGPoint] = [:]

        for rank in TaxonomyTreeRank.allCases {
            let nodes = (rankGroups[rank] ?? []).sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            let x = CGFloat(rank.rawValue) * 170 + 90
            let startY: CGFloat = 72

            for (index, node) in nodes.enumerated() {
                positions[node.id] = CGPoint(
                    x: min(x, width - 90),
                    y: startY + CGFloat(index) * 76
                )
            }
        }

        return positions
    }

    private func selectedNeighborIDs(in graph: TaxonomyTreeGraph) -> Set<String> {
        guard let selectedNodeID else { return [] }
        var ids: Set<String> = [selectedNodeID]
        for edge in graph.edges where edge.from == selectedNodeID || edge.to == selectedNodeID {
            ids.insert(edge.from)
            ids.insert(edge.to)
        }
        return ids
    }

    private func edgeColor(_ edge: TaxonomyTreeEdge, selectedNeighborIDs: Set<String>) -> Color {
        selectedNeighborIDs.contains(edge.from) && selectedNeighborIDs.contains(edge.to)
            ? Color.accentColor.opacity(0.7)
            : Color.secondary.opacity(0.24)
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

private struct TaxonomyTreeNodeView: View {
    let node: TaxonomyTreeNode
    let isSelected: Bool
    let isNeighbor: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(node.title)
                    .font(node.rank == .species ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let subtitle = node.subtitle {
                    subtitleText(subtitle)
                }
            }
            .frame(width: node.rank == .species ? 138 : 118, height: 52)
            .padding(.horizontal, 6)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(node.rank == .species ? Color(uiColor: .secondarySystemGroupedBackground) : Color(uiColor: .systemBackground))
            .shadow(color: .black.opacity(isSelected ? 0.16 : 0.06), radius: isSelected ? 8 : 3, x: 0, y: 2)
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if isNeighbor { return .accentColor.opacity(0.35) }
        return .secondary.opacity(0.18)
    }

    private var accessibilityLabel: String {
        if node.rank == .species {
            return "\(node.title), \(node.subtitle ?? "Species")"
        }
        return "\(node.title), \(node.rank.title)"
    }

    @ViewBuilder
    private func subtitleText(_ subtitle: String) -> some View {
        if node.rank == .species {
            Text(subtitle)
                .font(.caption2)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
