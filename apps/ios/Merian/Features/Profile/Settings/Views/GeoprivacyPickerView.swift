import SwiftUI

/// Explains the privacy implications before updating the account preference.
struct GeoprivacyPickerView: View {
    @Binding var defaultGeoprivacy: String
    @State private var viewModel: GeoprivacySettingsViewModel

    init(
        defaultGeoprivacy: Binding<String>,
        dependencies: GeoprivacySettingsDependencies
    ) {
        _defaultGeoprivacy = defaultGeoprivacy
        _viewModel = State(
            initialValue: GeoprivacySettingsViewModel(
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        List {
            ForEach(GeoprivacyOption.all) { option in
                Button {
                    select(option)
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.title)
                                .foregroundColor(.primary)
                            Text(option.descriptor)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if defaultGeoprivacy == option.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Geoprivacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ option: GeoprivacyOption) {
        guard defaultGeoprivacy != option.id else { return }
        defaultGeoprivacy = option.id
        viewModel.queuePreferenceUpdate(option.id)
    }
}
