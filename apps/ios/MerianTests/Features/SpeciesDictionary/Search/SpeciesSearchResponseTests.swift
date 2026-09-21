import XCTest
@testable import Merian

final class SpeciesSearchResponseTests: XCTestCase {
    private let id = "00000000-0000-4000-8000-000000000001"
    private var request: SpeciesSearchRequest {
        .init(requestId: id, question: "Butterflies", context: nil, resultKind: .species, cursor: nil)
    }
    private var payload: [String: Any] {
        ["schema_version": 1, "request_id": id, "result_kind": "species", "status": "results",
         "message": "Butterflies", "context": ["query": "butterfly", "group": "insects", "media": NSNull(), "mode": "description"],
         "species": [], "sightings": [], "next_cursor": NSNull()]
    }
    func testDecodesVersionedEmptyResultsAndRejectsIdentityAndKindDrift() throws {
        let result = try SpeciesSearchResponseValidator.decode(JSONSerialization.data(withJSONObject: payload), request: request)
        XCTAssertEqual(result.context?.group, .insects)
        for (field, value) in [("schema_version", 2 as Any), ("request_id", UUID().uuidString), ("result_kind", "sightings")] {
            var invalid = payload
            invalid[field] = value
            XCTAssertThrowsError(try SpeciesSearchResponseValidator.decode(JSONSerialization.data(withJSONObject: invalid), request: request))
        }
    }
    func testCursorRoundTripsSnakeCase() throws {
        let cursor = SpeciesSearchCursor(id: id, rank: nil, sharedAt: "2026-01-01T00:00:00Z")
        let encoded = try JSONEncoder().encode(cursor)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["shared_at"] as? String, cursor.sharedAt)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        XCTAssertEqual(try decoder.decode(SpeciesSearchCursor.self, from: encoded), cursor)
    }
    func testClarificationRequiresUsableContextAndMessage() throws {
        var clarification = payload
        clarification["status"] = "clarification"
        clarification["message"] = "Does it have wings?"
        XCTAssertNoThrow(try SpeciesSearchResponseValidator.decode(JSONSerialization.data(withJSONObject: clarification), request: request))
        clarification["context"] = NSNull()
        XCTAssertThrowsError(try SpeciesSearchResponseValidator.decode(JSONSerialization.data(withJSONObject: clarification), request: request))
        clarification["context"] = payload["context"]
        clarification["message"] = ""
        XCTAssertThrowsError(try SpeciesSearchResponseValidator.decode(JSONSerialization.data(withJSONObject: clarification), request: request))
    }
    func testRejectsUnboundCursorAndUnrequestedContextChangeOnPagination() throws {
        var invalid = payload
        invalid["next_cursor"] = ["id": id, "rank": 1]
        XCTAssertThrowsError(try SpeciesSearchResponseValidator.decode(JSONSerialization.data(withJSONObject: invalid), request: request))
        let pageRequest = SpeciesSearchRequest(requestId: id, question: nil,
                                              context: .init(query: "birds", group: .birds, media: nil, mode: .description),
                                              resultKind: .species, cursor: nil)
        XCTAssertThrowsError(try SpeciesSearchResponseValidator.decode(JSONSerialization.data(withJSONObject: payload), request: pageRequest))
    }
}
