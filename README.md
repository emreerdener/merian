# Naturebook

**Native AI-Powered Ecological Identification for iOS**

Naturebook is a field-ready biological identification app built around
zero-friction capture and scientific-grade accuracy. Point the camera at any
plant, animal, insect, fungus, or other organism, describe it in text, or
capture a short sound clip and receive a structured identification in seconds —
including taxonomy, ecology, conservation status, and diagnostic comparisons
against lookalike species. Merian remains the repository, target, and module
codename.

Public branding and compatibility are governed by the
[Naturebook public-brand contract](docs/system-architecture/08-public-brand-compatibility.md).
Production domain, AASA, email, backend, App Store, verification, and rollback
steps are tracked in the
[Naturebook rebrand rollout runbook](docs/development-guides/15-naturebook-rebrand-rollout.md).

> **Consent production release hold (2026-08-03):** The final **One last step**
> Ready consent screen and versioned adult, Terms, Gemini, and optional PostHog
> evidence are implemented. All tracked consent findings are closed in source, including
> crash-safe ghost-ledger handoff, withdrawal-time PostHog transport blocking,
> verified atomic local-ledger persistence, restart-safe multi-account
> withdrawal journaling, target-account restoration, final in-merge
> account/session fencing, Realtime repair, OAuth account replacement, and
> atomic rejection of delayed offline AI/analytics grants plus deny-wins
> rebasing of revocations onto the locked server head. Gemini authorization,
> Edge PostHog delivery, and iOS permission gates now resolve the provider-wide
> greatest revision across all disclosure versions first: any head revocation
> denies, and only a head grant may enter disclosure/rollout checks.
> Completed users also remain on a launch-matched neutral root while required
> account evidence is unknown, so approval controls are never a transient
> startup state. An expired cached Supabase session retains its account identity
> for this gate until refresh succeeds or Auth emits a signed-out result; token
> expiry alone is never treated as no session. Fetch, decoding, pending-row
> push, and ledger-write failures
> keep that root active, expose **Try Again**, and receive bounded 5-, 10-, and
> 20-second account-fenced retries. Once an authenticated account enters that
> missing-local-evidence restoration state, only a successfully persisted
> authoritative merge may select the scanner or Ready consent screen.
> Internal test builds may continue, but
> do not nominate the candidate for public production or enable strict server
> enforcement until **iOS Build and Test** and the validation-only **Supabase
> Candidate Validation** workflow are green on the same immutable SHA, followed
> by replacement-build rollout, App Store 18+ configuration, and paid Gemini
> billing/DPA evidence.
> See the
> [canonical consent readiness record](docs/legal/production-consent-readiness-2026-08-03.md).

> **iOS privacy manifest status (2026-08-05):** The main app now owns a
> validated `PrivacyInfo.xcprivacy` declaring no tracking, the reviewed linked
> data categories, and approved reasons for app-only user defaults, app-container
> file timestamps, and write-admission disk-space checks. This closes the
> missing-manifest finding in source, not the production gate. The final
> exact-SHA archive must report `privacy_manifest_valid: true`, and the signed
> Organizer archive still needs an aggregate privacy report reconciled with SDK
> manifests, the public policy, App Store Connect answers, and counsel review.
> See the
> [iOS privacy manifest contract](docs/development-guides/16-ios-privacy-manifest.md).

> **iOS transport security status (2026-08-05):** The main app no longer
> disables App Transport Security. App-configured origins and backend-supplied
> remote media are accepted only as credential-free HTTPS, with ATS retained as
> an independent platform backstop. Source, archive, and exported-IPA
> validators reject broad or domain-scoped exceptions and insecure Supabase
> origins. Public promotion still requires exact-SHA archive evidence reporting
> `transport_security: "ats-default"`. See the
> [iOS transport security contract](docs/development-guides/17-ios-transport-security.md).

> **Sign in with Apple deletion status (2026-08-06):** Apple authorization-code
> capture, Vault-backed refresh-token storage, claim-fenced provider revocation,
> subject-bound credential-state revalidation, and a durable manual fallback
> for pre-rollout Apple accounts are implemented in source. Supabase Auth
> deletion is now unreachable while a stored Apple credential remains.
> Production promotion still requires hosted Apple key
> provisioning, exact-SHA fresh-catalog replay, a real Apple exchange/revoke
> smoke, and either an enforceable minimum-supported-build gate or an
> independent server-delivered manual fallback for older iOS binaries. See the
> [canonical Apple deletion contract](docs/backend-and-data/20-sign-in-with-apple-account-deletion.md).

