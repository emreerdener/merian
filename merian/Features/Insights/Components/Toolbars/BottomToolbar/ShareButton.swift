import SwiftUI

struct ShareButton: View {
    let shareExternally: () -> Void
    let onShareToExplore: (() -> Void)?
    let isSharingToExplore: Bool
    
    @State private var showingOptions = false
    
    var body: some View {
        Button(action: {
            if onShareToExplore != nil {
                showingOptions = true
            } else {
                shareExternally()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                Text("Share")
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .confirmationDialog("Share", isPresented: $showingOptions, titleVisibility: .hidden) {
            if let onShareToExplore {
                Button(isSharingToExplore ? "Sharing to Explore..." : "Share to Explore") {
                    onShareToExplore()
                }
                .disabled(isSharingToExplore)
            }
            Button("Share via Messages, Mail, etc.") {
                shareExternally()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
