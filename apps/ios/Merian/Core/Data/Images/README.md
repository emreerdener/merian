# Core Data Images

This directory owns shared bounded ImageIO downsampling, file-backed still-image
preparation, bounded local and remote loading, image caches, scan-image
recovery, photo-library writes, and thumbnail backfill. The canonical runtime
contract is the
[image pipeline](../../../../../../docs/system-architecture/03-image-pipeline.md).

## Ownership

- `ImageDownsampler.swift` is the synchronous, stateless ImageIO thumbnail
  decoder used across Core AI, Capture, Insights, Profile, shared UI, and
  Species Reference. Its URL and encoded-data entry points preserve the existing
  autorelease-pool and optional alpha-stripping boundaries; it owns no mutable
  singleton or actor state.
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
  canonical URL mapping and evidence priority. A timestamp guess cannot claim a
  file already owned by a mapping, while later strong evidence evicts a
  conflicting timestamp group regardless of which bounded caller ran first.
  Multi-image timestamp groups are admitted and removed atomically.
  `LocalScanMediaRecoveryRevisions.swift` versions affected canonical source
  URLs and supplies bounded change streams to visible image consumers.
  `LegacyScanMediaRecoveryIndex.swift` is the read-only SQLite index used for
  legacy rescue-store alignment, and `LocalScanMediaRecoverySnapshot.swift` is
  the immutable bridge from current or historical scan values into that policy.
- `Services/ScanMediaRecoveryRegistrationService.swift` rebuilds recovery
  mappings after startup through bounded, cancellation-aware SwiftData reads. It
  reserves direct filename matches even without a rescue row and performs strong
  scan-ID/media-order registration across the complete library before the
  timestamp fallback pass.
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
- Cache and coalescing keys include the current recovery revision. Replacing or
  removing evidence makes an earlier cache entry unreachable, including writes
  from a decode that finishes after invalidation. Visible scan thumbnails and
  full-size local image views observe their source URLs and restart cancelled
  loads when the revision changes. Explore and Profile image consumers use the
  same `ImageRecoveryReloadModifier`; unrelated images remain cached.
- The loader's isolated session retains 30-second request and 300-second
  resource timeouts, four connections per host, disabled cookies, and the 24 MB
  memory / 256 MB disk media cache.
- Local scan recovery requires exact filenames, scan-ID evidence, or the
  constrained one-to-one timestamp rules in the canonical pipeline. It renders a
  recovered file but does not mutate cloud metadata. Recovery source identity
  accepts credential-free HTTPS only, lowercases the scheme and host, removes an
  explicit default port, and ignores query/fragment variants.
- Recovery-index registration never fetches the complete scan table on the main
  actor. The service uses fresh contexts and at most 200 immutable snapshots per
  page, throws an unreadable-store failure, checks cancellation between pages,
  and completes every strong-evidence page before timestamp-ordered fallback.
  The first pass also reserves direct filename matches for scans absent from the
  rescue index. The registry independently enforces that priority across
  interleaved Historical Sync, Scan Library, and post-startup registration
  calls.
- Cloud repair admits only exact local URLs supported by direct filename or
  registered strong evidence. Timestamp guesses are local display fallbacks and
  cannot authorize uploads. Verification is repeated before each network side
  effect after a suspension; loss of evidence permits a later verified retry.
  Cloud repair keeps each canonical source URL single-flight across every
  suspension. Network failures pause the process-local queue for 15 minutes. The
  live adapter is the only owner of endpoint and app-event effects.
- Every production Swift file in this directory stays at or below the 600-line
  review guard.
- Capture-only Vision focus detection remains under
  [Capture Shared](../../../Features/Capture/Shared/README.md); optional
  LiDAR/Vision physical-size estimation remains under
  [Capture Submission](../../../Features/Capture/Submission/README.md). Neither
  is general image-storage infrastructure.

## Verification

- `LocalImageLoaderTests` covers deterministic request coalescing, decode
  admission, URL policy, canonical recovery-source identity, and local recovery
  evidence, including atomic timestamp groups and strong-evidence replacement of
  an earlier timestamp guess. `LocalImageLoaderTests+RecoveryEvidence.swift`
  adds real paged-registration collisions, timestamp-only repair denial, and
  cached/in-flight image invalidation. `LocalScanMediaRecoveryRevisionTests`
  covers targeted revisions, canonical aliases, atomic-group eviction, and
  reset.
- `CloudScanImageRepairActorTests` covers the injected missing-image workflow
  order, equivalent-URL duplicate enqueue while inspection is suspended, and
  evidence invalidation at admission, inspection, signing, and upload with a
  successful later verified retry.
- `ScanMediaRecoveryRegistrationTests` covers the no-index fast path,
  cancellation, the hard 200-record cap, stable paging, and
  strong-evidence-before-timestamp ordering.
- `ImageLoadingArchitectureTests` freezes declaration ownership, imports,
  dependency boundaries, post-startup bounded registration, downsampler/test
  ownership, retired Utilities paths, and the production line ceiling.
- `ImageDownsamplerTests`, `ImageCacheTests`, and `MediaPreparationActorTests`
  retain their focused bounded-decode, cache, and preparation contracts.

The repository-wide native testing tiers are documented in the
[iOS testing strategy](../../../../../../docs/development-guides/08-testing-strategy.md).
