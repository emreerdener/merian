import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Map preferences")
struct MapPreferencesTests {
    @Test func satelliteDefaultAndExplicitChoiceSurviveReloadAndAccountCleanup() throws {
        let name = "merian.tests.map-preferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.mapAppearance == .satellite)
        settings.mapAppearance = .standard
        #expect(defaults.string(forKey: UserDefaultsKeys.mapAppearance) == "standard")
        let secondMap = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(secondMap.mapAppearance == .standard)
        settings.mapAppearance = .satellite
        secondMap.refreshFromDefaults()
        #expect(secondMap.mapAppearance == .satellite)
        settings.mapAppearance = .standard
        #expect(AccountScopedPreferences.purgeAndVerify(userDefaults: defaults))
        secondMap.refreshFromDefaults()
        #expect(secondMap.mapAppearance == .standard)
        defaults.set("unrecognized", forKey: UserDefaultsKeys.mapAppearance)
        secondMap.refreshFromDefaults()
        #expect(secondMap.mapAppearance == .satellite)
    }

    @Test func recentsAreBoundedDeduplicatedAccountQualifiedAndPurged() throws {
        let name = "merian.tests.map-history.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RecentPlaceStore(defaults: defaults)
        let owner = UUID()
        let otherOwner = UUID()
        for index in 0..<12 {
            store.record(RecentPlace(title: "Synthetic place \(index)", subtitle: "Test region"), for: owner)
        }
        #expect(store.places(for: owner).count == 10)
        #expect(store.places(for: owner).first?.title == "Synthetic place 11")
        #expect(store.places(for: otherOwner).isEmpty)
        #expect(store.places(for: nil).isEmpty)
        let duplicate = RecentPlace(title: "SYNTHETIC PLACE 5", subtitle: "Test region")
        store.record(duplicate, for: owner)
        #expect(store.places(for: owner).count == 10)
        #expect(store.places(for: owner).first == duplicate)
        #expect(RecentPlaceStore(defaults: defaults).places(for: owner).first == duplicate)
        store.remove(duplicate, for: owner)
        #expect(store.places(for: owner).count == 9)
        store.record(duplicate, for: otherOwner)
        store.clear(for: owner)
        #expect(store.places(for: owner).isEmpty)
        #expect(store.places(for: otherOwner).count == 1)
        let oldGeneration = store.resetGeneration
        #expect(AccountScopedPreferences.purgeAndVerify(userDefaults: defaults))
        #expect(store.places(for: otherOwner).isEmpty)
        #expect(store.resetGeneration != oldGeneration)
    }

    @Test func recentPlacePayloadContainsOnlyDisplayLabels() throws {
        let place = RecentPlace(title: "Synthetic park", subtitle: "Test region")
        let data = try JSONEncoder().encode(place)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["title", "subtitle"])
    }
}
