import Foundation

struct SyncCollectionPayload: Encodable {
    let id: String
    let name: String
    let created_at: String
    let is_deleted: Bool
    let scan_ids: [String]
}

let payload = SyncCollectionPayload(id: "123", name: "test", created_at: "now", is_deleted: true, scan_ids: ["456"])
let data = try! JSONEncoder().encode(payload)
print(String(data: data, encoding: .utf8)!)
