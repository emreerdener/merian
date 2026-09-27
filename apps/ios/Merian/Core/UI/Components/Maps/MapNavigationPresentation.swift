import CoreLocation
import MapKit
import SwiftUI

/// Hosts transient sheets and feedback; callers own map data and camera application.
struct MapNavigationPresentation: ViewModifier {
    @Bindable var navigation: MapNavigationModel
    let owner: UUID?
    let onDestination: (MKMapItem) -> Void
    @Environment(AppSettings.self) private var settings
    @Environment(\.mapPlaceSearchConfiguration) private var configuration
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let configuration { navigation.search.configure(configuration) }
            }
            .sheet(isPresented: $navigation.isSearchPresented, onDismiss: { navigation.search.end() }) {
                MapPlaceSearchSheet(model: navigation.search) { navigation.isSearchPresented = false }
            }
            .onChange(of: navigation.search.selectedResult?.id) { _, _ in
                guard navigation.isSearchPresented,
                      navigation.search.isCurrent(owner: owner),
                      let result = navigation.search.selectedResult else { return }
                navigation.cancelNavigation()
                navigation.isSearchPresented = false
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    onDestination(result.item)
                }
            }
            .onChange(of: settings.recentPlacesResetGeneration) { _, _ in navigation.reset() }
            .onChange(of: owner) { _, _ in navigation.reset() }
            .onChange(of: navigation.isSearchPresented) { _, presented in
                if !presented { navigation.search.end() }
            }
            .onDisappear { navigation.reset() }
            .alert(
                navigation.locationAlert == .denied ? "Turn On Location" : "Location Unavailable",
                isPresented: Binding(
                    get: { navigation.locationAlert != nil },
                    set: { if !$0 { navigation.locationAlert = nil } }
                )
            ) {
                if navigation.locationAlert == .denied {
                    Button("Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    Button("Not Now", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: {
                Text(navigation.locationAlert == .denied
                     ? "Allow location access in Settings to center the map on your position."
                     : "We couldn’t determine your location right now. You can still search and browse the map.")
            }
    }
}

private struct MapPlaceSearchConfigurationKey: EnvironmentKey {
    static let defaultValue: MapPlaceSearchConfiguration? = nil
}

extension EnvironmentValues {
    var mapPlaceSearchConfiguration: MapPlaceSearchConfiguration? {
        get { self[MapPlaceSearchConfigurationKey.self] }
        set { self[MapPlaceSearchConfigurationKey.self] = newValue }
    }
}
