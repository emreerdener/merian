import SwiftUI

struct ExploreRootModePicker: View {
    let activeTab: ExploreTab
    @Binding var activeDiscoveryMode: ExploreDiscoveryMode
    @Binding var activeIdentifyMode: ExploreIdentifyMode
    @Binding var activeFieldTripsSection: FieldTripsSection

    @ViewBuilder
    var body: some View {
        picker
            .pickerStyle(.segmented)
            .padding(.bottom, 1)
            .background(Capsule().fill(.regularMaterial))
            .clipShape(Capsule())
            .frame(width: pickerWidth)
    }

    @ViewBuilder
    private var picker: some View {
        switch activeTab {
        case .feed:
            Picker("Observations view", selection: $activeDiscoveryMode) {
                Text("Feed").tag(ExploreDiscoveryMode.feed)
                Text("Map").tag(ExploreDiscoveryMode.map)
            }
        case .community:
            Picker("Identify view", selection: $activeIdentifyMode) {
                ForEach(ExploreIdentifyMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        case .fieldTrips:
            Picker("Field trips view", selection: $activeFieldTripsSection) {
                ForEach(FieldTripsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
        }
    }

    private var pickerWidth: CGFloat {
        switch activeTab {
        case .community, .fieldTrips:
            240
        case .feed:
            220
        }
    }
}
