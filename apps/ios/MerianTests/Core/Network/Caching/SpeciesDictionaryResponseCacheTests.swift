import Foundation
import Testing

@testable import Merian

@Suite("Species Dictionary Response Cache")
struct SpeciesDictionaryResponseCacheTests {
    private typealias Fixtures = SpeciesDictionaryNetworkFixtures

    @Test func dictionaryStoresReturnedAliasesAndPrefersIDWithoutNameFallback() {
        let cache = SpeciesDictionaryResponseCache()
        let entry = Fixtures.dictionaryEntry()
        cache.storeDictionaryEntry(entry)

        #expect(cache.dictionaryEntry(speciesId: " \(entry.id.uppercased()) ", scientificName: nil) == entry)
        #expect(cache.dictionaryEntry(speciesId: nil, scientificName: " TESTUS \n floridus ") == entry)
        #expect(cache.dictionaryEntry(speciesId: "not-a-uuid", scientificName: entry.scientificName) == entry)
        #expect(cache.dictionaryEntry(speciesId: Fixtures.alternateID, scientificName: entry.scientificName) == nil)
        #expect(cache.dictionaryEntry(speciesId: nil, scientificName: nil) == nil)
    }

    @Test func externalDictionaryEntryHasOnlyANameAlias() {
        let cache = SpeciesDictionaryResponseCache()
        let entry = Fixtures.dictionaryEntry(id: "external:testus%20floridus")
        cache.storeDictionaryEntry(entry)

        #expect(cache.dictionaryEntry(speciesId: entry.id, scientificName: nil) == nil)
        #expect(cache.dictionaryEntry(speciesId: nil, scientificName: entry.scientificName) == entry)
        #expect(cache.dictionaryEntry(speciesId: Fixtures.speciesID, scientificName: entry.scientificName) == nil)
    }

    @Test func dictionaryTTLIsTenMinutesFromInsertionNotLastRead() {
        var now = Date(timeIntervalSince1970: 0)
        let cache = SpeciesDictionaryResponseCache(now: { now })
        let entry = Fixtures.dictionaryEntry()
        cache.storeDictionaryEntry(entry)

        now = Date(timeIntervalSince1970: 599)
        #expect(cache.dictionaryEntry(speciesId: entry.id, scientificName: nil) == entry)
        now = Date(timeIntervalSince1970: 600)
        #expect(cache.dictionaryEntry(speciesId: entry.id, scientificName: nil) == nil)
        #expect(cache.dictionaryEntry(speciesId: nil, scientificName: entry.scientificName) == nil)
    }

    @Test func statsTTLIsFiveMinutesAndIndependentOfDictionaryTTL() {
        var now = Date(timeIntervalSince1970: 0)
        let cache = SpeciesDictionaryResponseCache(now: { now })
        let entry = Fixtures.statsEntry()
        let dictionaryEntry = Fixtures.dictionaryEntry()
        cache.storeDictionaryEntry(dictionaryEntry)
        cache.storeObservationStatsEntry(entry, requestedSpeciesId: entry.speciesId, requestedScientificName: entry.scientificName)

        now = Date(timeIntervalSince1970: 299)
        #expect(cache.observationStatsEntry(speciesId: entry.speciesId, scientificName: nil) == entry)
        now = Date(timeIntervalSince1970: 300)
        #expect(cache.observationStatsEntry(speciesId: entry.speciesId, scientificName: nil) == nil)
        #expect(cache.observationStatsEntry(speciesId: nil, scientificName: entry.scientificName) == nil)
        #expect(cache.dictionaryEntry(speciesId: dictionaryEntry.id, scientificName: nil) == dictionaryEntry)
    }

