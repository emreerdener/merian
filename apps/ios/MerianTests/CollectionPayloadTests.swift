import XCTest
@testable import Merian

final class CollectionPayloadTests: XCTestCase {
    
    func testSyncCollectionPayloadEncoding() throws {
        // Create a mock payload as defined in BackgroundDatabaseActor
        let payload = BackgroundDatabaseActor.SyncCollectionPayload(
            id: "123-456",
            name: "Test Bug Collection",
            created_at: "2026-03-25T13:40:03Z",
            is_deleted: false,
            scan_ids: ["scan1", "scan2"]
        )
        
        let requestPayload = BackgroundDatabaseActor.SyncRequestPayload(collections: [payload])
        
        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(requestPayload)
        
        // Decode to dictionary to verify
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        XCTAssertNotNil(json, "JSON serialization failed")
        
        let collections = json?["collections"] as? [[String: Any]]
        XCTAssertNotNil(collections, "Missing collections array")
        XCTAssertEqual(collections?.count, 1)
        
        let first = collections?.first
        XCTAssertEqual(first?["id"] as? String, "123-456")
        XCTAssertEqual(first?["name"] as? String, "Test Bug Collection")
        XCTAssertEqual(first?["created_at"] as? String, "2026-03-25T13:40:03Z")
        XCTAssertEqual(first?["is_deleted"] as? Bool, false)
        let scans = first?["scan_ids"] as? [String]
        XCTAssertEqual(scans, ["scan1", "scan2"])
    }
}