> **Production release evidence gate (2026-07-28):** DwC-A exports are
> authoritatively disabled for the initial launch by migration
> `20260728133835_disable_dwca_exports_for_launch.sql`; Release iOS builds hide
> the staged controls, new jobs fail closed in PostgreSQL, processing cron is
> stopped, and archive cleanup remains active. Exact-SHA fresh-catalog pgTAP,
> complete CI—including the hosted full iOS unit-test target, unsigned Release
> archive, and frozen public-web gate—and production credential/catalog smoke
> tests still gate the base release. Maximum-shape export and delivery evidence
> moves to the separate DwC-A feature-enable gate. See the
> [canonical release-hold record](docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

> **Critical scan release gate (2026-07-28):** the latest attached
> disposable-catalog run passed 24 of 26 files, including the complete
> inline/video and formerly ambiguous identity-merge fixtures. The only two
> failures reached the new atomic Explore/Community RPCs and proved their
> `SECURITY INVOKER` caller lacked explicit relational privileges on
> `explore_community_requests`; the run stopped before production mutation.
> Forward migration `20260729044500_grant_atomic_explore_service_privileges.sql`
> now grants only the required service-role table operations while
> browser-facing roles retain no writes, and both fixtures assert that boundary.
> The remediation also preserves offline retry history and requires the durable
> completed-upload transition to commit before inference starts. No successful
> exact-SHA deployment evidence for these corrections has been retained yet. The
> release remains held until one reviewed exact SHA passes all 27 current
> catalog files, completes the ordered backend deployment, passes the matching
> hosted iOS gate, and clears joined video, Field Chat, offline, and Explore/Ask
> the Community staging smokes. See the
> [video finalization incident](docs/incidents/2026-07-video-scan-canonical-finalization-regression.md).

> **TestFlight addendum (2026-07-29):** build 1.0.2 (235) exposed a client
> state-machine deadlock after `failed_retryable / background_ingestion_failed`.
> Media uploaded successfully, but every status preflight skipped the Identify
> request required to reclaim the failed generation; upload success also erased
> its retry count. A follow-up archive showed the initial single-row latch fix
> was insufficient on a migrated store: retry state survived in the durable job
> while a drifted queued-scan snapshot restarted at attempt one. Retry authority
> now reconciles both copies and advances from their monotonic maximum. A
> separate same-session smoke proved new Identify and Explore publication
> healthy while an eligible older `media_reconciliation_abandoned` record was
> rejected by the terminal repair signer. The tree now preserves one exact retry
> latch through re-stage, permits its generation-fenced Identify dispatch,
> bounds automatic churn, and allows only authenticated tombstone-free
> `replay_exhausted` repair, or `media_reconciliation_abandoned` repair backed
> by composite service proof: a post-result dead letter no earlier than the
> latest charged normal/replay attempt, evidence shaped for its producer
> generation, no active reservation or corrupt timestamp lineage, and no
> moderation-rejected or moderation-infrastructure-failed capture lifecycle row.
> Pre-rollout evidence narrowly supports the vulnerable producer’s first
> committed normal attempt; it must also belong to the immutable exact
> dead-letter-ID snapshot captured by the migration, predate the private cutoff,
> and match the audited multimodal post-safety error path. The exact snapshot
> prevents a producer blocked behind migration DDL from gaining legacy authority
> through its earlier transaction-start timestamp. Post-rollout evidence must
> bind the exact quota IDs, validated provider result, and completed Identify
> safety evaluation. Because the rollout uses two separate migration-file
> transactions, production now predeploys fail-closed signing, status, and share
> consumers before either file, then deploys the schema-dependent Identify
> producer only after proof hardening and service-only readiness checks succeed.
> Library, scheduler, reconnect, and URLSession replay wakes now share one
> process-local driver plus at most one trailing pass, preventing overlapping
> status probes, orphan transitions, retry inflation, and start-log storms. See
> the
> [retry deadlock incident](docs/incidents/2026-07-failed-retryable-scan-status-upload-deadlock.md)
> and
> [legacy share incident](docs/incidents/2026-07-media-abandoned-explore-share-recovery.md).
> A later physical-device smoke also staged and submitted a scan with Wi-Fi and
> cellular disabled; it remained queued and completed after connectivity was
> restored. This positively exercises ordinary offline replay, but build `235`
> predates the remediation and its retained console lacks the transaction-level
> sequence, so a fresh globally higher exact-source TestFlight build remains a
> release requirement. Hosted iOS Runs 97 and 153 are stale failure evidence for
> parent SHA `0aa170fa`: both stopped on two ambiguous offline-sync
> `Set(compactMap:)` expressions before test or archive execution. Pushed
> descendant `f292dc48` explicitly types every equivalent snapshot as
> `Set<String>` and locally passes the complete app/unit/UI `build-for-testing`
> product graph under the documented CoreSimulator resource bypass. Run 99 on
> exact descendant `631e123e8` subsequently exposed three stale test-contract
> expectations; their test-only correction is committed in `8642a8c6d`. Run 100
> on that exact descendant passed all 1,241 unit tests and every protected
> critical scan-flow regression, while exposing a fixed four-second
> Debug-fixture race before the hosted accessibility hierarchy could observe
> `ScanningStatusBadge`. The timer-free handshake is committed as
> `399482b649363c820b59fee1967bf94e35a5c0e7`. Run 101 on that exact SHA again
> passed all 1,241 unit tests and protected regressions, and its current-SHA
> Release archive passed at 239,079,424 bytes for `1.0.2 (235)`, fingerprint
> `989544a7bbb531c91673c1949ed676497c6cd08a2028375fc5fc3a73ca7b100c`, with
> verified main dSYM UUIDs and no Debug UI-seed markers. The UI smoke now proved
> queued navigation, shared scanning content, decoded audio playback, and the
> explicit badge tap; it failed only when the seeded completed record did not
> take over the already-open sheet. That late Debug transaction used the
> container main context while the sheet was bound to its environment
> `ModelContext`, then relied on an asynchronous library event to merge the
> insert. The context-bound follow-up performs the transaction in that exact
> context and immediately calls the existing production queue-promotion path.
> Release retains a no-op coordinator, and production queue timing is unchanged.
> That portion is committed as `838533e98589f4fca89643e966864a7d59adca05`. Run
> 102 on that exact SHA did not reach the queued UI smoke because its complete
> unit target reported 1,240 passed and one failed:
> `testCancelledExploreShareUsesCanonicalCancellationAndDoesNotReplay` observed
> zero requests while expecting the first request. Its fixed loop of 100
> executor yields did not provide a time-bounded rendezvous with URLSession on
> the loaded hosted simulator. Commit `4f68e68913fca6276458cd093ad167c9bc7d5d9e`
> replaces that loop with a wait of up to five monotonic seconds for the
> observable first dispatch, then preserves both exact assertions: one request
> before cancellation and still one after cancellation. Run 102's current-SHA
> Release archive independently passed at 239,083,520 bytes for `1.0.2 (235)`,
> fingerprint
> `2f79712ff4b08ac6fea2e972e9819c5b9d54a0a46bf4d051a3facaddc1963a30`, with
> verified main dSYM UUIDs and no Debug UI-seed markers. Run 103 on exact SHA
> `4f68e68913` passed all 1,241 unit tests, every protected critical case, and
> its 239,083,520-byte current-SHA archive with fingerprint
> `99c82c4e68eceb39c0d29db26bfe57236105de25c499dcd1a9acbe3c82e25c0e`. The queued
> UI smoke still failed after its explicit badge tap because the seeded
> completed record did not take over the queued sheet. A local result-bundle run
> after correcting child-before-parent event ordering reached **Northern
> Cardinal** and retained decoded audio, then proved the bottom toolbar was
> absent: queued and completed states share one UUID, so a toolbar task keyed to
> that ID did not restart after promotion advanced the presentation generation.
> Commit `2ca985f6079c41c45c6a6e78d382c8283eb0db3b` makes a persisted
> completion authoritative over stale same-ID queued routes and keys
> result-toolbar plus Field Notes tasks to that generation. Rebinding that stale
> route after the exact completion is already visible is an idempotent no-op
> that preserves the result generation and controls. A later verbose exact-case
> rerun exposed an independent
> test-interaction defect: the animated scanning badge advertised a 703-point
> accessibility frame beginning at x=-384.7 in a 402-point window, so XCTest
> rejected the rectangle and tapped its x=5 fallback sliver. Commit
> `2ca985f6079c41c45c6a6e78d382c8283eb0db3b` proved that visually clipping those
> translated descendants was insufficient: Run 104 compiled both test bundles,
> passed all 1,243 unit tests and the 239,112,192-byte Release archive
> (fingerprint
> `145b2bb7571b18c556bc6e8ff6944b60fdb14e9c85c73896936f978c0886faeb`), then
> failed the explicit containment assertion before tapping because the badge
> still exposed an off-window accessibility frame. Commit
> `6ed0f557b3222890aca55e4c383b2c110ffc8269` removes translated SwiftUI geometry
> from the control: completed-state glare is drawn inside a fixed Canvas and
> label changes use a bounded opacity transition. Run 105 on that exact SHA
> passed all 1,243 unit tests, every protected critical case, and its
> 239,095,808-byte Release archive (fingerprint
> `6141847844d37a450109e7d2ef2e7bd42512c1fc68991f5b7ef497a9625b2e7c`), but
> failed earlier in the UI smoke because `ScanningStatusBadge` was no longer
> discoverable through `app.buttons`. The queued Insight and native Back control
> were present. Re-composing the native Button with
> `.accessibilityElement(children: .ignore)` had changed where the caller's
> identifier was exposed. Commit `c7eac9c8f3124437712ee72eeff49d09e6ea55b1`
> removes that recomposition, retains the explicit label on the native Button,
> and adds a source guard rejecting its return. On that exact SHA, a local Xcode
> 26.6 generic-Simulator `build-for-testing` compiled and linked the app,
> complete unit bundle, and UI bundle for both simulator architectures; local
> resource compilation and XCUI execution remain unavailable in the desktop
> sandbox. The smoke still reports both app and badge rectangles if containment
> ever fails again. A hosted run on `c7eac9c8f3` or a committed descendant must
> pass the exact one-case queued-scan UI smoke and its current-SHA archive
> together. See the
> [queued Insight same-ID handoff incident](docs/incidents/2026-07-queued-insight-same-id-handoff-regression.md).

> **App Store export integrity addendum (2026-07-30):** a clean local archive
> from exact revision `6ce1a56a47aea1deb05353a7714c3f0518aabfac` correctly
> carried `1.0.2 (236)` and source fingerprint
> `5c02aec4af0b40f131f127d1d55469f23bf503cb236a4029e87dd1b1946c3b76`.
> Xcode's distribution pipeline nevertheless emitted an App Store-signed IPA
> labeled build `272`, matching its cached latest App Store Connect build `271`
> plus one, while retaining the archive's source provenance. The prior export
> helper omitted `manageAppVersionAndBuildNumber`, whose Xcode default is
> enabled, and verified only the archive—not the artifact it called
> TestFlight-ready. Retained Content Delivery logs prove Xcode uploaded `1.0.2 (272)`
> successfully with no errors or warnings and App Store Connect accepted it for
> processing, so `272` is definitively consumed. The command-line exporter that
> created competing archive and upload identities is now retired. Xcode
> Organizer is the sole distribution path, and its Xcode-managed number as
> reported by App Store Connect is authoritative. See the
> [Xcode export renumbering incident](docs/incidents/2026-07-xcode-export-build-number-rewrite.md).

---

## Features

### Capture Workspace

- User-orderable Scan, Record, and Describe pages. The first configured mode is
  selected during workspace initialization, so Audio-first and Description-first
  launches do not briefly open Camera or start camera hardware.
- Instant-on `AVCaptureSession` with device priority: triple camera → LiDAR →
  dual → wide. Triple camera is preferred on Pro models to expose the full
  0.5×–15× optical zoom range.
- LiDAR depth harvesting via `AVCaptureDepthDataOutput`, feeding absolute
  subject distance (up to ~5m) to the AI model to prevent scale hallucinations.
- Tap-to-focus, tap-to-expose, pinch zoom, vertical swipe zoom, and direct drag
  on the zoom meter.
- Native hardware button capture via `AVCaptureEventInteraction` (volume
  buttons, Action button, iPhone 16 Camera Control).
- Mixed-media staging mode — queue up to 2 total photos, short Pro video clips,
  audio clips, or descriptions before submitting to inference.
- Share one photo from iOS Photos directly to Naturebook. The app opens through
  its image document association, preserves included EXIF date/location context,
  requires the normal gallery crop, and continues through the existing quota,
  confirmation, inference, and offline-queue flow without a Share Extension or
  broad Photo Library access.
- Pro video scans let users briefly hold the visual shutter for a short
  stabilized clip, with an active countdown, cancel control, staged playback
  review, and image-based thumbnail; Naturebook analyzes five ordered sampled
  frames plus accompanying audio when available, then stores an upload-bounded
  playback clip for library review and Explore sharing while keeping sampled
  frames out of the user-visible media carousel.
- Optional **Save to camera roll** uses add-only Photos access to preserve new
  camera photos and original video recordings. Explicit Insight and Scan Library
  Downloads can save retained local or approved cloud videos alongside photos
  even when automatic saving is off; video writes remain file-backed. See the
  [camera-roll media export contract](docs/features-and-hardware/27-camera-roll-media-export.md).
- Audio Listen Mode records a 15-second WAV clip with live spectrogram and SNR
  feedback.
- Describe Mode supports typed observations and live voice dictation through
  `SpeechManager`.
- Real-time viewfinder intelligence hints (brightness, distance, motion blur)
  powered by on-device luma analysis at 3fps.
- Logarithmic zoom meter with optical stop indicators, haptic detents at each
  lens transition, and a tick-elongation animation around the active position.

### Identification

- Powered by **Google Gemini 2.5 Flash** (ordinary Naturebook tier) and
  **Gemini 2.5 Pro** (Pro tier), routed via Deno Edge Functions on Supabase.
  Production permits only the server-side `GEMINI_PAID_API_KEY`; there is no
  unpaid-key fallback and private provider secrets never touch the client
  binary.
- Every public provider attempt first obtains an idempotent database reservation
  that verifies durable entitlement, selects the allowed model, and applies
  UTC-day plus per-user/IP cost ceilings. Entitlement/database failures fail
  closed.
- The staged entitlement replacement gives every existing and future account
  three lifetime complimentary Pro scans, separate from the daily Flash scan.
  Paid Pro takes precedence; after the third durable result, compatible
  single-evidence captures fall back to Flash while video, mixed-media, and
  Pro-only actions offer an upgrade. Activation remains behind the documented
  protocol-3 atomic cutover after the reservation-safe iOS build is verified.
- Structured JSON output schema enforced server-side: common name, scientific
  name, full Linnaean taxonomy, ecology type, IUCN Red List status,
  location-aware invasiveness flag with region/rationale/confidence, confidence
  score, dominant colors, categorical group tags, and a lookalike diagnostic
  comparison.
- Dog and cat scans keep species-grade taxonomy (`Canis lupus familiaris` /
  `Felis catus`) while optionally carrying a separate pet label for confident
  breed, mix, coat-pattern, or body-type display.
- Concurrent on-device `VNClassifyImageRequest` drives the scanning overlay's
  status phrases while the network round-trip runs.
- Environmental telemetry captured for each scan: shutter-time GPS, date/time,
  LiDAR depth scale, zoom, and cached device context travel with live inference.
  For eligible live-camera still scans, elevation, WeatherKit, and semantic
  location join within a 150 ms grace period or are patched into the owner scan
  afterward.
- `/identify-multimodal` is the shared live and replay endpoint for visual,
  audio, Describe, mixed-media, and video submissions; queued media uploads
  through R2 staging before inference. For a fresh provider-owning invocation,
  HTTP `200` means moderation, required media promotion, primary species
  resolution, scan creation, authenticated-owner read-back, every claimed
  staging-key disposition, and ready canonical image/video/audio verification
  have completed before the ingestion ledger is marked complete last. A later
  same-UUID response marked `X-Merian-Idempotent-Replay: reconstructed` may
  instead be rebuilt from that exact durable owner row while canonical
  reconciliation remains retryable; it never invokes the provider again. Every
  success still guarantees that the returned owner scan exists and is
  immediately addressable.
- Live-camera still-image analysis becomes eligible to start as soon as the
  durable local queue accepts the scan. WeatherKit/reverse geocoding receive a
  150 ms grace period, late context is patched without re-identifying, and the
  live request hands the uplink to background recovery after its body finishes
  sending. Parsed and persisted results render before awards, Field trips, or
  optional client enrichment. Primary Wikipedia/GBIF species resolution on a
  cache miss may extend the required server finalization interval; analytics,
  group tags, and candidate enrichment remain background work. Free remains on
  `gemini-2.5-flash` and Pro remains on `gemini-2.5-pro`; prompts, schema,
  thinking budgets, image resolution, output limits, and the single Gemini call
  per scan are unchanged.
- Older/interrupted observations missing their owner cloud row can be repaired
  through authenticated Edge contracts before Field Chat, Ask the Community, or
  Explore sharing. Recovery never grants iOS direct scan-table writes and
  restores media only through owner-scoped staging keys. Every current
  scan-producing route atomically establishes its job/intent before provider
  dispatch; rolling-deployment claim and recovery share that per-scan database
  generation lock. Recovery writes its scan and completed ledger atomically and
  requires an existing complete ledger, exact `replay_exhausted`, or exact
  `media_reconciliation_abandoned` plus the matching composite
  dead-letter/quota/media-lifecycle proof; policy, later-policy, unproven
  abandonment, unknown, and no-ledger state fails closed. A retryable scanless
  generation writes one durable client retry latch mirrored across its queued
  scan and durable job. Fresh reads consult both copies, serialized transitions
  repair drift before mutation, and retry accounting advances from the monotonic
  maximum. That exact latch survives any required fresh upload and lets the
  delayed preflight send Identify instead of repeatedly classifying its own
  retry as server-owned. A known cloud-complete result has higher authority than
  either retry copy. Explicit retry starts a fresh bounded automatic budget
  under the same scan UUID, including for description-only work with no
  upload-reset boundary. Owner deletion takes the same lock and writes a private
  UUID tombstone before storage erasure, permanently fencing delayed inference,
  replay, and cross-device recovery for the deleted generation. Storage deletion
  accepts only flat free/Pro object keys containing that canonical owner UUID,
  so a poisoned row cannot nominate another user's object. A leased server
  reaper independently completes interrupted media erasure and scheduled
  monitoring alerts on deletion backlog/SLA health. The full joined success,
  retry, recovery, Field Chat, and Explore contract is documented in
  [`16-scan-ingestion-reliability-and-recovery.md`](docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

### Scans Library

- Grid view of all personal captures, sorted by newest, oldest, or alphabetical.
- **Semantic search** across common name, scientific name, confident pet labels,
  ecology type, AI-generated color tags, categorical group tags (e.g. "bird",
  "songbird"), and Latin taxonomy fields. Searching "bird" resolves via a
  taxonomy class → plain-English synonym mapping, so neither Latin knowledge nor
  exact species names are required.
- Category filter bar: All, Plants, Fungi, Insects, Birds, Mammals, Reptiles,
  Other.
- User-created collections (albums) with many-to-many scan relationships, synced
  to Supabase.
- Non-biological captures isolated in a dedicated view.
- Pending queued captures render above completed scans with state-aware
  upload/inference affordances.

### Insight Sheet

- Species header with common name, scientific name, and AI confidence spectrum
  (3-band visual scale). Confident dog/cat pet labels can headline the sheet
  while the scientific name remains visible as taxonomy context.
- Full Linnaean taxonomy (kingdom → genus).
- Ecological description, Wikipedia extract, and in-app Safari link.
- Mixed-media carousel combining live captures, persisted
  image/video/audio/description pages, and GBIF/Wikipedia reference images.
- Scan Information Card: location name, elevation, zoom factor, weather, date,
  time, and a MapKit snapshot.
- Toxicity warning banner, IUCN conservation status, and species badges
  (invasive, ecology type).
- Diagnostic comparison: primary match rationale, confusing lookalike, and key
  visual differentiators.
- Shared scan milestone queue for Field trip progress, achievement unlocks, and
  global **New to Naturebook** dictionary contributions.
- Private field notes persist on `LocalScanRecord` / `OfflineQueuedScan` and can
  optionally be published to Explore posts.
- Pro-only Field chat lets users ask saved follow-up questions from completed
  biological insights without resending raw images, with AI-generated quick
  prompts grounded in the saved scan context.

### Explore

- Explore uses exactly three bottom items: **Observations**, **Field trips**, and
  **Identify**. Identify owns a **Requests / Index** root picker. Requests is a
  dashboard with shared All/Yours/organism filters, a 12-card **Identify
  requests** preview, and 10 grouped **Recent activity** rows. **See all
  requests** and **See all activity** push paginated **Identify requests** and
  **Identify activity** pages; Index renders the existing Species Dictionary
  overview. The unfinished taxonomy Tree/galaxy map is preserved behind its
  default-off flag but has no MVP navigation entry point.
- Public feed, following feed, trending, nearby, and map views backed by
  Supabase RPCs and Edge Functions.
- Explore post details expose the same floating Field chat entry point as
  Insights. Each Pro viewer gets a private per-post conversation visible only to
  them—not to other viewers—grounded in the public observation and Species
  Dictionary context. Authors can use it on their own published posts too.
- Share/unshare scans to Explore with optional public hashtags and a selectable
  common-name snapshot, browse hashtag post collections, like posts, comment,
  react to comments, follow authors, and receive Explore notifications.
- Field trips are released for every user. They add guided regional checklist
  quests beside Explore, with Outings, Goals/Tips detail, automatic Backyard
  Safari Level 1 enrollment, explicit start for other standard outings,
  curated tips, profile pins, following-weighted Community discovery, and a
  compact account-cached visual Scan target that opens the relevant field trip
  guide. The active level shows a circular progress ring; completed standard
  goals use the exact device-local scan thumbnail and open that Insight inside
  the same Explore sheet when the record is available. Saved biological Insights
  also keep a persistent **Field trips** card listing every outing or visible
  Event credited by that scan. Its rows show the experience name without a
  redundant level label and open the owning Goals overview in the current
  navigation stack, with Back returning to the Insight. Backyard Safari starts
  at Level 1 for every account, other standard outings require explicit start,
  and Events require join; a scan may advance several active
  experiences but credits at most one goal in each. Unreviewed AI evidence must
  be at least a tier-specific **Possible match** (75% Flash / 65% Pro); a weaker
  match remains pending until confirmation or correction. Scan ingestion applies
  standard/Event progress and first-outing achievement state atomically, retains
  a private idempotency receipt for recovery after termination, and keeps the
  durable Capture goal hint until acknowledgement. Field trip database entry
  points are service-role-only behind the authenticated Edge API, while trigger
  and reconciliation helpers remain database-only; direct client roles cannot
  call ownership-bearing RPCs. The auto-enrolled starter uses the existing
  profile-visible status-only summary, including at `0/N`, without publishing
  scan evidence. Saved scans still show contextual progress toasts
  with a credited ring and tap-through navigation before any achievement or New
  to Naturebook notification from the same scan. Publication storage stays
  separate from Explore posts; typed Field trip cards can appear in unfiltered
  Recent and Following, but not in Explore maps or the other post-only surfaces.
  Events are public for every user and include curated seasonal challenges,
  completion badges, published entries, and optional challenge hashtag
  suggestions. Their UI is part of Field trips rather than a separate client
  release flag.
- Explore cards and public share text can show confident dog/cat pet labels
  without replacing the stored species common/scientific names used for
  dictionary links and statistics.
- Explore posts support image, short-video, and standalone-audio media
  snapshots.
- Compact Explore/profile grids render standalone-audio posts with the species
  reference photo and a waveform badge; full post media remains the playable
  spectrogram.
- Explore feed videos autoplay muted whenever the feed is entered or resumed;
  post detail inherits the feed's current choice, then returning to the feed
  resets playback to muted.
- Feed audio and video use a dedicated center Play/Pause hit zone, while taps
  elsewhere on the media continue opening post detail and double taps like.
- Standalone-audio playheads in Explore feed, Explore post detail, and completed
  scan Insights follow the audible player clock smoothly and hold their exact
  position while playback is paused, buffering, or being repositioned.
- Standalone Explore audio posts offer an optional device-local “Boost audio”
  listening mode from feed and detail menus, remembered independently per post
  without changing the original recording.
- Completed scan-library Insights with standalone audio offer the same local
  listening boost, remembered separately per private scan and applied to every
  audio clip in that scan without changing stored media.
- The Scans library represents standalone-audio scans with their species
  reference photo and a waveform badge, while opening the scan retains the
  spectrogram-first playback experience. Audio shares are fail-closed: the
  server evaluates speech and non-speech sounds before creating or reactivating
  the Explore post, so only an approved share becomes public. Content-addressed
  attestations safely avoid repeat Gemini calls when the bytes, model, and
  policy contract are unchanged. Feed and detail reuse the shared AVPlayer host
  for video/audio, while maps, widgets, and compact profile previews stay
  thumbnail-first.
- Legacy audio scans can be shared when their original local recording still
  exists: the app repairs durable R2/scan media first, then runs the same
  fail-closed publication gate. Deleted legacy recordings remain unrecoverable.
- Author profiles open inside the Explore navigation stack, expose
  privacy-scoped public stats, non-opening public achievements, and
  active/published Field trip previews, and cap profile-to-scan nesting after
  one profile hop. A non-self visible profile can be reported from its overflow
  menu with a bounded reason/detail form; reporting opens a grouped internal
  review case and does not block the user automatically.
- Home Screen widget caches thumbnail-first visual Explore snapshots through the
  shared App Group, renders video posts as clean still thumbnails, and excludes
  audio-only posts.
- Public Explore share pages render visual posts at
  `https://naturebook.earth/explore/post/{postId}` through the Next.js web app.
  Detail pages use a square ordered image/video/audio carousel: videos autoplay
  muted on a loop while selected, and WAV audio fills the frame with its
  persisted spectrogram plus user-initiated controls and optional browser-local
  Boost Audio. The public home grid uses species reference thumbnails for audio
  posts, while social metadata retains the spectrogram. Legacy non-WAV posts
  keep playback plus the speaker fallback. Audio-only posts remain excluded from
  Home Screen widgets.
- Loaded Species Dictionary pages share readable UUID-first links at
  `https://naturebook.earth/species/{speciesId}/{slug}`. The UUID stays
  authoritative, while UUID-only and stale-slug browser links permanently
  redirect to the current readable canonical URL. Installed apps select
  Explore Identify/Index before opening species detail; browser recipients get
  the server-rendered public reference page with attribution-approved imagery
  and no scan- or user-specific data.

### Native Share Extensions

- Messages app extension surfaces a cached, searchable scan library inside
  iMessage and lets users insert a scan image, rich Naturebook card, or text
  description into the compose field.
- Shared App Group cache files keep shipped extensions lightweight while the
  main app owns SwiftData and scan reconciliation.
- Photos-to-Naturebook import is not an extension: the `public.image` document
  association opens the containing app and copies one shared file into its
  private pending-import inbox.

### Profile & Gamification

- Running species count, current scan streak, and longest streak.
- 52-week rolling contribution heatmap (year and month viewports).
- 13 achievement awards across categories: observation milestones, taxonomy
  specializations, environmental conditions, conservation engagement, and
  capture technique. Awards surface with smart sort: recently unlocked →
  in-progress → legacy.

### Settings

**General preferences** — theme (system/light/dark), an optional fresh-launch
Explore destination, Notifications, system haptics, and geoprivacy. **Pro** —
multi-capture scans and expedition mode. **Workspace** — camera and audio
preferences, **Reorder modes**, the on-by-default Camera field trip-goal overlay
and selected-goal preference, and scan-submission confirmation. This setting
does not disable server-side progress or the persistent Insight card.
**Geoprivacy** — open, obscured (~10km), or private; configurable per account
and synced to Supabase. **Notifications** — species discovery alerts,
achievement milestone alerts. **Changelog** — bundled feature notes, release
notes, and selected in-progress work. **Export** — staged Darwin Core Archive
(DwC-A) data export for academic/research use; hidden and server-disabled for
the initial production launch. **Account** — Sign in with Apple or Google,
anonymous Ghost Sessions, and durable account deletion that detaches retained
scientific observations from the account, queues media cleanup, and removes
the backend Auth identity only after database, storage, and any stored Apple
provider credential are verified complete. Pre-rollout Apple accounts receive
a durable manual-revocation notice because no server token exists to revoke.
An independent scheduled
health check alerts when the reaper is unconfigured, work is overdue, leases
expire, or the deletion backlog breaches its SLA. See the
[scientific-observation retention contract](docs/backend-and-data/17-scientific-observation-retention.md).

---

## Architecture

### Thermal & Memory Management

- `HardwareOrchestrator` monitors `ProcessInfo.thermalState` and
  `isLowPowerModeEnabled`, dynamically capping framerates (60fps → 24fps) and
  dropping glassmorphism shaders under thermal pressure.
- Expedition Mode allows users to force the 24fps/low-fidelity pipeline manually
  for off-grid battery conservation. This is separate from Explore Field trips.
- `ViewfinderIntelligence` throttles frame analysis to 3fps via `NSLock` before
  any `@MainActor` context switch, preventing GPU thermal spikes from the luma
  evaluation loop.

### Offline-First Data Pipeline

- `OfflineQueuedScan` (SwiftData) persists captures with full telemetry when
  inference fails or connectivity is absent.
- `NWPathMonitor` enters through `OfflineJobScheduler` on reconnection. The
  scheduler reconstructs one real wake from persisted scan/job retry deadlines
  after reconnect, foreground, or relaunch; atomic claims clear the deadline
  before background `URLSession` work begins.
- Every inference claim persists its UUID beside the queue transition. Claims,
  retries, result saves, URLSession cancellation, and guarded queue deletion
  compare that durable generation under one per-scan persistence coordinator, so
  a delayed callback cannot clear or cancel replacement work.
- `HistoricalDatabaseActor` reconciles paginated cloud sync into SwiftData in a
  single pass, with push-before-pull ordering to prevent unsynced local
  collections from being treated as obsolete.

### Zero-OOM Design

- All heavy database work runs through `@ModelActor` isolation:
  `BackgroundDatabaseActor` (live saves), `HistoricalDatabaseActor` (cloud
  sync), `SearchDatabaseActor` (search index builds), `FileIOActor` (image I/O).
- 48MP ProRAW library imports route through `ImageIO` with explicit bounds,
  blocking RAM cache inflation that causes JetSam kills.
- Local and remote thumbnail decoding uses a cancellation-aware four-permit pool
  plus an explicitly QoS-tagged ImageIO queue. Excess work suspends without
  blocking user-initiated threads, preventing priority-inversion hangs while
  preserving the decode concurrency ceiling.
- Image pipeline produces a 1024px JPEG for inference and a 2048px JPEG for
  display in a single pass.
- Search index uses O(1) delta updates — only added/removed scans are
  reprocessed, never the full library.
- Every production Edge JSON endpoint uses a capped streaming reader with an
  endpoint-class budget, strict JSON content type, declared/actual length
  agreement, and stable request IDs. Media handlers retain explicit larger
  ceilings for reviewed payloads and bounded R2 responses, so missing
  `Content-Length` and chunked bodies cannot allocate beyond the Deno isolate
  budget before rejection. Unexpected server failures return a generic public
  code while provider, schema, and implementation details remain in
  request-correlated server logs.
- Outbound Edge calls combine caller cancellation with provider deadlines and
  stream response bodies through endpoint-specific ceilings before parsing. CI
  rejects production modules that bypass the reviewed HTTP or signed-R2
  adapters.

### Identity & Monetization

- Anonymous IDFV-backed Ghost Sessions (zero-friction, no sign-up required at
  launch).
- Sign in with Apple / Google OAuth preserves the Ghost UUID through
  `linkIdentityWithIdToken`; existing-account conflicts use a provider-bound,
  one-use `/merge-ghost-profile` handoff, an atomic database merge, and durable
  Auth cleanup. Pending proofs survive restarts in a device-only Keychain queue
  for the 30-day recovery window. The pending schema-aware hardening adds
  policy-reviewed ownership and durable provider-state repair and remains gated
  by the
  [Supabase deployment runbook](docs/backend-and-data/06-supabase-deployment-runbook.md#ghost-account-merge-security-rollout).
- Apple sign-in also sends the one-use authorization code to an authenticated
  Edge endpoint immediately after Supabase session installation. The server
  verifies both Apple identity tokens, binds their subject to the Auth identity,
  and stores only the refresh token in Vault. Registration failure clears the
  new local session so later account deletion is never represented as
  automatically revocable without a durable credential.
- RevenueCat webhook verifies a timestamped raw-body HMAC, reconciles
  authoritative subscriber state, and applies idempotent, monotonically ordered
  `free` ↔ `pro` transitions. Transfers reconcile source and destination in one
  transaction. Recurring/grace expiry is persisted, timed access has a local
  expiry fail-safe, and a durable scheduled CustomerInfo sweep deadline-drains
  small leased waves to repair missed deliveries. Expired leases are indexed,
  and an independent monitor alerts on oldest due age. Existing scan media
  remains in place.
- RevenueCat project-level Pro billing enables developer integrations; it does
  not grant customer access. Store trials activate through receipts without a
  manual per-user approval, while beta access is a finite promotional `pro`
  grant. The only case-sensitive App User ID generated by Merian is the
  uppercase Supabase UUID. Customer counts need not match Supabase.
  Explicit-cohort selection, get-or-create `201`, exact stable-identity
  provider-mutation gates, provider-preserving Ghost merge, and guarded
  empty-shell cleanup are implemented in source. Ghost accounts may purchase and
  receive beta Pro; generic `401` responses preserve their UUID instead of
  creating another Supabase and RevenueCat customer. User-facing Continue as
  Ghost also retains the same linked UUID and app data. Provider grants and
  cleanup still require the exact reviewed production-operation evidence in the
  [RevenueCat identity incident](docs/incidents/2026-08-revenuecat-customer-identity-drift.md).
- Free receives one primary Flash scan per UTC day. The staged introductory
  offer replaces the calendar trial with three lifetime complimentary Pro
  scans per account; complimentary holds settle independently from provider
  quota and do not combine into six credits during Ghost-account merge. Paid
  Pro removes the ordinary product cap and receives Gemini 2.5 Pro, video
  scans, AI chat, multi-capture, Apple Watch logging, expedition mode, and
  offline queue; database fair-use ceilings still bound automated provider
  traffic. Every public AI route atomically resolves entitlement, selects its
  model, and reserves per-user/IP quota before provider dispatch. The iOS
  `UserDefaults` meter is advisory, and its debug-only bypass cannot change
  server capacity. Protocol-3 iOS admission serializes one stable
  account/scan funding reservation before local media writes, subtracts
  unresolved reservations from verified capacity, and defers later
  Flash-eligible work until earlier server settlement is known.
- Pro follow-up chat is served by a Supabase Edge Function using Gemini 2.5
  Flash against stored scan evidence only; the same function also generates
  short, scan-specific prompt chips from private text context.

### Evidence Retention

- Biological scan media is intended to be durable regardless of subscription
  tier. Supabase Postgres stores scan/post rows and R2 URLs; Cloudflare R2
  stores the referenced bytes. A surviving database URL is not an object backup.
  Temporary staging, quarantine, and export objects still expire quickly, while
  durable free/Pro upload and avatar prefixes must have no age-based expiration.
  Non-biological scans are cleaned up after the retention window.
- When a durable object is independently missing but a strongly matched
  Documents file survives, the app can render the local copy and use an
  owner-authenticated promotion plus one metadata transaction to repair both
  Scan Library and matching Explore references.
- Explore media loss never auto-deletes or auto-unpublishes a post. Two spaced
  direct R2-origin `404` checks confirm a primary object as missing. The public
  projection omits only bad items and reversibly quarantines an all-missing post
  while preserving its row, publication intent, likes, and comments. Verified
  repair automatically restores ordinary visibility.

### Privacy

- The final onboarding screen states, “Naturebook sends observation data to
  Google Gemini for AI-powered identification.” Scanning requires current 18+
  self-attestation, Terms acceptance, and Gemini data-sharing permission.
- PostHog app usage and diagnostics are optional, account-wide, default-off in
  the absence of a grant, and withdrawable without changing core functionality.
  The implementation findings are closed in source; the candidate remains
  production-held on exact-SHA rollout evidence and external controls in the
  [consent readiness record](docs/legal/production-consent-readiness-2026-08-03.md).
- Geoprivacy is enforced server-side: `obscured` rounds coordinates to ~10km;
  `private` strips location entirely. Endangered species coordinates are
  automatically offset by 50km regardless of user setting.
- Global DwC-A exports replace user IDs with versioned, domain-separated
  HMAC-SHA256 pseudonyms under a dedicated export key, preserving longitudinal
  attribution without exposing or reusing Supabase credentials. Public callers
  can queue personal exports only. Job creation incrementally freezes bounded
  occurrence and multimedia DTOs from one MVCC snapshot; the worker persists
  keyset cursors and claim-fenced CSV byte-count/CRC manifests across bounded
  phases with canonical row/archive budgets. Every source member is
  privacy-revalidated before assembly, delivery, and every download. Export
  recipients receive a revocable application capability, not a one-day storage
  signature; authorized clicks produce only a 30-second read-only redirect.
  Revoked/expired archives enter a leased cleanup outbox. Final ZIP checksum
  assembly composes bounded chunk CRCs instead of rescanning the complete
  archive in JavaScript.
- Account deletion preserves login access through relational account detachment
  and cursor-persisted R2 erasure. It waits for a delayed empty verification
  sweep, then revokes any stored Apple refresh token before removing Auth; a
  scheduled reaper resumes every phase after a crash. The database refuses an
  R2 storage claim unless the matching private
  deletion job is `storage_pending` after relational cleanup, and vetoes the
  claim while a live profile or owned scan remains. An outbox row alone is never
  deletion authority. Apple-linked legacy accounts without a captured token
  complete deletion with an explicit manual-revocation disposition that iOS
  persists across sign-out and relaunch. A separate five-minute monitor reads only aggregate
  service-only health and detects missing reaper credentials, a disabled cron,
  retry failures, expired leases, and age/backlog SLA breaches.

---

## Tech Stack

| Layer          | Technology                                                              |
| -------------- | ----------------------------------------------------------------------- |
| iOS client     | Swift 6, SwiftUI, SwiftData, AVFoundation, CoreLocation, Vision, MapKit |
| Web frontend   | Next.js, React, Mantine                                                 |
| Backend        | Supabase (PostgreSQL, Deno Edge Functions)                              |
| Cloud storage  | Cloudflare R2 (S3-compatible)                                           |
| AI model       | Google Gemini 2.5 Flash / Pro                                           |
| Payments       | RevenueCat                                                              |
| Analytics      | PostHog                                                                 |
| CI/CD          | GitHub Actions                                                          |
| Email Services | Resend                                                                  |

“S3-compatible” describes Cloudflare R2’s request/signature protocol only.
Merian does not use Amazon AWS storage or compute; Supabase remains the backend
and authorization boundary.

**Minimum deployment target**: iOS 17.2 **Current schema**: MerianSchemaV50

---

## Getting Started

### Prerequisites

- macOS Tahoe 26.2 or later, as required by
  [Xcode 26.6](https://developer.apple.com/xcode/system-requirements/)
- Xcode 26.6 to match compiled CI and Release archive validation
- `xcodegen` (`brew install xcodegen`)
- Supabase CLI

### Setup

```bash
git clone https://github.com/your-org/merian.git
cd merian
cp Signing.local.example.xcconfig Signing.local.xcconfig
cp Config.local.example.xcconfig Config.local.xcconfig
xcodegen generate
open Merian.xcodeproj
```

Set `MERIAN_DEVELOPMENT_TEAM` in `Signing.local.xcconfig` to your Apple
Developer Team ID before opening the project. This file is ignored by git so
your local signing choice survives `xcodegen generate`.

Keep the shared project on automatic signing and do not set
`CODE_SIGN_IDENTITY` in `project.yml` or an `.xcconfig`. Xcode chooses Apple
Development for local Run/Test actions and Apple Distribution for an authorized
archive; forcing the distribution identity conflicts with automatic signing on
the widget, Messages extension, and watch app.

`Merian.xcodeproj` is committed for convenience, but `project.yml` remains the
source of truth. Regenerate the project after target, package, build setting,
entitlement, or source-group changes.

Pull requests report the stable `iOS Build and Test / Production readiness`
check. Relevant iOS, watch, project, configuration, and build-tooling changes
must pass the complete `merianTests` target and an unsigned Release archive from
the exact workflow SHA before shipping. The workflow reports the check but
cannot make it merge-blocking by itself; require that exact final check in the
repository ruleset. See the
[compiled iOS CI gate](docs/development-guides/08-testing-strategy.md#compiled-ios-ci-gate)
and
[release checklist](docs/development-guides/14-ios-release-versioning.md#routine-testflight-upload).
The authority boundary is recorded in the
[Xcode release architecture](docs/system-architecture/09-ios-release-publisher.md).

Configure the required app-facing client config in `Config.xcconfig` or ignored
local overrides in `Config.local.xcconfig`. Public client values like
`SUPABASE_URL` and the public key configured through the historical
`SUPABASE_ANON_KEY` build setting are used by the app at runtime; use a current
`sb_publishable_...` value rather than a legacy anon JWT. True backend secrets
like `GEMINI_PAID_API_KEY` must stay server-side only. Unsigned validation archives
do not ship. Xcode Release archives require the production RevenueCat iOS SDK
key beginning with `appl_`.

### Common Shortcuts

From the repo root:

```bash
make xcodegen
make validate-ios-privacy-manifest
make validate-ios-transport-security
make validate-ios-versioning
make test-ios-ci-tooling
make db-push
make functions-deploy
```

Normal local builds never increment the app version or build. For routine beta
testing, wait for exact-SHA **iOS Build and Test**, then use Xcode
**Product → Archive** and Organizer **Distribute App → TestFlight & App Store →
Upload**. Keep automatic signing and **Manage version and build number**
enabled. Xcode and App Store Connect own the uploaded build number; promote the
same processed build through TestFlight and App Review. See the
[iOS publishing runbook](docs/development-guides/14-ios-release-versioning.md)
for setup, upload, promotion, and incident-safe recovery.

### Release Notes & Changelog

User-facing release documentation lives in three places:

- `CHANGELOG.md` for TestFlight, App Store, QA, support, and human release
  planning.
- `apps/ios/AppStore/ReleaseNotes/<marketing-version>.md` for the reviewed
  per-train App Store listing and “What's New” source.
- `apps/ios/Merian/Resources/Changelog/changelog.json` for the bundled in-app
  Settings changelog.

See `docs/development-guides/12-in-app-changelog.md` before adding in-app notes,
images, or deployment summaries.

### Local Web

The public web surface lives in `apps/web/`.

```bash
cd apps/web
cp .env.example .env.local
npm install
npm run dev
```

The web routes include `/explore/post/[postId]`, a server-rendered public
Explore share page with Open Graph metadata; `/species/[speciesId]/[slug]`, the
licensed public Species Dictionary page, with `/species/[speciesId]` retained as
a permanent compatibility redirect; and the allowlisted `/api/explore/audio`
stream used only for browser-local Boost Audio processing, plus public
policy/support pages at `/privacy`, `/terms`, `/guidelines`, `/privacy-choices`,
`/support`, and `/legal`.

The generic **Share Naturebook** action intentionally uses the served homepage
before the App Store listing is live. There is no `/invite` route or referral
program. Once the listing is publicly reachable, replace the explicit iOS TODO
with the reviewed App Store Connect campaign link and configure the same
campaign destination for the public-web download CTA.

See `apps/web/README.md`,
`docs/features-and-hardware/17-public-web-share-pages.md`, and
`docs/development-guides/15-naturebook-rebrand-rollout.md` for the web env
contract, share URL strategy, Universal Links, production verification, and
rollout steps.

For Vercel production, configure the project Root Directory as `apps/web` and
attach `naturebook.earth`, `naturebook.app`, their `www` aliases, and the legacy
`merian.earth` aliases to that project. A plain Vercel `404: NOT_FOUND` response
means the request has not reached the Next.js app. Use only the environment
variables allowlisted by `apps/web/.env.example`; never mirror GitHub
`Production` secrets or direct database credentials into Vercel. Public Explore
server rendering requires `SUPABASE_URL` plus the validated
`SUPABASE_SERVER_API_KEY`; the browser-facing `NEXT_PUBLIC_SUPABASE_ANON_KEY`
cannot execute that scoped server projection. The exact GitHub, Supabase Edge,
public-web, and internal-admin ownership matrix is documented in
[`docs/development-guides/05-keychain-and-secrets.md`](docs/development-guides/05-keychain-and-secrets.md#deployment-environment-ownership).

### Local Internal Admin

The private operations application lives in `apps/admin/` and is deployed as a
separate project at `admin.naturebook.earth`.

```bash
cd apps/admin
cp .env.example .env.local
npm ci
npm run dev
```

Admin changes receive an independent quality check from
`.github/workflows/admin-quality.yml`, which performs a frozen install,
high-severity dependency audit, unit tests, TypeScript checking, and a
production build. To make that check a release gate, GitHub repository rules and
the admin Vercel project must require `Naturebook Admin Quality / test`, with
the GitHub Action added as a required Vercel Deployment Check. The workflow file
creates the check but does not independently block a direct merge or production
promotion.

The admin app accepts only the public Supabase URL/key and requires an existing
Google Auth user, private admin membership, and verified TOTP AAL2. Never add a
service-role key or analytics token to this deployment. See
`apps/admin/README.md`, `docs/backend-and-data/10-internal-admin.md`, and
`docs/backend-and-data/11-internal-admin-operations.md` for setup, role,
security, bootstrap, deployment, and recovery procedures.

### Local Backend

From the repo root, point the Supabase CLI at the backend service directory:

```bash
supabase --workdir services start
supabase --workdir services functions serve identify
```

### Database Migrations

```bash
supabase --workdir services db push
```

### Edge Function Deploys

```bash
supabase --workdir services functions deploy
```

That is the emergency manual full-fleet command, not a candidate-validation
path. Use **Supabase Candidate Validation** to replay and test an exact SHA in a
disposable database without production secrets or mutations. Its stable
readiness check reports on every pull request, and its fail-closed scope job
requires complete validation for every input inspected by the candidate suite.
Production deployment runs through the path-filtered GitHub workflow, which
validates frozen function-local dependency graphs, requires exact name parity
with `services/supabase/config.toml`, and deploys only transitive runtime
consumers in bounded batches. The fleet size is derived rather than hard-coded.
Before reporting success, it derives that same
canonical inventory and verifies that every production route reaches code with
`X-Merian-Handler: 1`. The two intentional gateway-verified routes receive only
a validated legacy anon JWT for this preflight; a publishable key is never sent
as Bearer, and rollout fails closed if the required execution credential is
unavailable. It separately verifies that `identify-multimodal`,
`check-scan-status`, Explore sharing/composer media, and Field Chat fail closed
without user Authorization, along with Ask the Community creation. Exact
non-mutating SQLSTATE probes also verify the three required scan/publication
RPCs are live for server authority and denied to real public project
credentials; a transient Supabase gateway `404` remains a failed or in-progress
rollout. Static caller coverage rejects a route literal from any application
target, workflow, worker, script, or active migration when it has no configured
entrypoint. Scan-producing routes treat at-least-once delivery as idempotent
success: the same owner/scan UUID replays its validated response as HTTP `200`
without a second AI provider call instead of surfacing an internal quota or
completion `409`. Existing completed rows can be reconstructed through the same
wire contract. See the
[July 2026 Identify idempotency incident](docs/incidents/2026-07-identify-idempotency-conflict.md).
Current opaque Supabase server keys use only the standard `apikey` header;
legacy service-role JWTs temporarily use both `apikey` and Bearer. Credential
sources are classified independently so a stale migration slot cannot veto an
exact valid key, and production rollout requires the synchronized Edge secret's
stored digest to match the selected key. Exposed tables require RLS and reviewed
grants, and new migrations leave transaction and history ownership to the pinned
CLI. Top-level timeout guards use session settings with matching resets so fresh
replay cannot silently ignore them. See the
[server credential and database safety
contract](docs/backend-and-data/13-server-credentials-and-database-release-safety.md)
and
[Supabase deployment runbook](docs/backend-and-data/06-supabase-deployment-runbook.md).
The complete review inventory and remaining production evidence are recorded in
the
[2026-07-28 Edge Function fleet review](docs/backend-and-data/15-edge-function-fleet-review-2026-07-28.md).

---

## Documentation

Extended architecture documentation lives in `docs/`:

| Directory                                                         | Contents                                                                                                        |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `docs/codebase-map.md`                                            | Current target/module/function/schema map generated from this repo state                                        |
| `docs/system-architecture/`                                       | Data flow, concurrency model, zero-OOM patterns, AI engineering                                                 |
| `docs/features-and-hardware/`                                     | Camera pipeline, hardware orchestration, feature module breakdowns                                              |
| `docs/features-and-hardware/17-public-web-share-pages.md`         | Public Explore/species share-page contracts, media/privacy rules, and Universal Links compatibility             |
| `docs/backend-and-data/`                                          | Edge function contracts, database schema, offline sync, API contracts                                           |
| `docs/backend-and-data/10-internal-admin.md`                      | Internal admin architecture, security boundary, roles, metrics, moderation, and AI ledger                       |
| `docs/backend-and-data/11-internal-admin-operations.md`           | Internal admin setup, deployment, access recovery, pricing, and incident runbook                                |
| `docs/backend-and-data/12-explore-media-health-and-quarantine.md` | Reversible Explore media-loss policy, origin verification, owner communication, recovery, security, and rollout |
| `docs/backend-and-data/18-complimentary-pro-scans.md`             | Normative three-credit ledger, reservation, settlement, protocol, iOS, merge, security, and rollout contract     |
| `docs/backend-and-data/19-security-and-reliability-remediation-2026-08-03.md` | Joined collection, upload, funding, redirect, taxonomy, rollout, and evidence record |
| `docs/legal/production-consent-readiness-2026-08-03.md`         | Canonical adult, Terms, Gemini, analytics, source status, exact-SHA evidence, and release-hold record                 |
| `docs/development-guides/16-ios-privacy-manifest.md`            | App privacy declarations, required-reason inventory, maintenance rules, and archive/App Store evidence               |
| `docs/development-guides/`                                        | Core managers reference, app lifecycle, testing strategy                                                        |
| `docs/incidents/`                                                 | Incident evidence, cause confidence, containment, recovery limits, and production exit criteria                 |
| `docs/rfcs/active-capture-goal-context.md`                        | Long-term source-agnostic Capture goal architecture and extension contract                                      |

---

## Legal

Naturebook is a tool for education, discovery, and conservation. Usage is
subject to the terms of the Google Gemini API, Supabase, and Apple platform
guidelines. Public copy lives in the
[Terms of Service](apps/web/app/terms/page.tsx) and
[Privacy Policy](apps/web/app/privacy/page.tsx). Release and counsel review are
tracked separately in the
[consent readiness record](docs/legal/production-consent-readiness-2026-08-03.md),
the [iOS privacy manifest contract](docs/development-guides/16-ios-privacy-manifest.md),
and the [counsel memo](docs/legal/terms-counsel-review.md); none is legal advice or a
substitute for owner/counsel approval.
