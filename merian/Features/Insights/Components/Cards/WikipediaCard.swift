import SwiftUI

struct WikipediaCard: View {
    @Environment(InferenceEngine.self) var inferenceEngine
    
    var body: some View {
        if let data = inferenceEngine.speciesData, 
           let wikiExtract = data.wikipediaOverview, 
           wikiExtract.count >= 60 {
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                        
                        HStack(spacing: 8) {
                            Image(systemName: "book")
                                .foregroundColor(.secondary)
                            Text("Overview")
                                .font(.system(.headline))
                                .foregroundColor(.primary)
                        }
                        .padding(.bottom, 8)
                           
                        Text(wikiExtract)
                            .font(.system(.body))
                            .foregroundColor(.secondary)
                    }
            }
            .card()
        }
    }
}
