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
                let progressBarWidth: CGFloat = 240
                let progress = min(CGFloat(uniqueSpeciesCount) / CGFloat(target), 1.0)
                
                VStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemFill))
                            .frame(width: progressBarWidth, height: 8)
                        
                        Capsule()
                            .fill(AchievementTintToken.springGreen.color)
                            .frame(width: progressBarWidth * progress, height: 8)
                    }
                    
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
