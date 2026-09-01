import SwiftUI

struct OnboardingIllustration: View {
    static let stageSize: CGFloat = 320
    static let topPadding: CGFloat = 64

    let imageName: String
    private let size: CGFloat

    init(imageName: String, size: CGFloat = Self.stageSize) {
        self.imageName = imageName
        self.size = size
    }

    private var scale: CGFloat {
        switch imageName {
        case "journal": 1.1
        case "camera": 1.3
        case "location": 1.2
        case "bird-magnifier": 1.4
        default: 1
        }
    }

    private var horizontalOffset: CGFloat {
        imageName == "bird-magnifier" ? -26 : 0
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .scaleEffect(scale)
            .offset(x: horizontalOffset)
            .accessibilityHidden(true)
    }
}
