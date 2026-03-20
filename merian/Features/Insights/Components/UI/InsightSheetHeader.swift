import SwiftUI

struct InsightSheetHeader: ToolbarContent {
    @Environment(\.dismiss) var dismiss
    
    let commonName: String
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
