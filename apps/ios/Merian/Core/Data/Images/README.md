# Core Data Images

This directory owns file-backed still-image preparation, bounded local and
remote loading, image caches, scan-image recovery, photo-library writes, and
thumbnail backfill. The canonical runtime contract is the
[image pipeline](../../../../../../docs/system-architecture/03-image-pipeline.md).

## Ownership

- `LocalImageLoader.swift` is the actor entry point for cache lookup, request
  coalescing, local/remote routing, and the isolated media session. Its injected
  `Dependencies` value is the live bridge to recovery, decoding, fetching,
  diagnostics, and cloud repair.
- `Concurrency/AsyncPermitPool.swift` owns cancellation-safe admission to the
  four-slot image decode boundary.
- `Policies/ExternalReferenceImagePolicy.swift` owns HTTPS admission and the
  exact external-media suppression rule. `RemoteImageRetryPolicy.swift` owns
  retryable HTTP and transport classification plus bounded backoff.
- `Recovery/LocalScanMediaRecoveryResolver.swift` owns evidence-based matching
  of durable scan URLs to surviving local files.
  `LocalScanMediaRecoveryRegistry.swift` owns its lock-protected, process-local
  canonical URL mapping. `LegacyScanMediaRecoveryIndex.swift` is the read-only
  SQLite index used for legacy rescue-store alignment.
- `Services/CloudScanImageRepairActor.swift` owns the serial inspect, sign,
  file-backed upload, repair, and library-invalidation workflow. Only its live
  dependency adapter resolves the network client and app event publisher.
- `ExternalImageImportStore.swift` owns the durable document-import inbox;
  `MediaPreparationActor.swift` owns bounded still-image preparation;
  `PhotoLibraryManager.swift` owns add-only Photos writes; `ImageCache.swift`
  owns RAM caching; and `ArchiveManager.swift` owns generated archive downloads.
- `ScanThumbnailBackfillActor.swift` and `ScanThumbnailBackfillCandidate.swift`
  own immutable reference-thumbnail backfill inputs and actor-isolated recovery
  policy.

## Invariants

- Remote image requests accept only credential-free HTTPS URLs. The exact
  blocked iNaturalist asset remains denied before cache lookup and immediately
  before download.
- ImageIO decoding is limited to four admitted operations and runs on the
  dedicated user-initiated decode queue. Raw full-resolution network buffers are
  never inflated through `UIImage(data:)`. A waiter cancelled as a permit is
  granted returns that slot to the pool before reporting cancellation.
- A detached, coalesced load intentionally outlives cancellation of one view
  caller so another waiter can receive the same result and the cache can be
  populated.
- The loader's isolated session retains 30-second request and 300-second
  resource timeouts, four connections per host, disabled cookies, and the 24 MB
  memory / 256 MB disk media cache.
- Local scan recovery requires exact filenames, scan-ID evidence, or the
  constrained one-to-one timestamp rules in the canonical pipeline. It renders a
  recovered file but does not mutate cloud metadata. Recovery source identity
  accepts credential-free HTTPS only, lowercases the scheme and host, removes an
  explicit default port, and ignores query/fragment variants.
- Cloud repair keeps each canonical source URL single-flight across every
  suspension. Failures pause the process-local queue for 15 minutes. The live
  adapter is the only owner of endpoint and app-event effects.
- Every production Swift file in this directory stays at or below the 600-line
  review guard.

## Verification

- `LocalImageLoaderTests` covers deterministic request coalescing, decode
  admission, URL policy, canonical recovery-source identity, and local recovery
  evidence.
- `CloudScanImageRepairActorTests` covers the injected missing-image workflow
  order and equivalent-URL duplicate enqueue while inspection is suspended.
- `ImageLoadingArchitectureTests` freezes declaration ownership, imports,
  dependency boundaries, test ownership, and the production line ceiling.
- `ImageCacheTests` and `MediaPreparationActorTests` retain their focused cache
  and preparation contracts.

The repository-wide native testing tiers are documented in the
[iOS testing strategy](../../../../../../docs/development-guides/08-testing-strategy.md).
