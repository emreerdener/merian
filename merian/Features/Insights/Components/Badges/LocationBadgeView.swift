import SwiftUI

struct LocationBadgeView: View {
    let locationName: String?
    
    var body: some View {
        #if targetEnvironment(simulator)
        let name: String? = locationName ?? "Austin, TX"
        #else
        let name: String? = locationName
        #endif
        
        if let validName = name, !validName.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                Text(validName)
                    .lineLimit(1)
            }
            .font(.system(.subheadline))
        }
    }
}
