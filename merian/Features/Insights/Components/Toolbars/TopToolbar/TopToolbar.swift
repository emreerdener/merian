import SwiftUI

struct TopToolbar: ToolbarContent {
    @Environment(\.dismiss) var dismiss
    
    let commonName: String
    let isCommonNameScrolledPast: Bool
    @Binding var isIdentificationFlagPresented: Bool
    @Binding var isSavingPhotos: Bool
    @Binding var showDeleteConfirmation: Bool
    let onSavePhotos: () -> Void
    var onReanalyze: (() -> Void)?
    var onReviewAlternatives: (() -> Void)?
    var onConfirmIdentification: (() -> Void)?
    let isAlreadyFlagged: Bool
    let isAnalyzing: Bool
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
        }
        
        ToolbarItem(placement: .principal) {
            TopToolbarTitleView(
                commonName: commonName,
                isCommonNameScrolledPast: isCommonNameScrolledPast
            )
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            if !isAnalyzing {
                Menu {
                    Button(action: { onSavePhotos() }) {
                        Label("Download my photos", systemImage: "arrow.down.circle")
                    }
                    
                    Section("Identification") {
                        if let onConfirmIdentification = onConfirmIdentification {
                            Button(action: onConfirmIdentification) {
                                Label("Confirm species", systemImage: "checkmark.circle")
                            }
                        }
                        if let onReviewAlternatives = onReviewAlternatives {
                            Button(action: onReviewAlternatives) {
                                Label("Review alternatives", systemImage: "list.bullet")
                            }
                        }
                        if let onReanalyze = onReanalyze {
                            Button(action: onReanalyze) {
                                Label("Reanalyze species", systemImage: "arrow.2.circlepath")
                            }
                        }
                        if !isAlreadyFlagged {
                            Button(action: { isIdentificationFlagPresented = true }) {
                                Label("Flag for review", systemImage: "flag")
                            }
                        }
                    }
                    
                    Section {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Label("Delete scan", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
    }
}

// MARK: - Isolated Header Component
private struct TopToolbarTitleView: View {
    let commonName: String
    let isCommonNameScrolledPast: Bool
    
    var body: some View {
        ZStack {
            Text(commonName)
                .font(.system(.subheadline, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .opacity(isCommonNameScrolledPast ? 1 : 0)
                .scaleEffect(isCommonNameScrolledPast ? 1 : 0.85)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCommonNameScrolledPast)
    }
}
