import SwiftUI

struct NonBiologicalRetentionBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundColor(.red)
                .font(.system(size: 18))

            Text(NonBiologicalScansPresentation.retentionMessage)
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct NonBiologicalClearingProgressView: View {
    var body: some View {
        ProgressView(NonBiologicalScansPresentation.clearingProgress)
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .allowsHitTesting(false)
    }
}
