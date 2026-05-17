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
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if let target = persona.nextLevelThreshold, let nextTitle = persona.nextLevelTitle {
                VStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        GeometryReader { geometry in
                            let progress = min(CGFloat(uniqueSpeciesCount) / CGFloat(target), 1.0)
                            Rectangle()
                                .fill(AchievementTintToken.springGreen.color)
                                .frame(width: max(0, geometry.size.width * progress))
                        }
                    }
                    .frame(height: 12)
                    .background(Color(uiColor: .secondarySystemFill))
                    .clipShape(Capsule())
                    
                    Text("\(uniqueSpeciesCount) / \(target) discoveries until **\(nextTitle)**")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
        }
    }
}
