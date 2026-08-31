import SwiftUI

/// A bottom sheet letting the user choose their preferred display name for a species
/// from all known English common names (GBIF vernacular names + AI primary name).
///
/// The caller owns persistence and reset semantics through `onSelect`.
struct NamePickerSheet: View {
    let allNames: [String]
    let activeName: String
    var title: String = "Preferred name"
    var footerText: String = "Your selection is stored locally and applies only to your device."
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(allNames, id: \.self) { (name: String) in
                        Button(action: { onSelect(name) }) {
                            HStack {
                                Text(name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if name.lowercased() == activeName.lowercased() {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Common names")
                } footer: {
                    Text(footerText)
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
