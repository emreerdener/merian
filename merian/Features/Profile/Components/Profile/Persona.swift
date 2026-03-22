import SwiftUI

struct Persona: View {
    let uniqueSpeciesCount: Int
    
    private var persona: String {
        let count = uniqueSpeciesCount
        if count == 0 { return "The Observer" }
        else if count < 10 { return "Casual Explorer" }
        else if count < 50 { return "Dedicated Naturalist" }
        else if count < 100 { return "Verified Scholar" }
        else { return "Apex Observer" }
    }
    
    private var personaDescription: String {
        let count = uniqueSpeciesCount
        if count == 0 { return "The viewfinder is ready. Step outside to log your first scan." }
        else if count < 10 { return "Starting your collection. Learning the language of local flora and fauna." }
        else if count < 50 { return "Mapping local biodiversity and building a vibrant library." }
        else if count < 100 { return "Curating a museum-grade archive of the natural world." }
        else { return "An absolute authority on the ecosystem. Your collection is a masterpiece." }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(persona)
                .font(.system(.largeTitle, design: .serif))
                .fontWeight(.bold)
            
            Text(personaDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
