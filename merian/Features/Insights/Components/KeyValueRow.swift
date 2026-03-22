import SwiftUI

public struct KeyValueRow: View {
    public let title: String
    public let value: String
    public var valueIcon: String? = nil
    public var valueFontWeight: Font.Weight = .medium
    public var isValueItalic: Bool = false
    
    public init(
        title: String,
        value: String,
        valueIcon: String? = nil,
        valueFontWeight: Font.Weight = .medium,
        isValueItalic: Bool = false
    ) {
        self.title = title
        self.value = value
        self.valueIcon = valueIcon
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
                        .foregroundColor(.secondary)
                }
                Text(value)
            }
            .font(.system(.subheadline))
            .italic(isValueItalic)
            .fontWeight(valueFontWeight)
            .foregroundColor(.primary)
            .multilineTextAlignment(.trailing)
        }
    }
}
