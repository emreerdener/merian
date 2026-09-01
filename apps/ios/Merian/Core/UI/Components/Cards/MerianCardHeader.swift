import SwiftUI

struct MerianCardHeader<Accessory: View>: View {
    let systemImage: String
    let title: String
    let accessory: Accessory

    init(
        systemImage: String,
        title: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemImage = systemImage
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(.headline))
                .foregroundColor(.primary)
            accessory
        }
    }
}

extension MerianCardHeader where Accessory == EmptyView {
    init(systemImage: String, title: String) {
        self.init(systemImage: systemImage, title: title) {
            EmptyView()
        }
    }
}
