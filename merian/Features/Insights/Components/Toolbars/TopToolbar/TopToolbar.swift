import SwiftUI

struct TopToolbar: ToolbarContent {
    @Environment(\.dismiss) var dismiss
    
    let commonName: String
    let isCommonNameScrolledPast: Bool
    @Binding var isFlagIssuePresented: Bool
    @Binding var isSavingPhotos: Bool
    @Binding var showDeleteConfirmation: Bool
    let onSavePhotos: () -> Void
    
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
            Menu {
                Button(action: { isFlagIssuePresented = true }) {
                    Label("Flag for review", systemImage: "flag")
                }
                Button(action: { onSavePhotos() }) {
                    Label("Save my photos", systemImage: "arrow.down.circle")
                }
                .disabled(isSavingPhotos)
                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                    Label("Delete scan", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
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
            if isCommonNameScrolledPast {
                Text(commonName)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isCommonNameScrolledPast)
    }
}
