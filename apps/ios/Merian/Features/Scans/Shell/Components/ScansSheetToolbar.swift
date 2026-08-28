import SwiftUI

struct ScansSheetToolbar: ToolbarContent {
    @Bindable var searchManager: ScansManager
    @Binding var activeTab: ScansTab
    @Environment(AppSettings.self) private var appSettings

    let dismiss: DismissAction
    let onNewCollection: () -> Void
    let onShare: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some ToolbarContent {
        @Bindable var appSettings = appSettings

        if searchManager.isSelectionMode {
            selectionToolbar
        } else {
            defaultToolbar(appSettings: appSettings)
        }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") {
                searchManager.exitSelectionMode()
            }
            .disabled(searchManager.isDownloading)
        }
        ToolbarItem(placement: .principal) {
            Text("\(searchManager.selectedScans.count) Selected")
                .font(.headline)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Select All") {
                searchManager.selectAll()
            }
            .disabled(searchManager.isDownloading)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
            }
            .disabled(selectionActionsAreDisabled)

            Spacer()

            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
                Text("Download").fontWeight(.semibold)
            }
            .disabled(selectionActionsAreDisabled)

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .tint(searchManager.selectedScans.isEmpty ? .gray : .red)
            .disabled(selectionActionsAreDisabled)
        }
    }

    @ToolbarContentBuilder
    private func defaultToolbar(
        appSettings: AppSettings
    ) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: closeOrClearSearch) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            if activeTab == .collections {
                Button(action: onNewCollection) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(.blue)
                .accessibilityLabel("New collection")
            } else if activeTab == .library {
                libraryOptionsMenu(appSettings: appSettings)
            }
        }

        ToolbarItem(placement: .principal) {
            Picker("View", selection: $activeTab) {
                Text("Scans").tag(ScansTab.library)
                Text("Collections").tag(ScansTab.collections)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }

    private func libraryOptionsMenu(
        appSettings: AppSettings
    ) -> some View {
        Menu {
            ControlGroup {
                gridColumnToggle(
                    1,
                    label: "1x1",
                    systemImage: "rectangle.grid.1x2",
                    appSettings: appSettings
                )
                gridColumnToggle(
                    2,
                    label: "2x2",
                    systemImage: "square.grid.2x2",
                    appSettings: appSettings
                )
                gridColumnToggle(
                    3,
                    label: "3x3",
                    systemImage: "square.grid.3x3",
                    appSettings: appSettings
                )
            }

            Button(action: { searchManager.isSelectionMode = true }) {
                Label("Select multiple", systemImage: "checkmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
        }
        .accessibilityLabel("More options")
    }

    private func gridColumnToggle(
        _ count: Int,
        label: String,
        systemImage: String,
        appSettings: AppSettings
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { appSettings.gridColumns == count },
                set: { if $0 { appSettings.gridColumns = count } }
            )
        ) {
            Label(label, systemImage: systemImage)
        }
    }

    private var selectionActionsAreDisabled: Bool {
        searchManager.selectedScans.isEmpty || searchManager.isDownloading
    }

    private func closeOrClearSearch() {
        if !searchManager.searchQuery.isEmpty {
            searchManager.searchQuery = ""
        } else {
            dismiss()
        }
    }
}
