import SwiftUI

struct InsightDescriptionSection: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    @Binding var isSafariPresented: Bool
    @Binding var selectedWikiURL: URL?
    
    var body: some View {
        if let description = inferenceEngine.speciesData?.insightData.description {
            Text(description)
                .font(.body)
                .padding(.horizontal)
                
            if let rationale = inferenceEngine.speciesData?.insightData.regionalStatusRationale {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Regional context")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text(rationale)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
                
            if let wikiExtract = inferenceEngine.speciesData?.wikipediaExtract {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wikipedia snippet")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Text(wikiExtract)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
                
            if let wikiString = inferenceEngine.speciesData?.wikipediaUrl, let wikiUrl = URL(string: wikiString) {
                Button(action: {
                    selectedWikiURL = wikiUrl
                    isSafariPresented = true
                }) {
                    HStack {
                        Image(systemName: "safari.fill")
                        Text("Read article on Wikipedia")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .foregroundColor(.primary)
            }
        }
    }
}
