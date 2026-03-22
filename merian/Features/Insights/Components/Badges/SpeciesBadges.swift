import SwiftUI

/// Isolated declarative composition mapping pure biological traits to visual semantic badges natively.
struct SpeciesBadges: View {
    let species: SpeciesData
    
    var body: some View {
        CenterFlowLayout(spacing: 12) {
            if species.isInvasive {
                Badge(text: "Invasive", color: .orange, icon: "exclamationmark.triangle.fill")
            }
            
            // if !species.isLiveCapture {
            //     Badge(text: "Not a live capture", color: .gray, icon: "photo.badge.exclamationmark.fill")
            // }
            
            if !species.isBiological {
                Badge(text: "Not biological", color: .gray, icon: "xmark.seal.fill")
            }   
            
            if species.ecologyType.lowercased() == "domesticated" || species.ecologyType.lowercased() == "urban" {
                Badge(text: species.ecologyType.capitalized, color: .purple, icon: "house.fill")
            } else if species.ecologyType.lowercased() != "unknown" {
                Badge(text: species.ecologyType.capitalized, color: .blue, icon: "tree.fill")
            }
        }
    }
}
