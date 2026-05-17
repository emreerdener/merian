import SwiftUI

struct DistinguishingFeatureSheetView: View {
    let feature: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What to look for")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(feature)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
