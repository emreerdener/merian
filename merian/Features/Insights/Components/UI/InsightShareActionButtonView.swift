import SwiftUI

struct InsightShareActionButtonView: View {
    let shareDiscovery: () -> Void
    
    var body: some View {
        Button(action: { shareDiscovery() }) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                Text("Share")
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.borderedProminent)
    }
}
