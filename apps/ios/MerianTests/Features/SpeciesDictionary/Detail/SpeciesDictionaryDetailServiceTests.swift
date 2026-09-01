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
