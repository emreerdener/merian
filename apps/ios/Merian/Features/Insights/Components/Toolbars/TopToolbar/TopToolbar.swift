import SwiftUI

struct TopToolbar: ToolbarContent {
    enum LeadingControl {
        case close
        case back

        var systemImage: String {
            switch self {
            case .close:
                return "xmark"
            case .back:
                return "chevron.left"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .close:
                return "Close"
            case .back:
                return "Back"
            }
        }
    }

    @Environment(\.dismiss) var dismiss
    
    let commonName: String
    let isCommonNameScrolledPast: Bool
    @Binding var isSavingPhotos: Bool
    @Binding var showDeleteConfirmation: Bool
    let hasUserPhotos: Bool
    var leadingControl: LeadingControl = .close
    let onSavePhotos: () -> Void
    let hasFieldNotes: Bool
    let onFieldNotes: () -> Void
    var onReanalyze: (() -> Void)?
    var onReviewAlternatives: (() -> Void)?
    var onConfirmIdentification: (() -> Void)?
    var onAskCommunity: (() -> Void)?
    let isAnalyzing: Bool
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                toolbarIcon(leadingControl.systemImage)
                    .imageOverlayToolbarIconChrome(isFallbackActive: shouldUseContainedToolbarChrome)
            }
            .accessibilityLabel(leadingControl.accessibilityLabel)
            .imageOverlayToolbarButtonChrome(isFallbackActive: shouldUseContainedToolbarChrome)
        }
        
        ToolbarItem(placement: .principal) {
            ScrollAwareToolbarTitleBadge(
                title: commonName,
                isVisible: isCommonNameScrolledPast
            )
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            if !isAnalyzing {
                Menu {
                    actionMenuContent
                } label: {
                    toolbarIcon("ellipsis")
                        .imageOverlayToolbarIconChrome(isFallbackActive: shouldUseContainedToolbarChrome)
                }
                .imageOverlayToolbarButtonChrome(isFallbackActive: shouldUseContainedToolbarChrome)
            }
        }
    }

    private var shouldUseContainedToolbarChrome: Bool {
        ImageOverlayToolbarChrome.shouldUseContainedBackground
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .bold))
    }

    @ViewBuilder
    private var actionMenuContent: some View {
        if hasUserPhotos {
            Button(action: { onSavePhotos() }) {
                Label("Download scan", systemImage: "arrow.down.circle")
            }
        }

        Button(action: onFieldNotes) {
            Label(hasFieldNotes ? "Update field notes" : "Add field notes", systemImage: "square.and.pencil")
        }
        
        Section("Identification") {
            if let onConfirmIdentification = onConfirmIdentification {
                Button(action: onConfirmIdentification) {
                    Label("Confirm species", systemImage: "checkmark.circle")
                }
            }
            if let onReviewAlternatives = onReviewAlternatives {
                Button(action: onReviewAlternatives) {
                    Label("Review alternatives", systemImage: "person.fill.checkmark.and.xmark")
                }
            }
            if let onReanalyze = onReanalyze {
                Button(action: onReanalyze) {
                    Label("Reanalyze species", systemImage: "arrow.2.circlepath")
                }
            }
            if let onAskCommunity = onAskCommunity {
                Button(action: onAskCommunity) {
                    Label("Ask the community", systemImage: "person.crop.badge.magnifyingglass")
                }
            }
        }
        
        Section {
            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                Label("Delete scan", systemImage: "trash")
            }
        }
    }
}

// MARK: - Isolated Header Component
struct ScrollAwareToolbarTitleBadge: View {
    let title: String
    let isVisible: Bool
    
    var body: some View {
        ZStack {
            if !title.isEmpty {
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            }
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.85)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .accessibilityHidden(!isVisible || title.isEmpty)
    }
}