    @Test func replacementRefreshesBothAliasesFromOneInsertionTime() {
        var now = Date(timeIntervalSince1970: 0)
        let cache = SpeciesDictionaryResponseCache(now: { now })
        cache.storeDictionaryEntry(Fixtures.dictionaryEntry())
        cache.storeObservationStatsEntry(Fixtures.statsEntry(), requestedSpeciesId: nil, requestedScientificName: nil)

        now = Date(timeIntervalSince1970: 299)
        let replacement = Fixtures.dictionaryEntry(commonName: "Updated Test Flower")
        let stats = Fixtures.statsEntry(status: .partial)
        cache.storeDictionaryEntry(replacement)
        cache.storeObservationStatsEntry(stats, requestedSpeciesId: nil, requestedScientificName: nil)

        now = Date(timeIntervalSince1970: 598)
        #expect(cache.observationStatsEntry(speciesId: stats.speciesId, scientificName: nil) == stats)
        #expect(cache.observationStatsEntry(speciesId: nil, scientificName: stats.scientificName) == stats)
        now = Date(timeIntervalSince1970: 599)
        #expect(cache.observationStatsEntry(speciesId: stats.speciesId, scientificName: nil) == nil)
        now = Date(timeIntervalSince1970: 898)
        #expect(cache.dictionaryEntry(speciesId: replacement.id, scientificName: nil) == replacement)
        #expect(cache.dictionaryEntry(speciesId: nil, scientificName: replacement.scientificName) == replacement)
        now = Date(timeIntervalSince1970: 899)
        #expect(cache.dictionaryEntry(speciesId: replacement.id, scientificName: nil) == nil)
    }

    @Test func bothCapacitiesCountAliasKeysAndEvictOldestInsertionNotLeastRecentlyRead() {
        var now = Date(timeIntervalSince1970: 0)
        let cache = SpeciesDictionaryResponseCache(now: { now })
        for index in 1...32 {
            now = Date(timeIntervalSince1970: Double(index))
            storeBoth(index, in: cache)
        }
        #expect(dictionaryHit(1, in: cache) && statsHit(1, in: cache))
        #expect(dictionaryHit(32, in: cache) && statsHit(32, in: cache))

        now = Date(timeIntervalSince1970: 33)
        storeBoth(33, in: cache)

        #expect(!dictionaryHit(1, in: cache) && !statsHit(1, in: cache))
        #expect(cache.dictionaryEntry(speciesId: nil, scientificName: name(1)) == nil)
        #expect(cache.observationStatsEntry(speciesId: nil, scientificName: name(1)) == nil)
        for index in 2...33 {
            #expect(dictionaryHit(index, in: cache) && statsHit(index, in: cache))
            #expect(cache.dictionaryEntry(speciesId: nil, scientificName: name(index)) != nil)
            #expect(cache.observationStatsEntry(speciesId: nil, scientificName: name(index)) != nil)
        }
    }

    @Test func equalInsertionTimesKeepExactly64KeysWithoutPromisingTieOrder() {
        let cache = SpeciesDictionaryResponseCache(now: { Date(timeIntervalSince1970: 0) })
        for index in 1...33 { storeBoth(index, in: cache) }

        var dictionaryAliases = 0
        var statsAliases = 0
        for index in 1...33 {
            if dictionaryHit(index, in: cache) { dictionaryAliases += 1 }
            if statsHit(index, in: cache) { statsAliases += 1 }
            if cache.dictionaryEntry(speciesId: nil, scientificName: name(index)) != nil { dictionaryAliases += 1 }
            if cache.observationStatsEntry(speciesId: nil, scientificName: name(index)) != nil { statsAliases += 1 }
        }
        #expect(dictionaryAliases == 64)
        #expect(statsAliases == 64)
    }

    @Test func overflowPrunesExpiredAliasesAndKeepsFreshEntriesInBothStores() {
        var now = Date(timeIntervalSince1970: 0)
        let cache = SpeciesDictionaryResponseCache(now: { now })
        for index in 1...31 { storeBoth(index, in: cache) }
        now = Date(timeIntervalSince1970: 599)
        storeBoth(32, in: cache)
        now = Date(timeIntervalSince1970: 600)
        storeBoth(33, in: cache)

        for index in 1...31 {
            #expect(!dictionaryHit(index, in: cache) && !statsHit(index, in: cache))
        }
        #expect(dictionaryHit(32, in: cache) && statsHit(32, in: cache))
        #expect(dictionaryHit(33, in: cache) && statsHit(33, in: cache))
    }

