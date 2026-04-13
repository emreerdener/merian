import SwiftUI

struct Persona: View {
    let uniqueSpeciesCount: Int
    
    private var persona: UserPersona {
        UserPersona(speciesCount: uniqueSpeciesCount)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(persona.title)
                .font(.system(.largeTitle, design: .serif))
                .fontWeight(.bold)
            
            Text(persona.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
