# SwiftData & Edge API Gotchas

When building zero-OOM pipelines and heavily concurrent systems like Merian, minor API behaviors or framework bugs can manifest as catastrophic system errors. This document outlines critical edge cases involving SwiftData concurrency and Edge Function serialization so future development efforts can avoid repeating them.

---

## 1. SwiftData `@ModelActor` and `#Predicate` Deletion Sync Drops

When deleting records on a background executor (via an `@ModelActor` like `BackgroundDatabaseActor`), you must be extremely precise with how you request the `ModelContext` to purge the record. 

### ❌ The Anti-Pattern: `delete(model:where:)`
```swift
// DO NOT do this inside a background ModelActor
try modelContext.delete(model: OfflineQueuedScan.self, where: #Predicate { $0.id == scanId })
try modelContext.save()
```
While this is extremely efficient as it does not fault models into memory, **in iOS 17 SwiftData it is fundamentally bugged when executing on a background context**. 
- It accurately deletes the SQLite record on disk.
- However, it **does not** accurately formulate and emit the `NSManagedObjectContextObjectsDidChange` background sync notifications to the Main thread context.
- Consequently, any active `@Query` properties bound to the UI (e.g., in a `LibraryView`) will simply hold onto the memory cache and visually "strand" the deleted object in the UI, often leading to infinitely "stuck" loading spinners.

### ✅ The Recommended Pattern: Explicit Fetch-and-Delete
To ensure Main Actor arrays dynamically receive deletion notifications, the record must be instantiated into memory within the active background context prior to calling the atomic `delete` method.

```swift
var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
descriptor.fetchLimit = 1

if let scanToDelete = try modelContext.fetch(descriptor).first {
    modelContext.delete(scanToDelete)
}
try modelContext.save()
```
This strategy faults the swift macro correctly, binds the object identifiers to the active context cache, and when `save()` commits, the delta accurately diffs and synchronizes across all application contexts seamlessly—forcing the UI to refresh instantly.

---

## 2. API Contracts & Silent Optional Fallbacks

When modifying JSON DTO contracts between the client and Edge Functions, be acutely aware of how Swift's `JSONDecoder` evaluates structures comprised entirely of `Optional` properties.

If an API response payload is structurally nested (e.g., `{"success": true, "data": { "confidence_score": 0.9 }}`) but the client attempts to decode the inner payload schema at the root JSON level, the decoding process can fail **silently** without throwing `DecodingError.keyNotFound`.

### The Vulnerability
If the DTO `EdgeResponse` dictates that all of its properties are optional (e.g., `let confidence_score: Double?`, `let scientific_name: String?`), and the decoder parses the outer wrapper `{"success": true, "data": ...}` against `EdgeResponse`:
- It looks for `confidence_score` at the root. It's missing. Since it is optional, the decoder sets it to `nil`.
- It repeats this for all properties.
- **The Result**: Decoding inherently succeeds without throwing an error, but produces an empty, fully `nil` schema instance. 

This causes massive logic failures downstream (e.g., `confidenceScore` falling back to `0.0`, triggering default "Unknown Subject" states in the UI) while entirely obfuscating the root cause by bypassing error-handling catch blocks.

### ✅ The Recommended Pattern: Explicit Wrappers
If the Supabase edge function returns a `{"data": payload}` envelope, you must define and decode an exact 1:1 `EdgeResponseWrapper` struct that strictly requires the `data` key. 

```swift
// STRICT WRAPPER: Enforces key existence.
struct EdgeResponseWrapper: Codable {
    let data: EdgeResponse
}
// This will correctly throw `keyNotFound` if the server payload shape mutates.
let decoded = try JSONDecoder().decode(EdgeResponseWrapper.self, from: rawHttpData)
```

By ensuring that the structural envelope relies on non-optional keys (like `data`), we guarantee that API contract breaches throw loud, trackable `DecodingError` exceptions rather than silently corrupting parsing downstream.
