import SwiftUI

struct LocationBadgeView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    
    var body: some View {
        #if targetEnvironment(simulator)
        let name: String? = inferenceEngine.speciesData?.locationName ?? "Austin, TX"
        #else
        let name: String? = inferenceEngine.speciesData?.locationName
        #endif
        
        if let validName = name {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                Text(validName)
                    .lineLimit(1)
            }
            .font(.system(.subheadline))
        }
    }
}
