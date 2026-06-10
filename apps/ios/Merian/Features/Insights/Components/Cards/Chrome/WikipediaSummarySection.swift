import SwiftUI

struct WikipediaSummarySection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WIKIPEDIA")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(text)
                .font(.system(.body))
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
