import SwiftUI

struct InsightSheetHeader: ToolbarContent {
    @Environment(\.dismiss) var dismiss
    
    let commonName: String
    @Binding var showTitle: Bool
    @Binding var isFlagIssuePresented: Bool
    @Binding var isSavingPhotos: Bool
    @Binding var showDeleteConfirmation: Bool
    let onSavePhotos: () -> Void
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.secondary)
            }
        }
        
        ToolbarItem(placement: .principal) {
            Text(commonName)
                .font(.system(.subheadline))
                .fontWeight(.bold)
                .lineLimit(1)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.15))
                .background(.ultraThinMaterial, in: Capsule())
                .opacity(showTitle ? 1 : 0)
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
                    .foregroundColor(.secondary)
            }
        }
    }
}
