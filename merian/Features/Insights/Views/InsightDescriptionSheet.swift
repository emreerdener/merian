import SwiftUI

/// Read-only sheet overlay presenting the user's un-truncated description.
struct InsightDescriptionSheet: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Observation description")
                .font(.headline)
                .padding(.top, 24)
                .padding(.horizontal)
                .padding(.bottom, 16)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        // Make text selectable natively
                        .textSelection(.enabled)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }
}
