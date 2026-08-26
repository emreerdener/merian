import SwiftUI

struct FieldTripTemplateCard: View {
    let template: FieldTripTemplate
    let localScansById: [String: LocalScanRecord]
    let onOpenTemplate: () -> Void
    let onOpenCompletedScan: (String) -> Void

    private var previewTargetCount: Int {
        FieldTripTemplatePresentation.targetCount(for: template)
    }

    private var previewItems: [FieldTripChecklistItem] {
        FieldTripTemplatePresentation.previewLevel(for: template)?.items ?? []
    }

    private var showsScanPreview: Bool {
        previewTargetCount > 0
    }

    private var status: FieldTripTemplateStatusPresentation {
        FieldTripTemplatePresentation.status(for: template)
    }

    private var title: String {
        FieldTripTemplatePresentation.title(template.title, slug: template.slug)
    }

    private var subtitle: String? {
        FieldTripTemplatePresentation.subtitle(for: template)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsScanPreview {
                FieldTripScanPreviewStrip(
                    targetCount: previewTargetCount,
                    templateSlug: template.slug,
                    items: previewItems,
                    localScansById: localScansById,
                    onOpenTemplate: onOpenTemplate,
                    onOpenCompletedScan: onOpenCompletedScan,
                    tileSize: FieldTripTemplateCardLayout.previewTileSize,
                    presentationMode: .responsiveCatalog
                )
                .padding(.top, 24)
                .padding(.bottom, 16)
            }

            Button(action: onOpenTemplate) {
                VStack(alignment: .center, spacing: 6) {
                    Text(title)
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, showsScanPreview ? 0 : 24)
            .padding(.bottom, 16)

            Button(action: onOpenTemplate) {
                Text(status.catalogActionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(
                cornerRadius: FieldTripTemplateCardLayout.cornerRadius,
                style: .continuous
            )
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
        .padding(.horizontal, FieldTripTemplateCardLayout.outerHorizontalInset)
    }
}

struct FieldTripLifecycleStatusBadge: View {
    let status: FieldTripTemplateStatusPresentation
    let accessibilityIdentifier: String

    init(
        status: FieldTripTemplateStatusPresentation,
        accessibilityIdentifier: String = "FieldTripDetailStatus"
    ) {
        self.status = status
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private var indicatorColor: Color {
        switch status.kind {
        case .active, .completed:
            .green
        case .stopped:
            .orange
        case .notStarted, .locked:
            .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(status.title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Field trip status")
        .accessibilityValue(status.title)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct FieldTripTemplateDetailTagRow: View {
    let tags: [FieldTripTemplateTagPresentation]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 8, lineAlignment: .center) {
                ForEach(tags) { tag in
                    FieldTripTemplateTagPill(tag: tag)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct FieldTripTemplateTagPill: View {
    let tag: FieldTripTemplateTagPresentation

    private var tint: Color {
        switch tag.kind {
        case .visibility where tag.title == "Published":
            .green
        case .access:
            .primary
        default:
            .secondary
        }
    }

    private var usesTintedSurface: Bool {
        tag.kind == .visibility
    }

    private var accessibilityLabel: String {
        switch tag.kind {
        case .access:
            "Access, \(tag.title)"
        case .difficulty:
            "Difficulty, \(tag.title)"
        case .level:
            "Current level, \(tag.title)"
        case .visibility:
            "Publication status, \(tag.title)"
        case .location:
            "Location, \(tag.title)"
        }
    }

    private var accessibilityHint: String {
        guard tag.kind == .visibility else { return "" }
        return tag.title == "Published"
            ? "A public snapshot of this outing is published."
            : "This outing has not been published."
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage = tag.systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }

            Text(tag.title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(
                    usesTintedSurface
                        ? tint.opacity(tag.title == "Published" ? 0.16 : 0.12)
                        : Color(uiColor: .tertiarySystemGroupedBackground)
                )
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    usesTintedSurface ? tint.opacity(0.28) : Color.secondary.opacity(0.18),
                    lineWidth: 1
                )
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
