import SwiftUI

/// A bottom sheet letting the user choose their preferred display name for a species
/// from all known English common names (GBIF vernacular names + AI primary name).
///
/// Selection is persisted to UserDefaults via `InsightSheetViewModel.setPreferredCommonName`.
/// "Use default" resets to the canonical DB common name.
struct NamePickerSheet: View {
    let allNames: [String]
    let activeName: String
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
                    Text("Your selection is stored locally and applies only to your device.")
                }
            }
            .navigationTitle("Preferred name")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
