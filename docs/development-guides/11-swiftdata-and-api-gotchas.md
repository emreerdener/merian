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

---

## 3. `#Predicate` Cannot Reference Computed Properties

SwiftData's `#Predicate` macro compiles down to `NSPredicate` at the SQL layer. It can only reference stored properties that map 1:1 to database columns. Attempting to reference a computed property — even a simple one that derives from a stored field — crashes at runtime with:

```
Fatal error: keyPathToFlattenedExpression: …keyPath refers to a property
that is not supported by this predicate
```

### The Vulnerability
`OfflineQueuedScan` previously exposed a computed `var isDeleted: Bool { scanStateRaw == 5 }`. Using it in a `@Query` or `FetchDescriptor` predicate compiles fine but crashes at runtime.

### ✅ The Pattern: Store a Raw Int, Predicate on It

```swift
// Model
@Model class OfflineQueuedScan {
    var scanStateRaw: Int = ScanQueueState.pending.rawValue  // stored → safe for #Predicate

    var queueState: ScanQueueState {                         // computed → NOT safe for #Predicate
        get { ScanQueueState(rawValue: scanStateRaw) ?? .pending }
        set { scanStateRaw = newValue.rawValue }
    }
}

// Query — works
@Query(filter: #Predicate<OfflineQueuedScan> { $0.scanStateRaw < 5 }, ...)
private var queuedScans: [OfflineQueuedScan]

// FetchDescriptor — works
let failedRaw = ScanQueueState.failed.rawValue
let descriptor = FetchDescriptor<OfflineQueuedScan>(
    predicate: #Predicate { $0.scanStateRaw == failedRaw }
)
```

Always predicate on the raw stored `Int`, never on the typed computed wrapper. The enum is still safe to use everywhere else in business logic — just not inside `#Predicate`.

---

## 4. In-Memory Lock Sets Are Lost on Process Death

`OfflineQueueManager` originally tracked in-flight uploads via `var activeScanUploadIds: Set<String>`. While reliable within a single process, this set is destroyed on any app kill — including legitimate iOS background terminations. On the next launch, `syncPendingScans` would see scans still in `.uploading` state in SwiftData (because the state had not been updated yet), treat them as pending, and re-dispatch duplicate URLSession tasks.

### ✅ The Pattern: Persist State Before Dispatching

Transition scans to `.uploading` in SwiftData **before** calling `uploadTask.resume()`. If the process dies between the state write and the task dispatch, startup reconciliation detects the orphaned `.uploading` scans (no corresponding active URLSession task) and resets them to `.pending`. If the task was dispatched but the process died mid-upload, iOS's background URLSession re-attaches the task on relaunch — the `.uploading` state correctly prevents re-dispatch.

```swift
// Always persist state BEFORE crossing the URLSession boundary
await dbActor.markScansAsUploading(scanIds: filteredScans.map(\.id))

// Then dispatch
for item in uploadItems {
    let uploadTask = session.uploadTask(with: request, fromFile: item.fileURL)
    uploadTask.resume()
}
```

The same principle applies to any durable operation that must survive a crash: write the intent before performing the action, not after.
