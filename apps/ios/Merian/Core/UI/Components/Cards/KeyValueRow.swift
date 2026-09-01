import SwiftUI

public struct KeyValueRow: View {
    public let title: String
    public let value: String
    public var valueIcon: String?
    public var valueIconColor: Color?
    public var valueTextColor: Color?
    public var valueFontWeight: Font.Weight = .medium
    public var isValueItalic: Bool = false

    public init(
        title: String,
        value: String,
        valueIcon: String? = nil,
        valueIconColor: Color? = nil,
        valueTextColor: Color? = nil,
        valueFontWeight: Font.Weight = .medium,
        isValueItalic: Bool = false
    ) {
        self.title = title
        self.value = value
        self.valueIcon = valueIcon
        self.valueIconColor = valueIconColor
        self.valueTextColor = valueTextColor
        self.valueFontWeight = valueFontWeight
        self.isValueItalic = isValueItalic
    }

    public var body: some View {
        HStack {
            Text(title)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .tracking(1)
                .foregroundColor(.secondary)

            Spacer()

            HStack(spacing: 6) {
                if let vIcon = valueIcon {
                    Image(systemName: vIcon)
                        .foregroundColor(valueIconColor ?? .secondary)
                }
                Text(value)
            }
            .font(.system(.subheadline))
            .italic(isValueItalic)
            .fontWeight(valueFontWeight)
            .foregroundColor(valueTextColor ?? .primary)
            .multilineTextAlignment(.trailing)
        }
    }
}
