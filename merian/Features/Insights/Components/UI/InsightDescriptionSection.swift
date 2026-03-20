import SwiftUI

struct InsightDescriptionSection: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    
    var body: some View {
        if let data = inferenceEngine.speciesData, (data.wikipediaExtract != nil || data.wikipediaUrl != nil) {
            VStack(alignment: .leading, spacing: 16) {
                if let wikiExtract = data.wikipediaExtract {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wikipedia snippet")
                            .font(.system(.subheadline))
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text(wikiExtract)
                            .font(.system(.footnote))
                            .foregroundColor(.secondary)
                    }
                }
                    
                if let wikiString = data.wikipediaUrl, let wikiUrl = URL(string: wikiString) {
                    Button(action: {
                        selectedWikiURL = wikiUrl
                        isSafariPresented = true
                    }) {
                        HStack {
                            Image(systemName: "safari.fill")
                            Text("Read article on Wikipedia")
                                .font(.system(.body))
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemFill))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(UIColor.separator), lineWidth: 1)
                        )
                        .cornerRadius(12)
                    }
                    .padding(.top, 4)
                    .foregroundColor(.primary)
                }
            }
            .glassCard()
        }
    }
}
