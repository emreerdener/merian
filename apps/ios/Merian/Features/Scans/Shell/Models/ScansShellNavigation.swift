enum ScansTab {
    case library
    case collections
}

enum ScansNavigationRoute: Hashable {
    case nonBiologicalScans
    case privateScanMap
}

struct ScansSheetInitialNavigation: Equatable {
    let activeTab: ScansTab
    let routes: [ScansNavigationRoute]

    init(initiallyShowsNonBiologicalScans: Bool) {
        activeTab = initiallyShowsNonBiologicalScans ? .collections : .library
        routes = initiallyShowsNonBiologicalScans ? [.nonBiologicalScans] : []
    }
}

struct ScansShellSession: Equatable, Sendable {
    let isAuthenticated: Bool
    let ownerUserID: String?

    static let guest = Self(isAuthenticated: false, ownerUserID: nil)
}
