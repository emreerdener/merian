import SwiftUI

enum FieldTripScanPreviewAction: Equatable {
    case openTemplate
    case openCompletedScan(String)

    static func resolve(completedScanId: String?, hasLocalScan: Bool) -> Self {
        guard let completedScanId, hasLocalScan else { return .openTemplate }
        return .openCompletedScan(completedScanId)
    }
}

struct FieldTripScanPreviewStrip: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    let targetCount: Int
    let templateSlug: String
    let items: [FieldTripChecklistItem]
    let localScansById: [String: LocalScanRecord]
    let onOpenTemplate: () -> Void
    let onOpenCompletedScan: (String) -> Void
    let tileSize: CGFloat
    let presentationMode: FieldTripScanPreviewPresentationMode

    init(
        targetCount: Int,
        templateSlug: String,
        items: [FieldTripChecklistItem],
        localScansById: [String: LocalScanRecord],
        onOpenTemplate: @escaping () -> Void,
        onOpenCompletedScan: @escaping (String) -> Void,
        tileSize: CGFloat = 96,
        presentationMode: FieldTripScanPreviewPresentationMode = .compactScrollable
    ) {
        self.targetCount = targetCount
        self.templateSlug = templateSlug
        self.items = items
        self.localScansById = localScansById
        self.onOpenTemplate = onOpenTemplate
        self.onOpenCompletedScan = onOpenCompletedScan
        self.tileSize = tileSize
        self.presentationMode = presentationMode
    }

    private var visibleTargetCount: Int {
        max(0, targetCount)
    }

    @ViewBuilder
    var body: some View {
        switch presentationMode.resolvedLayout(forTargetCount: visibleTargetCount) {
        case .fixedScrollable:
            fixedWidthStrip
        case .equalWidthTwoUp:
            equalWidthTwoUpStrip
        }
    }

    private var fixedWidthStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                ForEach(0..<visibleTargetCount, id: \.self) { index in
                    scanSlot(at: index)
                        .frame(width: tileSize, height: tileSize)
                }
            }
            .padding(.horizontal, FieldTripScanPreviewLayout.horizontalInset)
        }
        .frame(height: tileSize)
    }

    private var equalWidthTwoUpStrip: some View {
        HStack(spacing: FieldTripScanPreviewLayout.spacing) {
            ForEach(0..<visibleTargetCount, id: \.self) { index in
                scanSlot(at: index)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(.horizontal, FieldTripScanPreviewLayout.horizontalInset)
    }

    private func scanSlot(at index: Int) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
            style: .continuous
        )
        let item = items.indices.contains(index) ? items[index] : nil
        let completedScan = item?.completedScanId.flatMap { localScansById[$0] }
        let action = FieldTripScanPreviewAction.resolve(
            completedScanId: item?.completedScanId,
            hasLocalScan: completedScan != nil
        )

        return Button {
            switch action {
            case .openTemplate:
                onOpenTemplate()
            case .openCompletedScan(let scanId):
                onOpenCompletedScan(scanId)
            }
        } label: {
            Group {
                if let completedScan {
                    ZStack {
                        Color(uiColor: .tertiarySystemGroupedBackground)

                        ScanThumbnail(
                            record: completedScan,
                            isOnline: offlineQueueManager.isOnline,
                            maxDimension: 300,
                            mediaBadgeAlignment: .topTrailing
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    }
                } else {
                    Image(
                        FieldTripGoalArtwork.imageName(
                            for: item?.prompt ?? "",
                            templateSlug: templateSlug,
                            fallbackIndex: index
                        )
                    )
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(FieldTripGoalTipButtonStyle())
        .accessibilityLabel(item?.prompt ?? "Field trip goal")
        .accessibilityValue(item?.isCompleted == true ? "Completed" : "Not completed")
        .accessibilityHint(completedScan == nil ? "Open this field trip." : "Open this scan's insight.")
    }
}
