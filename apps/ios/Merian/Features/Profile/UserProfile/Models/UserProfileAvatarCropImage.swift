import Foundation
import UIKit

/// A bounded avatar preview admitted to Profile's full-screen crop route.
struct UserProfileAvatarCropImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
