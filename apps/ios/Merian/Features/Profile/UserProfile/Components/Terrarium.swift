import SwiftUI

/// Displays persona artwork matching the user's taxonomical growth.
struct Terrarium: View {
    let uniqueSpeciesCount: Int

    private var persona: UserPersona {
        UserPersona(speciesCount: uniqueSpeciesCount)
    }

    var body: some View {
        Image(persona.imageName)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 360)
    }
}
