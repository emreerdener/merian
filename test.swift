import Foundation
let payload: [String: Any?] = ["r2ObjectKeys": ["staging/123.jpg"] as [String?]]
let cleanPayload = payload.compactMapValues { $0 }
do {
    let data = try JSONSerialization.data(withJSONObject: cleanPayload)
    print("SUCCESS: " + String(data: data, encoding: .utf8)!)
} catch {
    print("FAILED: \(error)")
}
