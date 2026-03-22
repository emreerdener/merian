import SwiftUI

struct ShareButton: View {
    let shareDiscovery: () -> Void
    
    var body: some View {
        Button(action: { shareDiscovery() }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                Text("Share")
            }
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderedProminent)
    }
}
