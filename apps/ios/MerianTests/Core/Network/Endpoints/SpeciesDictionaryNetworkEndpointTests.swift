import Foundation
import os
import Testing

@testable import Merian

@Suite("Species Dictionary Network Requests")
@MainActor
struct SpeciesDictionaryNetworkEndpointTests {
    private typealias Fixtures = SpeciesDictionaryNetworkFixtures

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.all)
    func requestVariantsKeepTheirWireShape(_ testCase: SpeciesDictionaryNetworkRequestCase) async throws {
        try await testCase.withResponse { client in try await testCase.invoke(client) }
    }

    @Test func invalidInputsFailBeforeDispatch() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No invalid lookup dispatch", expectedCount: 0) { sent in
            for path in ["/species-dictionary", "/species-observation-stats"] {
                fixture.transport.register(path: path) { request in
                    sent()
                    return try NetworkEndpointTestSupport.response(to: request, json: "{}")
                }
            }
            for name in ["", " \n\t ", String(repeating: "x", count: 161)] {
                await #expect(throws: MerianError.invalidResponse) {
                    try await fixture.client.getSpeciesDictionary(scientificName: name)
                }
                await #expect(throws: MerianError.invalidResponse) {
                    try await fixture.client.getSpeciesDictionary(speciesId: "invalid-id", scientificName: name)
                }
                await #expect(throws: MerianError.invalidResponse) {
                    try await fixture.client.getSpeciesObservationStats(speciesId: Fixtures.speciesID, scientificName: name)
                }
            }
            for id in ["", " \n ", "external:testus", "not-a-uuid"] {
                await #expect(throws: MerianError.invalidResponse) {
                    try await fixture.client.getSpeciesDictionary(speciesId: id)
                }
                await #expect(throws: MerianError.invalidResponse) {
                    try await fixture.client.getSpeciesObservationStats(speciesId: id, scientificName: Fixtures.scientificName)
                }
            }
        }
    }

    @Test func scientificNameLimitCountsUnicodeCharactersNotUTF8Bytes() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let name = String(repeating: "é", count: 160)
        let dictionaryJSON = Fixtures.dictionaryJSON.replacingOccurrences(of: Fixtures.scientificName, with: name)
        let statsJSON = Fixtures.statsJSON.replacingOccurrences(of: Fixtures.scientificName, with: name)
        try await confirmation("One request per supported lookup", expectedCount: 2) { sent in
            fixture.transport.register(path: "/species-dictionary") { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(
                    request, function: "species-dictionary", json: #"{"scientific_name":"\#(name)"}"#
                )
                return try NetworkEndpointTestSupport.response(to: request, json: dictionaryJSON)
            }
            fixture.transport.register(path: "/species-observation-stats") { request in
                sent()
                let url = try #require(request.url)
                let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                #expect(components.queryItems?.last?.value == name)
                return try NetworkEndpointTestSupport.response(to: request, json: statsJSON)
            }
            let dictionary = try await fixture.client.getSpeciesDictionary(scientificName: name)
            let stats = try await fixture.client.getSpeciesObservationStats(
                speciesId: Fixtures.speciesID, scientificName: name
            )
            #expect(dictionary.scientificName == name)
            #expect(stats.scientificName == name)
        }
    }

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations.filter(\.isCacheable))
    func rejectedSchemasNeverWarmRequestedAliases(_ testCase: SpeciesDictionaryNetworkRequestCase) async throws {
        for schema: Int? in [nil, 0] {
            let fixture = NetworkEndpointFixture()
            defer { fixture.close() }
            let attempts = OSAllocatedUnfairLock(initialState: 0)
            var response = try #require(JSONSerialization.jsonObject(with: Data(testCase.responseJSON.utf8)) as? [String: Any])
            if let schema { response["schema_version"] = schema } else { response.removeValue(forKey: "schema_version") }
            let invalidJSON = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)

            try await confirmation("A rejected schema cannot satisfy the next lookup", expectedCount: 2) { sent in
                fixture.transport.register(path: testCase.path) { request in
                    sent()
                    try testCase.expectRequest(request)
                    let attempt = attempts.withLock { count in count += 1; return count }
                    return try NetworkEndpointTestSupport.response(
                        to: request, json: attempt == 1 ? invalidJSON : testCase.responseJSON
                    )
                }
                await #expect(throws: MerianError.invalidResponse) { try await testCase.invoke(fixture.client) }
                try await testCase.invoke(fixture.client)
                try await testCase.invoke(fixture.client)
            }
        }
    }

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations.filter(\.isCacheable))
    func rejectedIdentityNeverWarmsReturnedAliases(_ testCase: SpeciesDictionaryNetworkRequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let returnedName = "Other testus"
        let responseJSON = testCase.responseJSON
            .replacingOccurrences(of: Fixtures.speciesID, with: Fixtures.alternateID)
            .replacingOccurrences(of: Fixtures.scientificName, with: returnedName)

        try await confirmation("A rejected identity cannot warm its returned ID", expectedCount: 2) { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                let attempt = attempts.withLock { count in count += 1; return count }
                if attempt == 1 {
                    try testCase.expectRequest(request)
                } else if testCase.kind == .stats {
                    #expect(request.httpMethod == "GET")
                    let url = try #require(request.url)
                    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [
                        URLQueryItem(name: "species_id", value: Fixtures.alternateID),
                        URLQueryItem(name: "scientific_name", value: returnedName)
                    ])
                } else {
                    try NetworkEndpointTestSupport.expectPOST(
                        request, function: "species-dictionary", json: #"{"species_id":"\#(Fixtures.alternateID)"}"#
                    )
                }
                return try NetworkEndpointTestSupport.response(to: request, json: responseJSON)
            }
            await #expect(throws: MerianError.invalidResponse) { try await testCase.invoke(fixture.client) }
            if testCase.kind == .stats {
                let accepted = try await fixture.client.getSpeciesObservationStats(
                    speciesId: Fixtures.alternateID, scientificName: returnedName
                )
                #expect(accepted.speciesId == Fixtures.alternateID && accepted.scientificName == returnedName)
            } else {
                let accepted = try await fixture.client.getSpeciesDictionary(speciesId: Fixtures.alternateID)
                #expect(accepted.id == Fixtures.alternateID && accepted.scientificName == returnedName)
            }
        }
    }

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations.filter(\.isCacheable))
    func cachedReadsKeepBypassingTransportEvenInCancelledTasks(_ testCase: SpeciesDictionaryNetworkRequestCase) async throws {
        try await testCase.withResponse { client in
            try await testCase.invoke(client)
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                try await testCase.invoke(client)
            }
            try await task.value
        }
    }

    @Test func warmStatsIDStillWinsOverADifferentValidName() async throws {
        try await SpeciesDictionaryNetworkRequestCase.stats.withResponse { client in
            let first = try await client.getSpeciesObservationStats(
                speciesId: Fixtures.speciesID, scientificName: Fixtures.scientificName
            )
            let cached = try await client.getSpeciesObservationStats(
                speciesId: Fixtures.speciesID, scientificName: "Other validus"
            )
            #expect(cached == first)
        }
    }

    @Test func debugResetAndSessionReplacementEachClearBothMemos() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let replacementSession = fixture.transport.makeSession()
        defer { replacementSession.invalidateAndCancel() }

        try await confirmation("Both lookups after each reset", expectedCount: 6) { sent in
            for testCase in [SpeciesDictionaryNetworkRequestCase.detailID, .stats] {
                fixture.transport.register(path: testCase.path) { request in
                    sent()
                    try testCase.expectRequest(request)
                    return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
                }
            }
            for pass in 0..<3 {
                if pass == 1 { fixture.client.resetSpeciesDictionaryCacheForTesting() }
                if pass == 2 { fixture.client.overridingSession = replacementSession }
                try await SpeciesDictionaryNetworkRequestCase.detailID.invoke(fixture.client)
                try await SpeciesDictionaryNetworkRequestCase.stats.invoke(fixture.client)
                // These second reads must use the memo populated in this pass.
                try await SpeciesDictionaryNetworkRequestCase.detailID.invoke(fixture.client)
                try await SpeciesDictionaryNetworkRequestCase.stats.invoke(fixture.client)
            }
        }
    }

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations.filter(\.isCacheable))
    func clientInstancesDoNotShareResponses(_ testCase: SpeciesDictionaryNetworkRequestCase) async throws {
        try await testCase.withResponse { firstClient in
            try await testCase.invoke(firstClient)
            try await testCase.withResponse { secondClient in
                try await testCase.invoke(secondClient)
                try await testCase.invoke(firstClient)
            }
        }
    }

    @Test(arguments: SpeciesDictionaryNetworkRequestCase.operations.filter(\.isCacheable))
    func debugResetDuringTransportDoesNotIntroduceANewGenerationFence(_ testCase: SpeciesDictionaryNetworkRequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let client = fixture.client
        try await confirmation("One lookup can populate after a DEBUG reset") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                // Deterministic overlap: the request has dispatched but its
                // validated response has not been inserted into the memo yet.
                client.resetSpeciesDictionaryCacheForTesting()
                return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
            }
            try await testCase.invoke(client)
            try await testCase.invoke(client)
        }
    }
}
