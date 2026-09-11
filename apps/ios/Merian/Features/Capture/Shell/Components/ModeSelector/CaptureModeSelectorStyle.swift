import SwiftUI
import UIKit

enum CaptureModeSelectorStyle {
    static let controlWidth: CGFloat = 200
    static let controlHeight: CGFloat = 56
    static let symbolPointSize: CGFloat = 24
    static let describeContentClearance: CGFloat = 82

    static let selectedSegmentTintColor = UIColor { traits in
        if traits.accessibilityContrast == .high {
            return .white
        }

        return traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.82)
            : UIColor.white.withAlphaComponent(0.96)
    }

    static func symbolColor(
        isSelected: Bool,
        colorScheme: ColorScheme
    ) -> UIColor {
        if isSelected || colorScheme == .light {
            return .black
        }

        return .white
    }

    static func symbolImage(
        for mode: CaptureMode,
        isSelected: Bool,
        colorScheme: ColorScheme
    ) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: symbolPointSize,
            weight: .semibold
        )
        guard let symbol = UIImage(
            systemName: mode.symbolName,
            withConfiguration: configuration
        ) else {
            return nil
        }

        let image = symbol.withTintColor(
            symbolColor(
                isSelected: isSelected,
                colorScheme: colorScheme
            ),
            renderingMode: .alwaysOriginal
        )
        image.accessibilityLabel = mode.title
        return image
    }

    static func applySymbolImages(
        to control: UISegmentedControl,
        orderedModes: [CaptureMode],
        selectedIndex: Int,
        colorScheme: ColorScheme
    ) {
        for (index, mode) in orderedModes.enumerated() {
            guard index < control.numberOfSegments else { continue }
            control.setImage(
                symbolImage(
                    for: mode,
                    isSelected: index == selectedIndex,
                    colorScheme: colorScheme
                ),
                forSegmentAt: index
            )
        }
    }
}