    @Test func statsRetainsRequestedAndReturnedAliasMechanics() {
        let cache = SpeciesDictionaryResponseCache()
        let entry = Fixtures.statsEntry()
        // Validation precedes insertion in the endpoint. This tests only the
        // memo's existing union-of-aliases mechanics, not acceptance of a DTO.
        cache.storeObservationStatsEntry(
            entry, requestedSpeciesId: Fixtures.alternateID, requestedScientificName: "Requested testus"
        )
        for id in [Fixtures.speciesID, Fixtures.alternateID] {
            #expect(cache.observationStatsEntry(speciesId: id, scientificName: nil) == entry)
        }
        for name in [Fixtures.scientificName, "Requested testus"] {
            #expect(cache.observationStatsEntry(speciesId: nil, scientificName: name) == entry)
        }
        #expect(cache.dictionaryEntry(speciesId: Fixtures.speciesID, scientificName: nil) == nil)
    }

    @Test func resetClearsBothStoresAndInstancesStayIndependent() {
        let cache = SpeciesDictionaryResponseCache()
        let otherCache = SpeciesDictionaryResponseCache()
        storeBoth(1, in: cache)
        #expect(!dictionaryHit(1, in: otherCache) && !statsHit(1, in: otherCache))
        storeBoth(2, in: otherCache)
        cache.resetForTesting()

        #expect(!dictionaryHit(1, in: cache) && !statsHit(1, in: cache))
        #expect(cache.dictionaryEntry(speciesId: nil, scientificName: name(1)) == nil)
        #expect(cache.observationStatsEntry(speciesId: nil, scientificName: name(1)) == nil)
        #expect(dictionaryHit(2, in: otherCache) && statsHit(2, in: otherCache))
        storeBoth(1, in: cache)
        #expect(dictionaryHit(1, in: cache) && statsHit(1, in: cache))
    }

    @Test func clockIsSampledOncePerHitOrInsertionAndNeverForEmptyKeysOrMisses() {
        var samples = 0
        let cache = SpeciesDictionaryResponseCache(now: {
            samples += 1
            return Date(timeIntervalSince1970: 0)
        })
        cache.storeDictionaryEntry(Fixtures.dictionaryEntry(id: "", scientificName: " "))
        cache.storeObservationStatsEntry(
            Fixtures.statsEntry(id: nil, scientificName: " "), requestedSpeciesId: nil, requestedScientificName: nil
        )
        #expect(cache.dictionaryEntry(speciesId: nil, scientificName: nil) == nil)
        #expect(!dictionaryHit(1, in: cache) && !statsHit(1, in: cache))
        #expect(samples == 0)
        storeBoth(1, in: cache)
        #expect(samples == 2)
        #expect(dictionaryHit(1, in: cache) && statsHit(1, in: cache))
        #expect(samples == 4)
    }

    private func id(_ index: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", index) }
    private func name(_ index: Int) -> String { "Testus \(index)" }

    private func storeBoth(_ index: Int, in cache: SpeciesDictionaryResponseCache) {
        cache.storeDictionaryEntry(Fixtures.dictionaryEntry(id: id(index), scientificName: name(index)))
        cache.storeObservationStatsEntry(
            Fixtures.statsEntry(id: id(index), scientificName: name(index)),
            requestedSpeciesId: id(index), requestedScientificName: name(index)
        )
    }

    private func dictionaryHit(_ index: Int, in cache: SpeciesDictionaryResponseCache) -> Bool {
        cache.dictionaryEntry(speciesId: id(index), scientificName: nil) != nil
    }

    private func statsHit(_ index: Int, in cache: SpeciesDictionaryResponseCache) -> Bool {
        cache.observationStatsEntry(speciesId: id(index), scientificName: nil) != nil
    }
}
