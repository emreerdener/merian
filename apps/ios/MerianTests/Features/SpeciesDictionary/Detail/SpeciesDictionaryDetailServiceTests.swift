import XCTest

@testable import Merian

@MainActor
final class SpeciesDictionaryDetailServiceTests: XCTestCase {
    private static let speciesID =
        "1cf79982-e5ee-4e3d-8d65-274527e6ae01"

    func testLivePageAdapterUsesInjectedClientAndForwardsIdentity() async throws {
        let transport = ScopedMockTransport()
        let client = MerianNetworkClient()
        client.overridingSession = transport.makeSession()
        client.overridingAuthUserID = UUID(
            uuidString: "22222222-2222-4222-8222-222222222222"
        )
        client.resetSpeciesDictionaryCacheForTesting()
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        transport.register(path: "/species-dictionary") { request in
            let body = try XCTUnwrap(MockURLProtocol.bodyData(for: request))
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertEqual(
                payload["species_id"] as? String,
                Self.speciesID
            )
            XCTAssertEqual(
                payload["scientific_name"] as? String,
                "Testus floridus"
            )
            return (response, Self.responseData)
        }
        let dependencies = SpeciesDictionaryPageViewModel.Dependencies.live(
            networkClient: client
        )

        let species = try await dependencies.loadSpecies(
            SpeciesDictionaryDetailRequest(
                speciesId: Self.speciesID.uppercased(),
                scientificName: "Testus floridus"
            )
        )

        XCTAssertEqual(species.id, Self.speciesID)
        XCTAssertEqual(species.commonName, "Field Test")
    }

    func testLivePageAdapterClassifiesNotFoundAndReadableErrors() {
        let dependencies = SpeciesDictionaryPageViewModel.Dependencies.live(
            networkClient: MerianNetworkClient()
        )

        XCTAssertEqual(
            dependencies.classifyLoadError(MerianError.httpError(
                statusCode: 404,
                message: "Species not found"
            )),
            .notFound
        )
        XCTAssertEqual(
            dependencies.classifyLoadError(MerianError.invalidResponse),
            .message(MerianError.invalidResponse.localizedDescription)
        )
    }

    func testLivePageAdapterUsesScientificNameWhenIDIsAbsent() async throws {
        let transport = ScopedMockTransport()
        let client = MerianNetworkClient()
        client.overridingSession = transport.makeSession()
        client.overridingAuthUserID = UUID(
            uuidString: "22222222-2222-4222-8222-222222222222"
        )
        client.resetSpeciesDictionaryCacheForTesting()
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: "https://example.com")),
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        transport.register(path: "/species-dictionary") { request in
            let body = try XCTUnwrap(MockURLProtocol.bodyData(for: request))
            let payload = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            XCTAssertNil(payload["species_id"])
            XCTAssertEqual(
                payload["scientific_name"] as? String,
                "Testus floridus"
            )
            return (response, Self.responseData)
        }
        let dependencies = SpeciesDictionaryPageViewModel.Dependencies.live(
            networkClient: client
        )

        let species = try await dependencies.loadSpecies(
            SpeciesDictionaryDetailRequest(
                speciesId: nil,
                scientificName: "Testus floridus"
            )
        )

        XCTAssertEqual(species.scientificName, "Testus floridus")
    }

    func testResolutionUsesAuthenticatedReceiptThenCanonicalRead() async throws {
        let transport = ScopedMockTransport()
        let client = MerianNetworkClient()
        client.overridingSession = transport.makeSession()
        client.overridingAuthUserID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil))
        transport.register(path: "/resolve-species-dictionary") { request in
            let body = try XCTUnwrap(MockURLProtocol.bodyData(for: request))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(payload, ["scientific_name": "Testus synonym"])
            return (response, Data("""
            {"schema_version":1,"requested_scientific_name":"Testus synonym","species_id":"\(Self.speciesID)","scientific_name":"Testus floridus"}
            """.utf8))
        }
        transport.register(path: "/species-dictionary") { request in
            let body = try XCTUnwrap(MockURLProtocol.bodyData(for: request))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(payload["species_id"], Self.speciesID)
            XCTAssertEqual(payload["scientific_name"], "Testus floridus")
            return (response, Self.responseData)
        }
        let dependencies = SpeciesDictionaryPageViewModel.Dependencies.live(networkClient: client)
        let resolve = try XCTUnwrap(dependencies.resolveSpecies)
        let species = try await resolve("Testus synonym")
        XCTAssertEqual(species.id, Self.speciesID)
    }

    func testMismatchedResolutionReceiptNeverFetchesAnotherSpecies() async throws {
        let transport = ScopedMockTransport()
        let client = MerianNetworkClient()
        client.overridingSession = transport.makeSession()
        client.overridingAuthUserID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil))
        transport.register(path: "/resolve-species-dictionary") { _ in
            (response, Data("""
            {"schema_version":1,"requested_scientific_name":"Unrelated species","species_id":"\(Self.speciesID)","scientific_name":"Testus floridus"}
            """.utf8))
        }
        transport.register(path: "/species-dictionary") { _ in
            XCTFail("Invalid resolution must not load a different species")
            return (response, Self.responseData)
        }
        let dependencies = SpeciesDictionaryPageViewModel.Dependencies.live(networkClient: client)
        let resolve = try XCTUnwrap(dependencies.resolveSpecies)
        do {
            _ = try await resolve("Testus synonym")
            XCTFail("Expected invalid receipt rejection")
        } catch {
            XCTAssertEqual(error as? MerianError, .invalidResponse)
        }
    }

    func testResolutionRejectsStaleIDRecoveryToAnotherCanonicalRecord() async throws {
        let transport = ScopedMockTransport()
        let client = MerianNetworkClient()
        client.overridingSession = transport.makeSession()
        client.overridingAuthUserID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")
        let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil))
        transport.register(path: "/resolve-species-dictionary") { _ in
            (response, Data("""
            {"schema_version":1,"requested_scientific_name":"Testus floridus","species_id":"\(Self.speciesID)","scientific_name":"Testus floridus"}
            """.utf8))
        }
        let replacementID = "33333333-3333-4333-8333-333333333333"
        transport.register(path: "/species-dictionary") { _ in
            let json = String(decoding: Self.responseData, as: UTF8.self)
                .replacingOccurrences(of: Self.speciesID, with: replacementID)
            return (response, Data(json.utf8))
        }
        let dependencies = SpeciesDictionaryPageViewModel.Dependencies.live(networkClient: client)
        let resolve = try XCTUnwrap(dependencies.resolveSpecies)
        do {
            _ = try await resolve("Testus floridus")
            XCTFail("A resolution must not adopt another ID through ordinary name recovery")
        } catch {
            XCTAssertEqual(error as? MerianError, .invalidResponse)
        }
    }

    private static let responseData = Data("""
    {
        "schema_version": 1,
        "data": {
            "id": "\(speciesID)",
            "scientific_name": "Testus floridus",
            "common_name": "Field Test",
            "content_quality": "complete",
            "alternative_common_names": [],
            "taxonomy": null,
            "hazard_type": "none",
            "iucn_red_list_status": null,
            "wikipedia_url": null,
            "wikipedia_overview": null,
            "habitat_description": null,
            "gbif_taxon_key": null,
            "group_tags": [],
            "reference_images": [],
            "similar_species": []
        }
    }
    """.utf8)
}
