import SwiftUI

// MARK: - Core Application Theme Modes
enum ThemeMode: String, CaseIterable, Identifiable {
    // MARK: - AppStorage States
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    // MARK: - Identifiable Compliance
    var id: String { self.rawValue }
    
    // MARK: - SwiftUI Engine Binding
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
