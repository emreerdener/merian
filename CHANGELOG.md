# Changelog

Notable user-facing changes are collected here as release-note source material.
Keep detailed code history in git; keep this file focused on what matters for
TestFlight, App Store, support, and QA.

## Unreleased

### Sign in with Apple Account Deletion — Release-Gated

- New Apple sign-ins now require the authorization code as well as the identity
  token. Naturebook exchanges the code server-side, verifies the Apple subject,
  and stores the refresh token encrypted in Supabase Vault for later deletion.
- Account deletion now has a durable provider-revocation stage after verified
  media erasure and before Supabase Auth removal. Apple outages or
  configuration failures retain the login and encrypted credential for a
  claim-fenced retry instead of silently skipping revocation.
- Apple-linked accounts created before token capture remain deletable and
  return an explicit legacy disposition. iOS records that disposition before
  sign-out and keeps showing Apple's manual removal steps until the user marks
  them complete.
- Apple credential-revocation notifications now trigger a subject-bound
  credential-state check. A still-authorized identity keeps its session;
  revoked, missing, transferred, unknown, or failed state resolution clears
  only the matching Apple-linked local session.
- Source implementation is complete, but public promotion remains gated on
  production Apple key provisioning, exact-SHA disposable database replay, a
  real exchange/revoke smoke, and either an enforceable
  minimum-supported-build gate or an independent server-delivered manual
  fallback for older iOS binaries. See the
  [canonical Apple deletion contract](docs/backend-and-data/20-sign-in-with-apple-account-deletion.md).

### Consent and Privacy Controls — Release-Gated

- Cold launch now keeps completed users on a launch-matched restoration surface
  while account consent is reconciled, instead of briefly flashing the approval
  screen before opening the scanner. This now includes an expired cached
  Supabase session: its known account remains in restoration while the SDK
  refreshes the access token, and only the later refresh or signed-out result
  may advance the root.
- A failed consent restore no longer behaves like proof that consent is absent.
  The neutral surface now offers **Try Again**, performs three bounded retries,
  preserves its budget across duplicate auth notifications, and rejects stale
  retry work after account or synchronization-generation changes.
- The final onboarding screen now combines 18+ self-attestation, required Terms
  and permission to send observation data to Google Gemini for AI-powered
  identification, and a separate optional analytics choice. Existing beta users
  return directly to that screen only when account reconciliation confirms that
  current evidence is absent.
- Versioned adult, Terms, Gemini, and analytics actions use an append-only local
  ledger and immutable account-owned Supabase evidence. Settings exposes the
  optional account-wide **Analytics & diagnostics** switch under Resources and
  intentionally provides no Gemini processing opt-out.
- The retained Gemini and analytics wording now uses fresh disclosure versions,
  forcing a new user action without rewriting any earlier beta evidence.
- Account switching now revalidates the observed user, Supabase SDK session,
  cancellation state, and synchronization generation inside the final consent
  merge before any local evidence or analytics state can change. A separate
  validation-only Supabase workflow provides fresh-catalog and concurrency
  evidence without receiving production credentials or deploying anything.
- Restored accounts now hold analytics in an explicit remote-authority wait
  state before cached consent is refreshed or applied. PostHog can reopen only
  after the current account's authoritative grant survives the final verified,
  identity-fenced ledger write; remote absence, revocation, fetch failure, or
  persistence failure remains off.
- Cross-device Gemini and analytics changes now use a server-serialized causal
  revision. If one device revokes permission while another holds an older
  offline grant, the delayed grant is rejected instead of becoming current when
  it reconnects. If an older offline revocation reconnects after a newer grant,
  the server rebases and accepts the withdrawal so permission remains deny-wins.
  Gemini authorization, PostHog delivery, and iOS permission gates all resolve
  that provider-wide, all-disclosure head before checking grant compatibility.
- Supabase candidate assurance now reports a stable result on every pull
  request. Its full-history scope detector includes every app, documentation,
  workflow, script, and backend root inspected by the executable contracts and
  requires complete validation for unresolved ranges or unclassified new roots.
- Onboarding now completes only after its versioned consent evidence is saved
  and read back successfully. Analytics withdrawal closes capture immediately
  and keeps an independently persisted, replayable withdrawal journal, so a
  failed ledger write cannot restore a previous grant after relaunch.
- All tracked consent findings are closed in source. Internal test builds may
  continue, but public production and strict server cutover remain held until
  exact-SHA validation, replacement-build rollout, disposable database replay,
  and the operator evidence in
  [`production-consent-readiness-2026-08-03.md`](docs/legal/production-consent-readiness-2026-08-03.md)
  are complete. Do not publish these bullets as App Store release notes before
  production approval.
- The main iOS app now bundles its own validated privacy manifest, declaring no
  tracking and the reviewed reasons for app-only user defaults, local file
  metadata, and low-storage write admission. Source, archive, and exported-IPA
  guardrails are in place; public promotion still requires the signed archive's
  aggregate Xcode privacy report and reconciled App Store privacy answers.
- The main iOS app now retains App Transport Security defaults. Configured
  origins, signed transfer URLs, avatars, and remote observation/reference media
  must be credential-free HTTPS, and source/archive/exported-IPA guardrails
  reject insecure exceptions or origins.

### Three Pro Scans Included

- Every existing and future account receives three Pro scans with no calendar
  expiration. The separate daily Flash scan remains available, so the
  introductory grant does not replace ordinary free access.
- Results and Settings show the server-verified number remaining. After the
  third usable Pro result, saved Pro results stay fully viewable and an upgrade
  action replaces access to new Pro-only analyses.
- Ordinary single-photo, standalone-audio, and description scans fall back to
  the daily Flash policy after exhaustion. Video, multi-item or mixed scans,
  refinement, and other Pro-only actions continue to show the soft paywall.
- Included Pro scans now follow retry-safe original-analysis linkage: a durable
  usable result consumes one scan, a proven terminal failure releases it, and
  ambiguous recovery cannot spend another credit. Paid subscriptions and the
  paid **7 Day Pass** remain unchanged.
- Offline admission now reserves one verified included Pro scan per stable scan
  before local media is written. Later eligible work waits safely, survives
  relaunch, and reclassifies after server settlement or a purchase instead of
  over-admitting stale capacity and ending in needs-attention.

### Safer Collection Synchronization

- A stale or colliding foreign collection ID is skipped without changing its
  owner or blocking unrelated albums. Collection memberships now require both
  the album and observation to belong to the same account at every database
  write boundary.

### Bounded Media Staging

- Direct R2 uploads now require an exact declared file size. Signed upload
  responses declare the MIME and length headers the app must send, and a file
  changed after signing is re-signed instead of uploaded under stale limits.
- Legacy upload requests without per-file sizes are rejected, closing the path
  that could stage arbitrarily large temporary objects.

### Redirect and Taxonomy Reliability

- Admin OAuth and public-domain redirects now preserve valid local paths while
  pinning every destination to its configured origin, including under hostile
  Host, protocol-relative, backslash, and encoded-separator inputs.
- Bounded GBIF imports now checkpoint successfully fetched pages even when all
  raw rows normalize out, so one empty-normalization page cannot stall the
  taxonomy cursor forever.

### Non-biological Scan Navigation

- Non-biological scan notices now link directly to their collection in the
  scans library.

### Field Trip Card Layout

- Field trip catalog cards now place a larger current patch beside the title, show
  status pills before a compact goal preview strip, and finish with the
  existing state-aware action.
- Active Field trips on Explore profiles now pair the current-level patch and
  title with trailing circular goal progress, and open the corresponding Field
  trip page when the card is tapped.

### Biological Achievement Eligibility

- Scans identified as non-biological no longer advance, unlock, or appear in
  the qualifying details for nature and species achievements.

### Simpler Starter Outings

- Every new and existing account now starts in Backyard Safari Level 1, so its
  first goals are ready in Scan without a separate enrollment step.
- Active starter status can appear on the account's public author profile under
  the existing status-only Field trip contract; enrollment does not publish
  scans, media, notes, or location evidence.
- Backyard Safari and Park Pollinators now start with 2 goals, expand to 4 in
  Level 2, and finish with a new Level 3 while keeping valid credited scans.
- Backyard Safari's first goals are now Bird and Dog, with Dog requiring an
  exact domestic-dog identification instead of any domesticated animal.
- All six collectible level patches have refreshed embroidered artwork that
  reflects each level's updated discoveries.

### Save Photos and Videos to Photos

- **Save to camera roll** now applies to new camera photos and original-quality
  video recordings. The preference remains off by default and uses add-only
  Photos access.
- Single and batch **Download** actions now include retained video clips from
  local scans and approved Naturebook cloud media, with accurate photo/video
  counts and clear partial- or zero-save feedback.
- Video exports stay file-backed to avoid large memory spikes, and temporary or
  original source files remain available until Photos finishes importing them.

### Insight Media Fallbacks

- Video scans whose original clip is no longer available now retain one photo
  fallback—the stored poster or middle sampled frame—instead of showing a black
  video page. If no usable user photo or video remains, the carousel ends with
  the existing original-photo-unavailable state after any audio, description,
  and reference pages.

### Account Upgrade Reliability

- Anonymous-to-existing-account hardening now includes explicit schema-aware
  ownership policies, durable RevenueCat destination repair, consistent child
  lock ordering, and safe retry responses for species-ledger drift. Overlapping
  species history must merge without corrupting discovery totals, and
  unsupported database relationships must stop safely before user data changes.
- The existing-account conflict fallback remains release-gated until its
  exact-version disposable database replay, complete catalog, Edge, and
  concurrency suites, strict lint, and advisors have all passed the rollout
  runbook's automated evidence gates.
- Production now predeploys the compatible Ghost merge mapper before related
  migrations, records exact-SHA disposable-CI proof, and runs a privacy-safe
  post-deploy and scheduled health audit for prepared receipts, Auth cleanup,
  and destination RevenueCat repair. Rolling audit windows remain index-backed
  as merge history grows.

### Scientific Observation Retention

- Every submitted scan now has an explicit scientific-retention contract.
  Account deletion removes the login, profile, public attribution, community
  content, media, private free-form notes, and device or semantic-location
  context, but retains the contributed ownerless scientific observation with
  its exact coordinates, elevation, time, taxonomy, identification,
  environmental, quality, and provenance facts. Tombstones remain outside
  personal and anonymous scan access. The deletion confirmation, location
  permission text, Terms, Privacy Policy, and Privacy Choices page now state the
  same mandatory, non-optional behavior.

### Release Integrity

- Xcode Organizer is now the sole signed archive, build-number management, and
  App Store Connect upload path. Apple account access and private signing
  material remain in Xcode and the local Keychain instead of being duplicated
  as GitHub secrets.
- Routine TestFlight uploads use **Product → Archive** followed by Organizer
  **TestFlight & App Store** with automatic signing and **Manage version and
  build number** enabled. The tracked `CURRENT_PROJECT_VERSION` remains a
  synchronized archive baseline, so beta iteration no longer creates manual
  build-number commits or competing sequential counters.
- GitHub continues to compile, test, and create an unsigned exact-SHA Release
  validation archive, but it cannot sign or upload it. Guardrails reject the
  retired GitHub publisher workflows/scripts and any new CI Apple credential or
  Transporter path.
- Release archives retain clean source revision/fingerprint provenance. The
  processed App Store Connect build is promoted unchanged through internal and
  external TestFlight and App Review; changed source or configuration receives
  a fresh Organizer archive and Xcode-managed build number.

### Critical Scan Reliability

- The exact-SHA hosted iOS gate now executes the deterministic queued-audio
  completion handoff instead of merely compiling the UI-test bundle. Release
  evidence must show exactly one passed, unskipped
  `testQueuedAudioScanRetainsAudioAcrossCompletionHandoff` case: the queued
  observation opens inside Scans with native Back navigation and the shared
  scanning experience, then keeps its audio page when the completed analysis
  replaces it. The seed now writes a valid PCM WAV and the smoke waits for the
  decoded playback control before and after handoff, so a retained filename
  backed by missing or corrupt media cannot pass. Completion no longer races a
  fixed countdown: the exact Debug-only fixture advances only when the smoke
  taps the shared status badge after all queued-state and playback assertions.
  Its transaction now uses the exact environment `ModelContext` already bound to
  the open Insight sheet and immediately invokes the existing production
  queue-promotion path after saving, rather than depending on a late
  cross-context event merge. The open destination is promoted before the
  synchronous library event refreshes its parent, and any later rebuild treats a
  persisted completed record as authoritative over the retained queued route
  snapshot. Result toolbar and Field Notes tasks are keyed to the monotonic
  presentation generation rather than the unchanged scan UUID, so Field Chat,
  Share, and notes reconnect without reopening the scan. The library event is
  retained only to refresh the parent Scans surface. The smoke also requires the
  completed observation to expose its Field Chat and Share toolbar controls,
  guarding the downstream connections after queue promotion. The Explore
  replay-cancellation regression now waits against a bounded monotonic deadline
  for its observable first URLSession dispatch instead of assuming 100 executor
  yields are sufficient on every hosted simulator. It still requires exactly one
  request before cancellation and no replay afterward. Empty, duplicate-suite,
  duplicate-case, contradictory-suite, skipped, malformed, or wrong-test result
  evidence fails closed and retains a separate result bundle and log.
  Complete-unit critical evidence now applies the same exact-suite integrity:
  every protected case must appear exactly once under exactly one passed suite,
  and every allowlisted source name must resolve to one unique `@Test`
  declaration with any explicit display-name alias bound to that declaration.
  The deterministic UI seed implementation is now excluded from non-Debug
  compilation; Release retains only signature-compatible no-ops. The Release
  archive gate also scans the main binary and rejects any retained seed launch
  argument or queued-audio fixture marker, so TestFlight/App Store launch state
  cannot activate or contain its local data replacement path. The shared
  scanning badge now paints animated decoration inside fixed Canvas geometry,
  uses an opacity-only label transition, and preserves its native Button
  accessibility node. This keeps the queued completion handshake discoverable as
  `ScanningStatusBadge` while retaining the strict in-window frame assertion.
  Release preflight now separates unsigned validation archives from the sole
  serialized publisher mode and blocks Organizer/ad-hoc distribution archives.
  Tracked per-user Xcode scheme metadata has been removed and the fingerprint
  tool rejects any future `xcuserdata`, preventing asynchronous scheme-order
  rewrites from changing release-source identity.
- Scan Library recovery now distinguishes visible needs-attention rows from
  automatic queue work. Stable damaged/beta rows no longer keep the 1.5-second
  queue poll alive or repeatedly wake upload/inference reconciliation, while
  Retry immediately re-enables monitoring for a recoverable failed row. Legacy
  non-runnable import rows no longer offer Retry in either queue surface, and
  the retry mutation API rejects them before changing durable state. The
  observable unsynced count now includes only automatically runnable rows, so an
  attention-only staged record cannot indirectly retrigger queue work. Its count
  is read through a fresh SwiftData context so background-committed attention
  transitions cannot remain hidden behind a cached main-context fault. The
  serialized database actor independently rechecks attention and retry timing at
  upload/inference claim time and excludes paused rows from orphan
  reconciliation, so a stale candidate snapshot cannot mutate or launch work the
  user must explicitly retry. Pending selection now pages past older
  future-dated retry, deferred-live-upload, network-blocked video, and
  media-less legacy rows instead of letting them hide newer runnable scans.
  Media-less rows use a separate bounded quarantine budget, while the explicit
  user-forced video override remains eligible. Global status reconciliation now
  reads through the serialized queue actor and excludes attention-paused
  inference rows, preventing a stale main-context fault from reviving their
  status probes. Satisfied-path policy changes now count as recovery wakes:
  cellular-to-WiFi and Low Data Mode-to-normal transitions resume newly eligible
  work even when reachability never went offline, constrained drains stay
  disarmed, and a final pre-claim policy check prevents a stale WiFi snapshot
  from dispatching video after an async handoff. Upload batch packing now scans
  the full bounded candidate window, skips non-fitting rows in favor of later
  work that fits, and moves a malformed empty pending row to visible
  needs-attention instead of letting it block the queue indefinitely. Library
  polling now applies those same live online/constrained/large-upload rules:
  offline, Low Data Mode, and cellular-blocked pending-video rows remain visible
  without a periodic refresh/kick log loop, and satisfied-path policy changes
  restart the task only when work becomes eligible. Dispatch rechecks policy at
  task resume, every final PUT disallows constrained transport, and every
  manifest PUT for a non-forced video scan disallows expensive transport so an
  in-flight mixed-media WiFi handoff cannot partially consume cellular data.
  Automatic inference preparation, delayed status probes, ingestion polls, retry
  callbacks, and orphan-status checks now also revalidate an online,
  unconstrained path before network entry, preventing a mid-preparation Low Data
  Mode transition from issuing another request or spending retry budget.
  Connectivity and upload policy are now also rechecked immediately after the
  durable claim. A handoff while claiming or signing atomically returns both
  scan and job to runnable state without consuming retry budget, and all signed
  members for one scan start together or not at all, eliminating a partial
  dispatch that could wait forever for a callback from a task never created.
  That quarantine rechecks both state and media in the serialized actor, so a
  stale candidate cannot tombstone work another path already advanced.
- Missing-owner Explore and Ask the Community recovery now resolves and
  byte-validates surviving local observation media before reconstructing the
  cloud row. A beta record whose durable URL is 404 and whose local file is gone
  can no longer create an empty completed cloud scan before recovery discovers
  that it has nothing safe to publish. Share Edge also rejects a media-less
  `recovery_scan` and proves every supplied staging key's exact scan/kind/role
  ledger binding before invoking owner recovery, protecting older clients and
  malformed direct requests. Field Chat keeps its intentional metadata-only
  recovery path.
- Field Chat now binds every retained Insight conversation to its exact scan
  owner and enforces conversation, scan/post, viewer, message, and feedback
  identity in deferred composite database constraints instead of relying only on
  Edge arguments. Untrusted historical cross-bound private rows are removed
  before validation so one damaged row cannot make the strict client reject an
  otherwise healthy thread forever. The remaining Insight feedback Data API
  grants are also closed, and conversation-optional feature feedback is
  independently bound to its exact scan owner. Chat and feedback writes now
  share the authenticated Edge-only boundary, with exact RLS joins retained as
  defense in depth.
- Structured scan upload signing now rejects zero-byte files on both iOS and
  Edge before a background transfer starts. The shared media-staging contract is
  version 4 and records a one-byte minimum. Foreground playback-video staging
  applies the same positive-size rule before requesting a signed URL, rather
  than treating an existing but empty filesystem path as uploadable.
- Queued and staged captures now open as pushed destinations inside the Scans
  library navigation stack instead of layering another sheet over the library.
  Their waiting state now matches foreground scanning with the same dynamic
  status pill, rotating **Did you know?** card, Field notes, and scan
  information. The redundant queued heading, upload explainer, and
  media/file-size summary have been removed; actionable retry timing and errors
  remain available.
- Fixed a TestFlight-confirmed queued-scan deadlock after a retryable cloud
  ingestion failure. The app now preserves one exact retry through any required
  media re-upload and lets that delayed generation send its Identify request
  instead of endlessly alternating status checks and successful uploads. Retry
  ownership is now read from both the queued scan and its durable job, counters
  advance from the monotonic maximum, and every serialized transition repairs a
  drifted mirror before mutation. A known cloud-complete result wins over retry
  state. This closes the migrated-store variant that still restarted at retry
  one after the initial single-row fix. Automatic retries pause for manual
  attention at the safety limit, and an explicit retry starts a fresh automatic
  budget under the same scan UUID so description-only work cannot immediately
  pause again. Opening the library logs only actual queue/library changes,
  expected duplicate retry callbacks are silent, and Library, scheduler,
  reconnect, and URLSession replay wakes share one active reconciliation plus at
  most one trailing pass. Hosted iOS result validation now requires the exact
  replay single-flight, retry-dispatch, dual-copy durable-latch,
  re-stage-survival, description-only manual-retry, and bounded/redacted
  diagnostic-export regressions to execute and pass.
- Restored Explore sharing for eligible older observations whose cloud media
  reconciler had abandoned a missing owner row even though the device retained
  the completed result and original media. Repair is limited to the
  authenticated owner’s exact `replay_exhausted` ledger, or exact
  `media_reconciliation_abandoned` plus composite service proof: a post-result
  dead letter no earlier than the latest charged normal/server-replay attempt,
  no active reservation or invalid timestamp lineage, and no moderation-rejected
  or moderation-pipeline-failed capture lifecycle row. Legacy unstructured
  evidence must belong to the immutable exact dead-letter-ID snapshot captured
  at rollout, predate the private database cutoff, and narrowly cover the
  vulnerable producer’s first committed normal attempt with no charged replay
  and the audited post-safety error path. Snapshot identity prevents a
  DDL-blocked producer from gaining legacy authority through an earlier
  transaction-start timestamp. New evidence binds the exact quota
  reservation/request IDs, validated provider result, and completed Identify
  safety evaluation. Because the baseline and hardening SQL files are separate
  migration-file transactions, production predeploys fail-closed signer, status,
  and share consumers before either file; the structured Identify producer
  deploys only after proof hardening is ready. It remains fenced by deletion
  tombstones and per-scan locks and still blocks later policy, unproven
  abandonment, unknown, foreign, and ordinary terminal state. Media cleanup can
  no longer overwrite an existing terminal policy decision. Rejected post-result
  proof writes now produce an explicit backend diagnostic instead of
  disappearing silently. New iOS builds commit owner repair before uploading;
  the guarded Edge path also supports the current released-client sequence.
- The Scan Library now accepts both the current wrapped and exact legacy
  direct-array Explore media-health response. A defensive empty `[]` no longer
  produces a false decode error merely from opening the library, rapid queue
  updates coalesce the independent read-only alert refresh without dropping a
  trailing repair/foreground request, account identity is revalidated after an
  in-flight call, and unknown success shapes still fail closed. HTTP benchmark
  logs now distinguish status, request bytes, and response bytes; the former
  ambiguous `bytes` field measured the request and is no longer mistaken for
  response-shape evidence. Production deployment now includes this owner-only
  route in the strict unauthenticated `401 + X-Merian-Handler` critical-path
  probe instead of relying only on broad route existence and its underlying RPC.
- Fenced Field Chat and Explore actions to one exact presented scan. A delayed
  SwiftData lookup can no longer retain the previous observation's post,
  Community, notes, media, or action state; Field Chat proves and presents the
  same captured scan ID across asynchronous readiness checks, and Explore
  recovery now prefers the backend's stable `not_found` code while retaining a
  narrow released-response text fallback. Switching records now invalidates
  every older scan-bound action generation, so delayed publication, post edit,
  Community, field-note, preferred-name, identification-confirmation,
  collection, issue-report, and delete callbacks cannot mutate or display state
  for the newly opened observation, including a same-scan issue-report
  completion from an older presentation generation. Sheet reset now advances
  request clocks instead of reusing zero-based tokens. A handler-confirmed
  missing owner row also clears an obsolete local post or Community marker,
  allowing the deliberate share action to enter guarded legacy recovery instead
  of exposing a broken Edit action.
- Completed the scan-switch audit across delayed and nested Insight actions.
  Candidate hydration and identification review now require the original scan,
  species, and latest user action; review writes remain ordered even when an
  older request is already running. Field Chat rejects late private-thread
  loads, sends, deletes, feedback, summaries, and prompts after another chat
  opens. Explore/Community/Field Notes editors, nested Share sheets, onboarding,
  and New Collection retain their original presentation identity. Nested Share
  directly checks its parent generation, and New Collection revalidates before
  insertion. Toolbar, export, media/audio, gallery, Wikipedia/Safari,
  common-name, nested candidate, copied composer, Field Chat parent, and toast
  callbacks all retain their immutable scan/generation target. Enrichment,
  Wikipedia, GBIF, and durable species-metadata writes also require the original
  presentation and latest review action, with writes serialized so the newest
  user choice is always final. Presentation dismissals now clear only their
  captured target, same-scan Explore/Community writes retain the exact
  post/request UUID, and an unavailable advisory post-detail read no longer
  erases confirmed Field Notes visibility. Offline queue polling, cached-media
  refresh, direct A-to-B sheet replacement, manual-retry refresh/indicator
  release, and result promotion can no longer restore, retain, promote, or clear
  UI for a different queued scan. Queued-to-completed handoff invalidates queued
  callbacks even under the same UUID, and a new completion handoff replaces an
  obsolete poller instead of being dropped. Rebinding an obsolete same-ID queued
  route after completion now preserves the active result generation and controls
  instead of resetting them. The shared animated scanning badge now draws its
  glare inside a fixed Canvas and fades text changes without translated mask
  views, instead of exposing invisible animation geometry as an oversized
  off-window activation frame. It retains its native Button accessibility node
  and explicit label so the caller's scanning identifier remains discoverable as
  an actual control. Best-effort Wikipedia, GBIF, and enrichment persistence now
  has a hard eight-active/eight-pending ceiling, so rapid queue replay cannot
  build an unbounded retained-closure backlog.
- Fixed the release-blocking scan failure that let Gemini finish but rejected
  the observation while saving it. Inline camera bytes no longer advertise a
  synthetic staging object, and the strict media finalizer now receives only
  real upload sources. The shared durable success boundary is restored for the
  Insight result, Field Chat, Explore sharing, field trips, and owner sync.
- Hardened the hosted iOS release gate against false-green test evidence. A
  passing full target must now include passed—not absent or skipped—named
  regressions for malformed analysis success, durable offline capture and atomic
  completion, Community mixed-media recovery, Explore publication and
  reconciliation integrity, exact scan-status identity/cardinality validation,
  and retryable single-flight Field Chat startup. Contradictory bulk status
  success can no longer terminate the app through duplicate dictionary keys.
- Fixed the valid-video finalization regression isolated by backend workflow run
  1552. Sampled video inference frames may remain in the compatibility image
  array but are no longer required as standalone ready images. Finalization now
  projects the same canonical image/playback/audio timeline rendered by the app
  and still requires exact owner-matched ready rows before completion, restoring
  video Insight, Field Chat, and Explore prerequisites without weakening lost
  upload detection.
- Fixed a second production-confirmed 503 before scan insertion: replay/profile
  drift tried to create a user with none of Explore’s mandatory public identity
  fields. All Identify routes now call one service-only, Auth-backed profile
  prerequisite that derives valid identity fields and refuses account deletion,
  merged ghosts, or cleanup races without weakening schema constraints.
- Added a service-only, fail-closed repair for already-owned scans stranded at
  media finalization. It distinguishes historical inline filename hints from
  genuine queued image sources, verifies the exact owner/job/intent topology and
  canonical media mapping, atomically normalizes both ingestion ledgers, and
  runs the canonical finalizer without another provider call. Multi-image,
  video-frame, queued-image, audio, and mixed-media states are covered.
- Upload-URL registration is now idempotent for a stable
  owner/client-scan/object key. A lost signing response reuses the committed
  asset and upload session, retryable failed assets are reactivated rather than
  duplicated, terminal/completed generations remain closed, and a partial
  database uniqueness rule serializes concurrent retries. Existing duplicates
  are retained as explicitly superseded audit rows; duplicate filenames are
  rejected before signing. Staging order is now the stable per-scan media slot
  rather than the scan’s accidental flat position in a multi-scan batch.
  Foreground, video, and recovery signing subsets for one scan now compose
  without treating the first subset as an immutable full manifest; their union
  remains capped at six by both Edge validation and an owner-serialized database
  trigger, including across concurrent disjoint-key requests.
- Offline image, audio, video, and Describe submissions now commit their local
  queue record before optional weather, geocoding, authentication, or other
  asynchronous enrichment. Upload callbacks preserve the exact canonical
  server-issued object key across authentication changes. A pre-insert
  persistence failure permits a fenced metered retry and resets consumed staged
  media to a fresh upload instead of looping on deleted object keys.
- Scan-media reconciliation now distinguishes durable standalone audio from
  inference-only video companion audio. A stranded standalone recording is
  retained and marked promoted instead of being mislabeled as deleted.
- Closed the remaining compatibility success gaps in `identify`,
  `identify-describe`, and `audio-spec`. All four scan producers now await the
  exact owner scan insert and run complete-last finalization in the required
  task; compatibility delivery may fall back only to an already-committed owner
  row while its bookkeeping remains retryable. Optional analytics/enrichment
  runs only afterward, and a transient post-provider dictionary-cache read
  degrades safely instead of stranding committed usage.
- Fenced scans interrupted by anonymous-to-account identity merge before generic
  ownership reparenting. Recovery is target-only and requires exact
  job/handoff/quota/lease/tombstone evidence; committed provider usage is never
  refunded or reopened, retired-source staging is never accepted, and active or
  deleted work always wins.
- Legacy audio requests that include both inline bytes and an old destination
  hint now ledger only the bytes actually used. Standalone audio is promoted
  into durable scan URLs and normalized media so it remains available to
  Insight, Field Chat, and Explore instead of being deleted after inference.
- A failed file in a background upload now fences and cancels the entire
  generation before sibling callbacks can advance an incomplete scan manifest.
  Final staging additionally requires duplicate-free set equality between
  successful and expected server-issued keys in that generation; missing,
  stale-extra, or duplicate expected members cannot be omitted. Sanitized
  filename/object-key collisions are rejected before signing, and removal of a
  completed sibling from `URLSession.allTasks` cannot be mistaken for a
  successful upload. Reattached generation-tagged tasks now invoke orphan
  recovery even though their creating process’s global sync latch is gone; a
  proven `.uploading → .pending` reset restarts signing in the same recovery
  pass.
- Explore media restoration now rejects traversal and cross-owner staging keys
  as well as per-kind overflow, aggregate overflow, and a staging key claimed as
  multiple media kinds. Repair accepts at most five images, one playback video,
  two standalone audio clips, and six keys total. Before promotion, every
  current key must match its upload ledger row's exact owner, client scan, media
  kind, and role; cross-scan or relabeled keys are rejected. Ledger-less
  released-client compatibility is limited to the exact deterministic
  scan/category filename and legacy extension-derived kind. The server removes
  partially promoted media only after a returned database rejection plus an
  exact-owner reread proves the URLs were not committed. Lost or unreadable
  scan-write responses preserve quota and promoted image, audio, and video
  objects so cleanup cannot break a committed scan; retries reconcile through
  the exact owner row. iOS checks the complete mixed-media count and all
  image/video/audio byte budgets before its first signing call, avoiding a
  partial staged repair when an old local snapshot is over a canonical cap.
- Fixed a staged-ledger regression that rejected Explore and Community media
  recovery precisely because analysis had already completed. Current repair
  signing carries a scan-bound `scan_share_restore` purpose. The server permits
  its completed-job exception only for deterministic category filenames,
  canonical roles, and a fresh scan read that either confirms the active
  JWT-owned row or proves it genuinely absent for guarded reconstruction.
  Pre-scan signing grants no scan-write or publication authority.
  Failed-terminal uploads stay closed except for exact authenticated-owner
  `replay_exhausted` repair, or `media_reconciliation_abandoned` repair with
  matching composite dead-letter/quota/media-lifecycle proof; tombstoned,
  policy-rejected, later-policy, unproven-abandonment, unknown, cross-scan, and
  ordinary post-completion uploads remain closed. Historical promoted capture
  rows no longer consume the separate active repair budget, and ambiguous
  signing retries reuse the committed restore row and session.
- Malformed paid-provider output now returns retryable HTTP 503 consistently
  across image, multimodal, Describe, and audio producers instead of stranding
  offline jobs behind terminal HTTP 422 handling.
- Background analysis now treats an empty, malformed, or structurally unusable
  HTTP-success body as ambiguous rather than complete. The exact queue row and
  local media remain durable for status recovery and a fenced retry; a local
  persistence or queue-cleanup failure can no longer mark the ingestion job
  complete. Confidence-zero source media also remains intact until the durable
  queue deletion authorizes file cleanup. Successful foreground, background, and
  server-recovered inference now marks the durable job complete in the same
  guarded save that inserts its completion event and removes the queue row,
  rather than persisting cancellation first or leaving foreground work
  cancelled. Crash replay after that save is idempotent and does not duplicate
  the completion audit event.
- Pending scan erasure now completes locally only after `/delete-scan` returns
  an explicit, decodable `success: true`. Authentication ambiguity, malformed or
  contradictory HTTP success, transport failure, and server failure retain the
  durable deletion task for capped-backoff retry instead of silently abandoning
  cloud cleanup. Privacy erasure retries no longer expire at the generic queue
  limit, and a remaining task repairs legacy paused or contradictory terminal
  job state on the next drain. A process-local single-flight guard prevents
  competing foreground wake sources from mutating the same SwiftData erasure
  task concurrently. Hosted iOS evidence must include all four exact
  confirmation, retry-state, single-flight, and malformed-response regressions.
- Field Chat now validates every successful thread response against the exact
  requested Insight scan or Explore post and one conversation before replacing
  visible messages. Even an empty thread must echo its subject. Malformed or
  mismatched replies remain retryable and cannot clear a failed outgoing
  question. Each send now requires one durable UUID and can report success only
  with its exact saved user/assistant pair; automatic, quota-layer, and manual
  retries coalesce under that UUID instead of inserting a duplicate question.
  Request UUID case is canonicalized, conflicting text reuse is rejected, new
  sends reserve both rows within the 30-row cap, and deterministic assistant
  UUIDv8 rows prevent duplicate answers during concurrent refusal or ambiguous
  persistence. Duplicate-insert and waited-replay checks now reject
  contradictory same-key payloads even when they race the initial read, and iOS
  requires the acknowledged user text to match the sent question exactly.
  Cross-device admission now runs in one database transaction: shared
  Insight/Explore daily accounting is serialized before conversation capacity,
  the exact user row is inserted only after both limits pass, and a second
  unanswered UUID in that conversation is rejected. Direct browser-role table
  writes cannot bypass this boundary. A quota-committed request whose assistant
  remains absent for ten minutes can use exact-row-bound recovery before one
  newly metered retry; live, mismatched, and completed requests remain closed.
  In-flight retries wait boundedly, failed provider or persistence attempts can
  resume, message text is capped before persistence, and oversized/incomplete
  response bodies fail closed. The latest interrupted user row now returns to
  the failed Retry/Edit bubble after relaunch—even when a filtered orphan
  response follows it—instead of appearing delivered without an answer, while
  its persisted row still counts toward capacity. Feedback, note summaries, and
  generated prompts also require exact subject-bound, bounded, privacy-safe
  confirmation before success. Backend and iOS note sanitizers now remove
  current UUIDv7 identifiers as well as older UUID forms and use a safe fallback
  if identifier removal empties the draft. Send-time and prompt safety now block
  unsafe action requests without rejecting or automatically refusing ordinary
  species names and educational ecology or hazard questions, and long Explore
  species labels cannot overflow prompt chips. Ask the Community applies the
  same `MerianError.invalidResponse` boundary to malformed success payloads
  instead of leaking decoder failures or showing an unconfirmed request.
- Species observation-chart requests now accept canonical RFC-variant UUID
  versions 1...8 at both GET and POST boundaries, matching the service security
  layer instead of rejecting a valid newer dictionary identifier before
  canonical UUID/name verification.
- Owned scan-image repair now reconciles a lost atomic metadata response from
  exact owner source/replacement references and never deletes a promoted
  replacement whose commit outcome is ambiguous.

### Release Assurance

- Release preparation is now bound to the exact release-source snapshot instead
  of only a version and build number. Archive preflight rejects dirty or changed
  source, every built app embeds its Git revision, source fingerprint, and
  clean/dirty state, hosted archive verification and local export require those
  values to match, and startup diagnostics expose them for TestFlight support.
  Release prep also rejects semantic-version downgrades, pins reproducible
  project generation to XcodeGen 2.45.4, and runs the focused stale-marker tests
  in the portable hosted guardrail target. Export output is canonicalized
  beneath the repository's `build/` directory before previous artifacts can be
  removed, and export-options paths cannot escape that directory. Provenance
  embedding rejects traversal plus final-component symbolic or multiple hard
  links before modifying the processed product plist. Marker parsing is now
  typed and fail-closed: local release commits must descend from the exact
  preparation-base revision, while CI validation markers must carry an exact
  matching workflow SHA; malformed identity fields cannot disable either
  boundary. Export paths also reject lexical dot components before
  canonicalizing missing descendants, preventing `mkdir -p` from resolving a
  hidden traversal outside the scoped build directory. Generated-project
  validation now proves the release preflight and provenance phases belong
  exactly once to the main app, invoke only their canonical scripts, and run in
  the required first/last product-mutating positions; adversarial fixtures
  reject detached, duplicated, replaced, and misordered phases. Source
  fingerprinting also rejects tracked `assume-unchanged` or `skip-worktree`
  index state so a sparse or locally hidden file cannot masquerade as a clean,
  complete release checkout. Credentialed App Store Connect build discovery now
  uses the sortable global build endpoint scoped to the exact app, requests the
  highest numeric build directly instead of inspecting only the 200 newest
  uploads, URL-encodes bracketed query names so curl cannot treat them as globs,
  bounds transport retries/timeouts and response size, and rejects an unknown
  successful response shape instead of silently selecting a reusable build
  number. Strict JSON marker parsing and portable link-count inspection keep the
  hosted generated-project lane on its cheap Ubuntu runner. The portable
  provenance fixture injects a narrow plist editor, while macOS runs
  additionally exercise the real Apple `PlistBuddy`; production archives keep
  the Apple binary as their fail-closed default.
- The latest supplied hosted iOS run compiled and executed 879 tests but exposed
  three unique release regressions: replay after an already-committed offline
  completion rejected the repeated queue deletion, and two malformed Explore
  share/share-state `200` responses leaked `DecodingError` instead of the
  required `MerianError.invalidResponse`. The committed production correction
  now accepts an absent queue only when the exact generation's durable job is
  complete and normalizes both decoder failures. Direct negative generation
  tests and malformed-response fixtures lock those boundaries. That failed run
  is retained as diagnostic evidence; it is not exact-final-SHA release proof.
- Fixed the only failing test in iOS workflow run 73 without weakening staging
  security. The mixed-media upload fixture now uses the same canonical lowercase
  Auth UUID namespace required of server-issued object keys. Failed iOS jobs now
  report structured `.xcresult` test names and assertions before consulting raw
  logs, so deliberately injected reply failures and corrupt-store recovery
  fixtures cannot mask the actual release blocker.
- Fixed the subsequent deterministic Xcode 26.6 test-module build failure in the
  staged-manifest regression. Its SwiftData predicate now compares against a
  captured plain scan identifier instead of trying to lower a model-to-model
  key-path comparison through `#Predicate`.
- Fixed the critical historical scan recovery migration that blocked fresh
  Supabase catalog replay. Its former 43 KiB routine and nested ledger predicate
  are decomposed into bounded, no-grant private validators behind the unchanged
  service-only wrapper; explicit ACL and source contracts prevent bypass or
  accidental recombination. Adversarial parser-seam fixtures now prove the
  structural contract rejects unmatched predicates, orphaned or unterminated
  control blocks, invalid `ELSIF` / `ELSE` ordering, and unterminated literals.
- Fixed the next fresh-catalog parser blocker exposed by backend workflow run
  1550. Identity-merge scan recovery used a schema-qualified `SUBSTRING` name
  with its unqualified `FROM` expression form; both key and URL extraction calls
  now use ordinary comma-separated `pg_catalog.SUBSTRING` invocation. A
  depth-aware fleet contract rejects qualified `FROM`, `FOR`, or `SIMILAR` forms
  in every migration, and copied operator SQL was corrected at the same seam.
- Backend workflow run 1551 proved every migration now parses and applies on a
  fresh PostgreSQL catalog. Its remaining two failures were fixture setup:
  overlong identity-merge usernames and a second plain `public.users` insert
  after the Auth signup trigger had already created the profile. Both fixtures
  now use constraint-valid usernames and trigger-aware profile upserts, with
  source contracts preventing either regression.
- Backend workflow run 1552 proved those setup corrections were only partial
  closure. Inline recovery passed its first 15 assertions and then raised in the
  mixed-video finalizer, exposing the compatibility-frame contradiction now
  corrected by a forward migration. The separate identity-merge fixture still
  aborted before TAP; it now emits phase, SQLSTATE, PostgreSQL message, detail,
  and hint and returns one failed assertion instead of another opaque bad plan.
  Run 1552 stopped before production preparation and made no production
  mutation; an exact-remediated-SHA catalog replay remains required.
- The next exact-SHA catalog run passed the complete 30-assertion inline/video
  fixture and localized the sole remaining failure to identity fixture setup: a
  synthetic PL/pgSQL `scan_id` variable was ambiguous beside `jobs.scan_id`. It
  is now named `fixture_scan_id`; a source contract rejects the old declaration.
  Production merge/recovery code had not run, so it was not weakened for this
  fixture-only SQLSTATE `42702`. The run stopped before production preparation
  and made no production mutation.
- The latest 26-file catalog replay proved the identity correction and passed 24
  files. Its only two failures reached the new atomic Explore and Community
  invoker RPCs, then PostgreSQL denied their `service_role` request-table lock
  before any fixture publication. A forward ACL migration now grants the exact
  table operations needed by those two invoker transactions—including Community
  reopen cleanup—without granting browser-facing writes, `ALL`, `TRUNCATE`,
  `REFERENCES`, `TRIGGER`, or `MAINTAIN`. The rollback fixtures now assert both
  the positive service allowlist and negative anon/auth write boundary. The
  workflow stopped before production preparation and made no production
  mutation.
- Production deploy contracts now pin cumulative Edge Function planning from the
  most recent successful production workflow SHA rather than only the triggering
  commit. A safe ancestor check is mandatory; unavailable or unsafe baselines
  select the full fleet. The job now has the missing read-only Actions
  permission needed to list successful runs in a private repository. This
  guarantees a fixture-only follow-up after failed catalog runs still deploys
  every pending scan and Explore runtime change before production smoke tests.
- Production smoke now proves ten critical scan, signing, share-state, Explore,
  Field Chat, Community, and deletion handlers are deployed and reject
  unauthenticated calls from inside the marked Merian handler. It also proves
  the scan-owner prerequisite, atomic Explore publication, atomic
  Community-request, legacy owner recovery, and both Field Chat quota RPCs are
  present in the live PostgREST schema cache. Exact SQLSTATE `22023` no-write
  sentinels validate server execution before any lock or mutation, while every
  real anon/publishable credential must remain denied; arbitrary `400` responses
  and logged response bodies cannot satisfy the gate. Every production smoke
  transfer now has a 1 MiB response ceiling in addition to its connect and
  whole-request timeout, so an oversized gateway or handler response fails
  closed without being copied into Actions logs.
- Release guidance now requires a manual `iOS Build and Test` dispatch on the
  final exact SHA when backend-only follow-up commits cause ordinary iOS scope
  detection to skip macOS work. Scope-only success cannot replace the full unit
  target and current-SHA Release archive.
- Field Chat no longer hides its toolbar action after a transient owned-scan
  `404 scan_not_ready`, plain status `not_found`, or action-level missing
  message/conversation response. Only terminal ownership, unsupported-scan, or
  an exact Explore `post_not_available` error sets permanent scan-scoped
  unavailability. Explore feedback’s `message_not_found` and unmarked platform
  404s remain retryable; the retry path uses one canonical still-syncing
  message.
- Multi-file offline uploads now clear durable retry accounting only after the
  exact complete manifest succeeds and its keys, retry reset, and staged state
  save together. One successful file, an absent queue/job read, a mismatched
  already-staged manifest, or a failed persistence write can no longer advance
  inference or reset the generation count before a failing sibling, preventing
  partial uploads from looping forever at attempt one.
- Completed background uploads now expose the durable staging-transition outcome
  to their caller. A fetch or save failure no longer falls through into an
  inference claim or gets logged as a persisted retry after rollback; the exact
  completion generation stays fenced while orphan reconciliation returns the
  still-uploading row to signing. Retry helpers now return an attempt number
  only when the queue/backoff write actually committed, with a bounded
  process-local wake retained when durable scheduling itself fails.
- A server-complete queued scan no longer clears retry metadata before
  exact-owner local hydration, promotion, and queue deletion succeed. Repeated
  local sync failures now persist the definitive owner-row observation before
  hydration, retain it across relaunch or a later status-endpoint outage, remain
  outside provider-dispatch eligibility, retain that fence through an explicit
  manual retry, and advance dedicated bounded recovery accounting instead of
  restarting from zero or analyzing the same observation twice.
- Explore publication now reports actual success back to the composer. The
  client also validates the success flag, echoed scan ID, post UUID, parseable
  share timestamp, authoritative location choice, and explicit published status
  before caching the post. Missing or malformed publication evidence is no
  longer accepted as rolling-compatibility success. The sheet closes only after
  that boundary; a failed or malformed response keeps the user’s draft in place
  and presents a retry message.
- Explore’s final database publication is now one service-role-only,
  invoker-rights transaction. It revalidates and locks the owner scan and
  replaces post metadata, selected media, hashtags, and resolved-community
  publication state together. It also rechecks the locked community request, so
  a transaction-time `needs_id` state returns conflict without publishing. A
  backward-compatible request that omits `location_sharing` now resolves the
  scan’s current geoprivacy only after taking that same owner-row lock,
  preventing a concurrent privacy change from publishing with a stale default. A
  late insert or constraint failure restores the previous complete snapshot
  instead of leaving a visible partial post or erasing healthy media while
  reporting failure. Transaction-time Community conflicts are recognized only by
  the exact PostgreSQL code and canonical pending-request message; unrelated
  database failures with matching text remain server failures.
- Ask the Community no longer depends on the removed legacy Explore upsert or
  performs post, media, and request writes in separate transactions. Taxonomy
  and moderation complete first, then one owner-checked RPC commits the complete
  hidden `needs_id` snapshot. Reopen resets stale publication/consensus state,
  and a write-time trigger rejects an explicit share that loses a concurrent
  Community-request race. Compatibility recovery now carries surviving image,
  playback-video, and standalone-audio staging keys through the same owner-safe
  media path instead of requiring an image and dropping video/audio. The iOS
  action also requires exact request identity, UUID, timestamp, status, and
  success evidence before showing Community success or clearing Explore state.
  Database-returned UUIDs are compared after canonical case normalization, so
  PostgreSQL lowercase output cannot turn a committed request from an Apple
  client's uppercase scan UUID into a false failure.
- Explore share-state refresh now rejects a mismatched scan, malformed IDs or
  timestamp, unpaired Community state, missing explicit feed visibility, unknown
  location state, and feed visibility without a committed post instead of
  mapping a stale or partial response onto the open Insight. Explore publication
  also rejects a returned location mode that contradicts an explicit privacy
  choice. Owner share-state now uses canonical moderation and media-health
  visibility: quarantined or moderated publication intent stays repairable but
  is not reported as feed-visible, and a degraded post returns when usable media
  remains.
- Supabase database and deployment commands now fail before config parsing or
  mutation unless the installed CLI is the exact reviewed `2.109.1` version.
  This prevents stale local parsers from producing misleading catalog failures
  or encouraging incompatible `config.toml` rewrites.
- Production function deployment now extracts every selected critical scan
  function from the graph plan and deploys the ten-function compatibility unit
  in its required order before unrelated parallel batches. Duplicate plan
  entries fail closed, and failure of one ordered member stops every later
  deployment instead of creating a knowingly incompatible partial rollout.
- The idempotent Identify response-finalization RPC now registers its
  intentional `service_role` execution grant in the migration-owned
  privileged-routine catalog. `PUBLIC`, `anon`, and `authenticated` remain
  revoked, the routine retains its in-body service-role check, and catalog
  failures now identify the exact unexpected role/signature.
- Disposable-catalog scan deletion and current-generation archive cleanup now
  execute their mutating completion calls in dedicated statements before reading
  post-state. This removes dependence on PostgreSQL's undefined Boolean
  subexpression order, preserves every terminal-state assertion, and reports
  RPC, owner-row, grant, tombstone, and snapshot failures independently.
- The disposable-catalog deletion scenario now establishes an exact
  same-generation `failed_terminal / replay_exhausted` ingestion ledger before
  expecting owner recovery. This preserves the production fail-closed rule that
  no-ledger or active generations return `deferred`, while allowing the fixture
  to proceed into deletion, stale-lease, tombstone, and resurrection coverage.
- Fresh-catalog static analysis now passes an explicit trigger-relation OID for
  every trigger routine and zero only for ordinary routines. A typed registry
  preserves all routine checks while preventing `plpgsql_check` from aborting
  with `missing trigger relation`; no production schema, policy, or privilege
  changed.
- Scan-table Data API privileges are now explicit rather than inherited from
  project-era Supabase defaults. A forward migration clears table and
  column-level grants, restores RLS-governed reads to API roles, restores
  canonical CRUD only to `service_role`, and reinstalls the exact five-column
  authenticated rolling-client bridge. It intentionally withholds
  truncate/reference/trigger/maintain privileges.
- The disposable-catalog scan ACL assertion now uses one exact five-column
  rolling-client compatibility allowlist. It independently rejects broad table
  mutation, every anonymous mutation/reference grant, and authenticated
  insert/reference or unexpected update grants, then requires every allowlisted
  update. This removes a contradictory check that classified the required
  compatibility grants themselves as broad access; no production privilege or
  policy was widened.
- DwC-A health acquisition failures now fail closed with stable
  `catalog_contract_missing`, `health_read_failed`, or `health_response_invalid`
  codes while still writing bounded JSON/Markdown evidence with queue values
  marked unavailable. Raw PostgREST/database details are withheld. A forward
  migration explicitly reloads the PostgREST schema after the service-only
  health routines are installed; a persistently missing routine remains a
  critical deployment/catalog failure rather than being treated as an empty
  queue.
- Focused DwC-A CI now grants Deno read access to every repository root its
  source-inspection contracts traverse, including the complete pgTAP fixture
  directory and iOS release-boundary sources. An earlier tooling contract
  rejects permission drift before the focused lane runs. GitHub run 1539 remains
  recorded as failed evidence because its command omitted the catalog-fixture
  root; only a replay from the corrected exact SHA can replace it.
- DwC-A exports are now intentionally unavailable for the initial production
  launch. Release iOS builds hide the staged Settings controls, while a private
  default-off PostgreSQL singleton and alphabetically first insert trigger
  reject old builds and direct queue insertion. The request boundary now
  serializes release state, the rolling account window, and insertion in one
  service-only transaction. Scheduled continuation is stopped, nonterminal jobs
  are failed, capabilities are revoked, and known archives enter durable
  cleanup; the cleanup worker and independent monitor remain active. Active
  maximum-shape/archive/email evidence moves to a separate feature-enable gate,
  but exact-SHA fresh-catalog, complete CI, production negative smokes, and
  cleanup health still gate the base release.
- Fresh-catalog database assurance now validates the current parent-first DwC-A
  privacy-revocation triggers instead of retired source-state-first routines.
  Scan recovery explicitly casts validated wire strings to catalog enum types,
  and catalog fixtures use distinct scan generations after a durable deletion
  tombstone has been written.
- Supabase Management API key discovery now retries only bounded transient
  transport, throttling, timeout, early-retry, and server failures before
  deployment or monitoring fails. Invalid credentials, malformed responses, and
  ambiguous key classifications still fail immediately, and retry diagnostics
  expose only a stable reason, attempt count, and bounded delay.
- Edge transport and `5xx` retries now replay only audited read routes or
  endpoint contracts with server-supported idempotency. Ambiguous failures no
  longer risk duplicating comments/feedback, toggling a reaction twice, or
  creating another upload staging generation after a lost response. Public
  species pages also require Merian handler evidence before treating an Edge
  `404` as a missing species, so router outages remain transient server errors.
  Retry delays now propagate task cancellation, preventing canceled foreground
  inference or read work from issuing a delayed replacement request.
- Implemented the release-blocking DwC-A/public-web repairs: full-member privacy
  revalidation now fences assembly, staging, email, and completion; completed
  exports now use revocable application capabilities with click-time full-source
  privacy checks, distributed rate limits, 30-second read-only storage
  redirects, and a durable archive-deletion outbox. Permanent email rejection
  terminates instead of retrying forever. Archive cleanup is attempt-key fenced,
  so stale cleanup cannot invalidate a replacement grant. Mixed export
  transitions now take the parent job row and one advisory generation lock
  before source/grant/outbox rows, preventing lock inversion. Atomic setup,
  rolling-compatibility claim, and owner recovery share one normalized per-scan
  generation lock. Every current scan-producing route establishes its job/intent
  before provider dispatch, fails closed with unused-quota refund if setup is
  unavailable, and verifies claimed media dispositions, confirmed storage
  deletions, and ready image/video/audio rows before completion is written last.
  A database trigger rejects every unfenced completion and completed-generation
  rewrite; only the atomic ghost-profile merge's exact source/target transaction
  markers may reparent completed evidence. Catalog replacement invalidates
  source authority without taking export-parent locks inside `TRUNCATE`, then
  the independent cleanup claimant performs parent-first grant revocation and
  archive enqueue. Compatibility finalization failure becomes explicit retryable
  work. Individual scan deletion now commits a private generation tombstone
  before storage erasure, so delayed inference, replay, or another device cannot
  resurrect a deleted UUID. A leased five-minute server reaper finishes
  interrupted erasure without the deleting device, independent monitoring alerts
  on SLA/backlog/expired leases, and completion removes the tombstone's owner
  linkage without removing that fence. Scan-media erasure now requires the exact
  canonical owner UUID in a flat free/Pro object key, preventing poisoned rows
  from nominating another user's object. Broad API-role scan mutation is
  revoked; current iOS metadata writes use owner-derived RPCs while a documented
  five-column grant bridges already-installed clients. No-ledger recovery now
  defers rather than allowing a modified client to fabricate history.
  Non-biological retention now generation-locks and revalidates candidates,
  writes the same durable erasure fence, and leaves all R2/row work to the
  independent reaper, closing the finalizer-versus-inline-purge window. Bulk R2
  deletion treats an already-absent object as idempotent success and omits
  object URLs from logs. Explore detail owns the canonical anonymous visibility
  predicate and page reads are atomic, while snapshot projection stops at
  cumulative byte limits instead of materializing every candidate DTO.
  Production promotion remains held until exact-release-SHA fresh-catalog,
  complete CI, production smoke, and hosted maximum-shape evidence meets
  `docs/backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md`.

### Explore

- Fixed queued scans that showed an **Automatic retry** time but could remain
  staged after that deadline. Naturebook now reconstructs an actual wake timer
  from the durable queue on foreground, reconnect, sheet presentation, and every
  retry-date write. The queued Insight shows a live retry countdown, changes to
  **Automatic retry is starting** when due, refreshes visible queue state once
  per second, and offers **Retry now** during scheduled backoff.
- Fixed scans that reached Naturebook but were shown as **Network timeout**
  after foreground/background or transport retry delivery. Repeating the same
  scan request now replays its completed result without another AI call, while
  the app shows customer-facing **Restoring scan** feedback and lets the exact
  queued/status recovery replace that message. This restores the shared
  prerequisite for Explore sharing and Field Chat on both current and
  reconstructable earlier scans.
- Fixed Scan Library observations being denied when sharing to Explore after
  server-side routine authorization hardening.
- Scan creation/status, Explore sharing/composer media, and Field Chat now retry
  only Supabase's platform-level missing-function response during transient
  route propagation. Handler-owned missing-scan responses still use owner-row
  recovery, while an exhausted router outage becomes a typed temporary-service
  error so it cannot mark a scan unavailable or expose
  `Requested function was not found`. Background inference now applies the same
  boundary before HTTP classification. Supabase routing failures, expired queued
  authentication, timeouts, duplicate/finalized requests, early requests, and
  throttling preserve the scan for durable retry. Other handler-owned `4xx`
  responses preserve queued media as user-actionable; only exact
  `observation_rejected` policy responses are terminal.
- Field Chat now preserves a confidence-focused prompt for identifications below
  70% confidence, even when generated suggestions fill the available chips.

### Media Reliability

- Stale server retry timestamps now trigger a one-second client recheck instead
  of being clamped to the full five-minute delay, preventing an already-expired
  server lease from unnecessarily stalling offline recovery.
- Explore no longer leaves an all-missing observation as a blank public post.
  Confirmed-missing items are hidden individually, and an all-missing post is
  reversibly hidden while its post record, likes, and comments remain safe.
- Added a persistent Scan Library recovery banner plus one incident
  notification. A repaired cloud image automatically restores the affected
  Explore media; successful restoration is reported quietly in app.
- Published-scan counts, the Profile preview, and the full grid now use the same
  server visibility rules. Locally cached share state no longer creates tiles
  that are absent from the full grid.
- Owners with affected publications see separate preserved, visible, and
  recovery-needed totals on Profile, while deployment monitoring reports only
  aggregate affected-account scope.
- Scan deletion confirmations now state that deleting a published scan also
  permanently removes its linked Explore post, likes, and comments.

### Brand

- Merian is now Naturebook. The name is new; your scans, account, subscriptions,
  and Explore content stay exactly where they are.

### Settings

- Renamed the Capture settings group to Workspace, keeping the Camera, Audio,
  **Reorder modes**, Field trip goal, and submission controls together.
- Added a default-off **Open Explore on launch** preference above Notifications.
  When enabled, a fresh ordinary launch opens the Explore feed; returning from
  the background does not reopen it, and shared photos, links, and tapped
  notifications still open their requested destination.

### Beta Operations

- Production deploys now prove that every configured Edge Function route reaches
  a marked Merian handler before reporting success. Gateway-verified preflight
  uses only a validated legacy anon JWT and never a publishable Bearer key. Scan
  creation/status, Explore sharing/composer media, and Field Chat additionally
  prove unauthenticated access fails closed. Regional gateway `404` responses
  receive bounded propagation retries and fail the rollout if route recognition
  does not recover.
- Fixed the proactive feedback survey so restored account history cannot open it
  during startup. Eligible returning testers can now be prompted only after
  another successful biological scan and dismissal of its result sheet.
- Consolidated the Supabase server credential and database release contract.
  Opaque project keys now use only standard `apikey` transport, every real
  public project key is a required negative deployment smoke control, and
  internal failures withhold operational response bodies and all secret-derived
  diagnostics. Production deploys now synchronize the exact revealed active key
  into a non-reserved Edge fallback before Function rollout and verify its
  stored SHA-256 digest without logging either value. Edge and web credential
  sources are classified independently so a malformed migration slot cannot veto
  an exact valid key or enter the accepted candidate set. Bounded propagation
  retries and endpoint-aware diagnostics replace opaque final Function/Data API
  errors with safe handler-versus-router or PostgREST-specific guidance.
  Scheduled JSON Function callers now preserve the same safe status and fixed
  handler-marker classification instead of reducing failures to the SDK's
  generic non-2xx message; the read-only scan-media monitor also retries only
  bounded transient failures.
- Closed the remaining exposed-table security gap for Explore comment reactions,
  revoked unsafe global and `public`-schema default table/sequence privileges,
  and added static plus live catalog enforcement for RLS and PostgreSQL 17
  privilege behavior.
- Added a catalog-driven user foreign-key index release gate for identity and
  account-deletion performance. Small missing indexes converge in migration;
  larger and partitioned relations fail with a supervised, independently
  verifiable construction path instead of taking an unbounded blocking lock.
- Hardened operational workflows with least-privilege taxonomy checklist
  writing, run-attempt-specific artifacts, bounded outbound responses, reviewed
  action pins, shell syntax checks, and weekly GitHub Actions dependency
  updates.
- Added an exact-commit iOS production-readiness gate. Build-relevant changes
  now compile the app and both shared test bundles with Xcode 26.6, execute the
  complete unit-test target with explicit coverage of camera, inference, and
  offline-sync concurrency suites, and independently produce and inspect an
  unsigned Release archive and matching dSYM before release.
- Release and TestFlight builds now use the normal free/Pro scan meter and
  server-enforced quota. Unlimited local-meter bypasses remain available only in
  DEBUG; subscription testing is still available directly from Settings → Plan.
- Paywall diagnostics now distinguish a missing current offering, an empty
  package set, and missing required `pro_week` / `pro_annual` products so beta
  store-configuration failures are visible before release.
- Subscription synchronization now verifies RevenueCat's signed delivery, checks
  authoritative subscriber state, and ignores duplicate or delayed events that
  could otherwise roll a newer renewal or refund backward. RevenueCat account
  transfers now reconcile both the source and destination atomically instead of
  relying on a follow-up lifecycle event. Recurring and grace-period expirations
  are now durable, and a scheduled authoritative subscriber sweep repairs a
  missed webhook without restoring refunded pass history. That sweep now drains
  repeated leased waves against a runtime deadline instead of stopping after ten
  users, indexes expired leases, and has an independent oldest-due-age alert.
- Hardened every server JSON endpoint against oversized or malformed streamed
  bodies and replaced internal exception details with stable request-correlated
  errors. The public beta waitlist now requires a verified security challenge,
  applies transactional per-network and global growth limits, and keeps raw
  network addresses out of storage and logs.
- Added hard deadlines to outbound Edge requests and streamed byte ceilings to
  provider diagnostics and enrichment JSON. Replay claims now outlive their
  downstream inference deadline, APNs retries share a collapse identifier, and
  CI rejects production modules that bypass the reviewed transport adapters.
- Database CI now discovers and executes every checked-in pgTAP catalog fixture
  instead of maintaining a selected list, so adding a new authorization or data
  integrity contract automatically makes it deployment-blocking.
- Migration CI now discovers every source-level migration contract before
  starting PostgreSQL, and fresh replay keeps timeout guards effective while
  rejecting invalid schema-qualified string-function syntax.
- Closed an internal-worker authorization bypass where an RLS-filtered,
  successful empty table read was mistaken for service-role authority. Every
  shared internal boundary now accepts only an exact platform-managed service
  key, rejects mixed credentials, keeps caller credentials out of downstream
  database clients, and denies real anon/publishable keys in the production
  smoke suite. Operational callers now retrieve revealed current secret keys
  through the Management API, use API-key-only transport, reject masked key
  representations, and fall back only to the exact legacy service-role key.
- Privileged Edge, webhook, and public-data clients now resolve the
  platform-managed current secret-key dictionary through one factory. Opaque
  keys stay out of Bearer transport across database, Storage, Functions, and
  Auth Admin calls, while inherited request metadata and real user access tokens
  remain intact.
- Migrated all twenty internal service request boundaries, installed `pg_net`
  routines, persisted HTTP cron commands, the server-only web client, and
  operator repair/audit tools to the same current/legacy key policy. Mixed
  user/service database routines now dispatch on bound user identity instead of
  a JWT-only service-role claim, with static, catalog, and read-only production
  audits preventing regressions.
- Made scientific exports safe to retry and bounded in memory. Duplicate workers
  now compete for one database lease, stale attempts cannot publish over the
  winner, and scan rows advance through short cursor-persisted CSV, assembly,
  and delivery phases instead of one long Edge invocation. Personal requests
  have canonical row/archive budgets; global exports are internal-only.
  Claim-token-fenced temporary chunks feed a streaming R2 multipart archive,
  provider replies are byte-capped, HTTP-200 multipart error documents are
  rejected, abandoned multipart sessions have an explicit seven-day lifecycle
  abort, rollout compatibility expires to a finite job cohort, raw rollout-era
  failures are sanitized, claimed/terminal results reject old-worker overwrites,
  and email delivery is idempotent. Global attribution now uses a dedicated
  versioned HMAC key instead of a Supabase credential or fallback salt. Export
  source arrays and selected taxonomy values now have validated
  cardinality/UTF-8 byte bounds, each claimed keyset page stops by serialized
  bytes as well as rows, and CSV is encoded one row at a time into a fixed-size
  buffer. Occurrence and multimedia now share one bounded immutable
  creation-time DTO snapshot, so later scans and edits cannot mix taxonomy,
  privacy, or media revisions. Confirmed identity is authoritative while the
  original AI identity remains history; exact GPS is omitted before persistence
  unless an unprotected personal job explicitly requested it. Full-member
  eligibility is now durably invalidated and revalidated before assembly,
  staging, email, and completion; invalidated objects are deleted. Processing
  jobs keep signed links private until final fenced completion. Snapshot
  projection applies cumulative byte limits one DTO at a time. Chunk downloads
  accept missing `Content-Length` only while enforcing exact streamed manifest
  bytes.
- Made account deletion durable and recoverable. Naturebook now records the
  deletion request before anonymizing account data, verifies that cleanup, and
  cursor-sweeps durable uploads, staging data, avatars, and exports. A delayed
  empty verification sweep must finish before sign-in access is removed as the
  final step. Interrupted attempts are resumed automatically instead of leaving
  an inaccessible account with personal profile data still present. Retained
  scientific observations now become ownerless tombstones rather than relying
  on a synthetic login/profile identity. Free-form notes and account context are
  removed; exact location and other scientific facts are retained under the
  current mandatory scientific-observation contract. Delayed ingestion replay
  treats those tombstones as terminal and cannot invoke AI for them.
- Fenced account-level R2 erasure against stale or orphaned storage markers. The
  database now requires the matching private deletion job to have completed
  relational cleanup, and refuses a storage claim while a live profile or any
  owned scan remains. Historical queue state alone can no longer authorize an
  active account's free/Pro prefix sweep.
- Added independent account-erasure SLA monitoring. A service-only aggregate
  health RPC now reports oldest active/due ages, phase and backlog counts, retry
  errors, expired leases, orphaned storage work, and reaper configuration
  without exposing user IDs. An offset five-minute GitHub schedule alerts
  independently of the database worker and retains bounded JSON/Markdown
  evidence. Configuration readiness now follows the reaper's exact Vault-first,
  NULL-only fallback, so a blank Vault value cannot be hidden by a populated
  legacy app setting.
- Fixed offline retry/result callbacks that could pass their in-memory token
  checks and still overwrite a newer SwiftData generation. Queue claims now
  persist their UUID atomically, and retries, cancellation, result saves, and
  deletion compare that durable owner under one per-scan coordinator. Foreground
  inference now carries the same durable generation through provider calls,
  persistence, UI publication, and queue cleanup, so a delayed live result
  cannot clear or cancel a newer retry. The queue manager now atomically
  consumes each generation and owns tokenized retirement across cancellation and
  pre-provider exits. Durable-owner lookup/save errors fail closed and retry
  with bounded backoff, and loading a historical scan now relinquishes the exact
  live owner without deleting its queued recovery work. Online text-only
  Describe now queues a zero-byte staged job before provider dispatch, removing
  its weaker process-local persistence exception. Valid confidence-zero
  responses remain terminal without a redundant provider call, while missing or
  mismatched response scan IDs now fail closed and preserve queued recovery
  work. Provider preflight and terminal failure effects now require the full
  exact owner, so a retired attempt cannot invoke nonvisual inference, trip the
  circuit breaker, or overwrite its replacement with an error.
- Kept transient Insight image failures out of durable scan state. Failed image
  pages now move behind available visuals without deleting user media or
  reference URLs, recover into source order after a successful retry, and reset
  their availability state when the displayed scan changes.
- Hardened the public web boundary with the patched exact Next.js release,
  per-request nonce CSP, explicit browser security headers, and a `server-only`
  service-role client separated from anonymous projection reads. Explore now
  uses two narrowly scoped, fixed-anonymous server projections: browser roles
  cannot execute them, no synthetic viewer can be supplied, and engagement or
  ownership state is withheld. Reviewed transitive overrides now replace
  Next.js's vulnerable PostCSS and Sharp versions, and web CI blocks current or
  future high/critical dependency findings instead of treating the documented
  audit as optional.
- Patched the separately deployed internal-admin dependency graph and added an
  independent quality check. Admin changes now use a frozen install, reject
  reviewed-vulnerable Next.js/PostCSS/Sharp versions, block live high/critical
  audit findings, and must pass syntax-aware secret-boundary tests, type-check,
  and a production build. The production contract requires that check in both
  GitHub repository rules and Vercel Deployment Checks before promotion.
- Hardened production workflows with immutable action commit pins, explicit
  read-only permissions, step-scoped secrets, whole-tree Supabase
  function/tooling formatting and lint, a discovery-based complete script test
  gate including ghost-user maintenance, and the complete recursive Edge test
  suite against the disposable database. Identify responses now use one
  executable contract to generate Gemini schemas, infer Edge types, validate
  provider and final server-enriched payloads at runtime, and generate the
  checked-in Swift DTO decoders. Malformed or numerically out-of-range responses
  fail before persistence or client delivery. Supported provider-side string and
  array bounds are projected from that same contract through a typed Google SDK
  adapter, and universally emitted nullable values remain required keys. The
  fail-closed contract gate checks the exact generated Swift block and exclusive
  DTO ownership across the complete iOS source graph, including cross-file and
  module-qualified aliases; a lightweight iOS guardrail runs the same gate for
  every app source change.

### Species Dictionary

- Fixed the Index's **Your Region** section so a valid device country no longer
  disappears. Regional catalogs now use refreshable GBIF occurrence evidence
  and exact country codes instead of trying to match country names inside broad
  free-text ranges. While existing species are being backfilled, the map card
  stays visible with a clear coverage-updating state; new identifications also
  stop overwriting curated legacy range text with `Unknown`.
- Temporarily hid the unfinished Tree of Life view from Explore’s Index while
  keeping the Species Dictionary catalog available.
- Hardened public observation charts against duplicate cold refreshes and
  provider outages. Charts now require a canonical Dictionary species, reuse
  negatively cached misses, and bound provider work with server-side rate
  limits, deadlines, and cross-server refresh leases. A failed refresh now keeps
  still-usable chart data stale instead of replacing it with an empty result,
  shared public caches are no longer fragmented by session token, and the app
  rejects legacy or mismatched responses before caching.
- Added sharing to Species Dictionary pages. Shared links open the matching
  Dictionary page in Naturebook when installed and otherwise show a rich public
  web reference with licensed imagery, attribution, taxonomy, conservation and
  safety details, habitat, overview, and linked similar species.
- Species share links now include a readable name slug after the stable UUID.
  Existing UUID-only links and links carrying an older name keep working and
  redirect to the current canonical URL in browsers.

### Media & Performance

- Added account-scoped recovery for a durable scan image whose cloud object is
  missing but whose original app Documents file survives. Naturebook can
  reconnect exact filename, preserved rescue-store, and tightly constrained
  timestamp evidence, render the local copy immediately, then verify the 404,
  upload a new owner object, and atomically repair both Scan Library and Explore
  references. Files without a high-confidence surviving match are left
  unresolved instead of being paired speculatively.
- Fixed a scan's own photo appearing again as a reference image in Insight and
  Explore post galleries. Other Naturebook observations and eligible Wikipedia
  and GBIF references remain available.
- Hid third-party reference images for domestic cat and dog identifications
  across Insight and shared Explore pages, while keeping the user's captured
  media and retaining reference galleries for wild felids and canids.
- Added single-photo import from the iOS share sheet. Sharing an image from
  Photos to Naturebook now opens the app and routes the file through the
  existing gallery crop, confirmation, quota, metadata, analysis, and
  offline-queue flow. Included EXIF date/location is preserved online and
  offline; excluded Location never falls back to the device's current
  coordinates.
- Reduced live-camera still-image analysis wait time by starting inference after
  a bounded environmental-context grace period, avoiding duplicate
  live/background uploads and duplicate inference dispatch, and moving optional
  enrichment, awards, and Field trips work off the first-result path. Free and
  Pro Gemini models and quality settings are unchanged; gallery, audio-bearing,
  and video submission behavior is unchanged.
- Fixed Audio recording occasionally reporting unavailable hardware immediately
  after switching from Camera. Recording now waits for camera release and safely
  recovers while the microphone route settles.
- Fixed videos starting silently after capture or app launch. Audible playback
  now reactivates the shared media session across Scans, Insights, and Explore
  without requiring an audio post to be played first.
- Removed a priority-inversion hang risk from local and remote image decoding.
  Decode concurrency remains capped for memory safety, but excess work now
  suspends asynchronously instead of blocking user-initiated threads.
- Prevented delayed camera recording callbacks, timeouts, and automatic-stop
  tasks from completing or stopping a newer video after rapid cancel/retry
  sequences.
- Fixed rapid thermal or power-state changes occasionally leaving the camera at
  an older frame-rate limit after the device heated up or recovered.
- Prevented delayed offline upload, inference, retry, status-probe, and
  background-expiration callbacks from clearing or cancelling a newer sync
  attempt. Queue progress now remains accurate across rapid reconnects, retries,
  and app suspension.
- Made search-library filters responsive for large histories by caching filter
  dimensions and normalized scan values per library generation, then filtering
  and sorting immutable snapshots away from the main UI actor. Collection sync
  also reads only direct collection memberships instead of repeatedly walking
  the entire local scan history, and server reconciliation now advances through
  existing memberships with a stable cursor before writing only the delta.
- Made server species totals scale with the species assignments changed by a
  scan write instead of rescanning a user's complete history. Bulk imports and
  owner transfers now update one private incremental ledger per SQL statement,
  and transfers repair both the previous and new owner's totals.
- Prevented non-finite media geometry from reaching SwiftUI in Explore detail
  zoom and audio playmarkers, eliminating invalid-frame warnings and unstable
  offsets during transient layout/player states.
- Removed the Capture startup SwiftUI AttributeGraph cycle for every
  configurable first mode (Camera, Audio, and Description). The pager now builds
  pages lazily, Description isolates its vertical scroller and reactive
  lifecycle from the horizontal pager, and capture chrome uses a fixed layout
  reservation. Startup Field-trip goal loading also shares one freshness-gated
  refresh instead of repeating the same capture-context and introduction
  requests. Leaving Description or closing the workspace now also stops
  dictation that is active or still starting.
- Restored the camera hint badge's pre-regression position above the shutter;
  full-screen overlays now use their prior fixed 250 pt clearance without
  reintroducing capture-bar measurement or startup layout feedback, with a UI
  regression test that checks the rendered hint and shutter frames do not
  overlap.
- Center-aligned the primary and secondary capture controls across Scan, Record,
  and Describe, and restored the Describe editor's clearance above that row;
  expanded the editor to fill the available height instead of leaving blank
  space above the controls; removed Describe's duplicate top-safe-area padding;
  Describe UI coverage now bounds both surrounding gaps and verifies the shared
  control centerline.
- Release configuration now requests the production APNs entitlement.

### Explore

- Kept resolved Community IDs out of normal Explore and species sightings until
  the owner explicitly publishes them. Changing a backing scan's geoprivacy no
  longer removes an already shared post; the post's saved location choice
  remains authoritative.
- Added the floating **Field chat** control to every visible Explore post
  detail, including the viewer's own posts. Each Pro viewer gets a private
  conversation visible only to them, grounded in the published observation and
  Species Dictionary.
- Simplified the Explore Field chat empty-state message to clearly say the
  conversation is private and visible only to the viewer.
- Field chat now hides when the sticky comment composer appears, keeping the
  public comment action visually primary at the bottom of an Explore post. A
  Field chat fallback moves into the post menu while the floating control is
  hidden.
- Fixed remote push-device registration failing with a Supabase 500 by replacing
  an unsupported PostgreSQL `{32,512}` regex bound with separate hex-format and
  length constraints; added static migration and executable database coverage,
  and clarified that the iOS token log records Apple's callback rather than a
  completed server registration.
- Reduced unread-badge network churn by sharing one in-flight count refresh,
  briefly reusing successful results, and using Realtime as the primary update
  path with a five-minute polling fallback.
- Fixed cross-device preferred species names repeatedly writing an already
  matching value or tombstone during cloud reconciliation.

- Fixed the Field notes editor so closing an unchanged note no longer
  republishes its existing visibility, shows a misleading public toast, or
  refreshes the Explore detail page. Real text edits still autosave with a
  **Field notes updated** confirmation, while public/private messages appear
  only after an actual visibility change.
- Released Field trips, standard Outings, and the Events segment to every user.
  Events include curated seasonal challenges, completion badges, published
  entries, and optional Explore hashtag suggestions without automatic posting
  or tagging.
- Redesigned Outing catalog cards with a compact progress ring, current-level
  Backyard Safari copy, the existing scrolling goal thumbnails, and pills for
  access, difficulty, level, public/private status, and an available
  privacy-filtered location.
- Added **The Field Naturalist**, an Easy achievement earned by completing a
  first outing or Seasonal Challenge. Its completed Profile card and unlock
  notification reopen the Field trip that earned it.
- Standardized **Field trip** / **Field trips** as the feature label while using
  **outing** for contextual descriptions, actions, activity messages, and
  VoiceOver. Renamed the standard catalog segment from **Challenges** to
  **Outings**; Seasonal Challenge terminology is unchanged.
- Added `All`, `Starter`, `Easy`, `Moderate`, and `Hard` difficulty filters to
  the Field trips catalog, including an illustrated empty state for levels
  without a current trip.
- Moved Goals and Tips into pinned toolbar tabs on standard Field trip and
  Seasonal Challenge detail pages. Goals now owns the trip overview, progress,
  actions, checklist, and Community content, while Tips opens directly to the
  curated guide.
- Added the same circular progress treatment to the active outing level header.
  Completed goals now replace their illustration with the exact captured photo
  or video thumbnail in both outing cards and detail, keep the standard neutral
  border, and open that scan's Insight within the current Explore sheet with a
  back arrow.
- Added Field trip progress notifications after a saved scan counts toward an
  outing or Seasonal Challenge. Each notification names the species and trip,
  shows the credited level's progress ring, and opens the matching outing goal
  or challenge when tapped. Notifications from one scan now appear in a stable
  order: outings, Seasonal Challenges, achievements, then New to Naturebook.
  Re-identifying an older scan scopes feedback to completion rows added by that
  attempt, preventing a prior level or destination from being announced again.
- Added a persistent **Field trips** card to saved biological Insights. Its
  compact rows separate the uppercase completion state from the goal name and
  pair larger objective artwork with a prominent credited-level progress ring.
  It keeps every outing or visible Event credited by that scan together and now
  matches other Insight card headers, removes the redundant level subtitle, uses
  a smaller goal heading, and opens the outing/Event Goals overview in the same
  navigation stack. Back returns to the originating Insight without replaying
  milestone feedback.
- Backyard Safari now advances from the activity period opened at account
  enrollment; other standard outings advance only after the user explicitly
  starts them, and Events only after the user joins. One scan can count toward
  several active experiences, but only one goal in each; a selected live Camera
  goal wins when it is still eligible, with deterministic server matching
  otherwise. The selection survives offline upload, and unfinished progress is
  re-evaluated after identification corrections.
- Fixed temporary scan-persistence and network failures being mistaken for
  completed Field trip processing. Naturebook now preserves the selected goal,
  retries progress automatically, and still shows other earned milestones once
  without duplicating them after recovery.
- Made Field trip attribution durable and transactional. Scan ingestion now
  applies standard outing progress, joined Event progress, the selected-goal
  preference, and first-outing achievement state in one database transaction; a
  private receipt lets later retries recover the original unlock result after
  app termination. The local selected-goal hint is kept until the server
  acknowledges progress.
- Hardened every Field trip and Event `SECURITY DEFINER` database function so
  direct anonymous/authenticated RPC calls cannot impersonate another user;
  authenticated clients now reach them only through the identity-verifying Edge
  API. Also fixed completed-outing publication item materialization and removed
  the profile-pin routine's fragile temporary-table dependency.
- Fixed saved Insight Field trip cards and the first-Field-trip Profile award
  remaining empty when a cached account session finished restoring after the
  screen appeared.
- Fixed ants counting toward Park Pollinators' **Bee or wasp** goal. The goal
  now requires a Hymenoptera identification categorized as a bee or wasp, so
  ants, sawflies, and other broader-order matches do not count, and any earlier
  invalid credit is removed from active progress.
- Tightened the rest of the active Outing checklist so labels and completion
  rules agree. Moths no longer count as Backyard **Butterfly**, ticks and
  scorpions no longer count as **Spider**, and animal/plant/ecology goals now
  require both the named organism group and the matching signal. Park goals that
  could not verify “near flowers” are now honestly labeled **Spider** and
  **Bird**, and the scene-based **Pollinator habitat** target is now the
  verifiable **Meadow plant** target. Earlier credit that fails the corrected
  rules is removed from active progress.
- Prevented unreviewed **Weak match** identifications from counting toward Field
  trip goals. Flash identifications now auto-qualify at 75% confidence and Pro
  identifications at 65%; weaker results remain pending until the user confirms
  the identification or a correction/community resolution confirms a species.
  Earlier weak-match credit is removed, and a later confidence downgrade can
  reopen goals that no longer have qualifying evidence. The repair migration now
  has bounded lock and statement timeouts, so deployment fails cleanly instead
  of waiting indefinitely behind live scan traffic.
- Added a left-aligned, above-title **Private** / **Published** badge to
  standard outing detail. Published is shown only when the owner has an active
  public outing snapshot; completion alone remains Private.
- Added a compact active outing target beneath the visual Scan mode picker. It
  matches the picker width and centers an instructional `Look for: {target}`
  label and outing name between artwork and an AirPods-inspired circular
  progress ring. Swiping cycles through unfinished targets across active
  standard outings, and tapping opens and highlights the matching guide. The
  indicator stays out of staged captures, refinement, video recording, other
  capture modes, and Seasonal Challenges. Its capsule uses untinted interactive
  Liquid Glass on iOS 26 and a neutral material fallback on earlier supported
  versions. An on-by-default Field trip goals setting can hide the capsule
  without changing outing data or progress, and tapping the capsule now provides
  light haptic confirmation before opening its guide. Its shared goal context is
  source-agnostic, so future guided experiences can integrate without coupling
  their API models or ranking rules to the camera.
- Kept a linked standard outing available in the Scan target indicator after
  joining a Seasonal Challenge. Challenge-specific progress remains separate and
  does not enter the standard outing indicator.
- Retired the placeholder Forest Edges outing from catalogs, detail/start
  routes, and the Scan target indicator while preserving existing progress,
  scans, publications, and evidence.
- Refined standard and Seasonal Field trip card and detail-image rounding, moved
  template badges onto the cover image, allowed full-width card text, and
  removed the redundant Open guide row and active-trip Continue Scanning
  actions. Loading skeletons now mirror the updated card layouts.
- Added a Filters pill and sheet to the Explore feed. Species groups,
  image/audio/video media, shared date, and Nearby distance can now be combined
  without thinning paginated pages on the device.
- Separated Explore post reports from identification flags. Reporting public
  content now enters its own moderation queue without marking the underlying
  species identification for review; existing misrouted reports are repaired,
  and repeat submissions preserve completed moderator decisions.
- Kept AI identification reasoning visible on public Explore post pages when a
  scan is reported; reasoning is hidden only when the identification itself is
  replaced by a user override.
- Added an optional **Boost audio** control to public web audio posts. It makes
  quiet recordings easier to hear with browser-local gain, rumble filtering, and
  peak limiting while leaving the published recording unchanged.
- Updated the public web discovery grid to show the species reference image for
  audio posts while retaining the spectrogram and playback controls on post
  detail pages.
- Simplified public Explore post details by removing like and comment counts and
  moving **Report this post** below the Taxonomy card.
- Reworked public Explore audio posts so the recording spectrogram fills the
  square media carousel and playback controls sit directly over its lower edge,
  with species reference images following as normal carousel slides.
- Added video playback to public Explore post pages. The active carousel video
  now receives the canonical public video URL, autoplays muted with native
  controls on a continuous loop, and shares the same square frame as every other
  carousel item; the public discovery grid remains poster-only for fast
  browsing.
- Kept audio presentation scoped correctly: feed and post detail always show a
  persisted or locally generated spectrogram, while compact Map, profile, and
  grid thumbnails continue to use the species reference photo.
- Added real spectrogram artwork for standalone-audio public web post pages and
  social previews. New WAV shares persist a deterministic thumbnail beside the
  recording, and a bounded repair worker can backfill older posts; unsupported
  legacy formats keep normal playback and the volume-icon fallback.
- Added image, video, and audio filters to the Explore map filter sheet. Media
  filters can be combined with species groups and remain accurate for clustered
  map results.
- Fixed the Explore map becoming unavailable when an audio-only or other
  media-only discovery had no hero image. Map points now use media posters or
  species reference thumbnails and isolate missing-thumbnail data safely. Map
  discovery cards now keep the Map-specific reference poster when an older feed
  copy of the same post is cached, retain audio/video typing, and show the
  shared compact bottom-right waveform or play badge.
- Fixed the Explore author profile's full published-scans view so it shows one
  back button instead of overlapping the stack and profile-library controls.
- Fixed missing Explore location labels on audio-only and other non-visual
  discoveries by resolving their capture location before scan persistence.
  Existing affected posts can be repaired from their saved coordinates without
  changing the author’s post-level location-sharing choice.
- Fixed standalone-audio thumbnails in profile and compact Explore grids so they
  keep the species reference photo after remote post data loads, with a
  bottom-right waveform badge identifying the recording; video posts retain the
  matching play badge.
- Added tactile feedback to user-controlled audio and video playback, mute,
  seeking, and audio-boost actions while keeping autoplay and restored settings
  silent.
- Added tap-to-seek and drag-to-scrub playback directly on audio spectrograms in
  Explore post detail. Feed cards remain playback-only so their navigation
  gestures stay predictable.
- Smoothed standalone-audio playheads in Explore feed and post detail. The line
  now follows audible playback at the display refresh rate, stays fixed while
  audio is paused, waiting, or seeking, and preserves the exact pause position.
- Added a compact **Boost audio** control directly to standalone-audio feed
  posts. It transitions to the existing **Boosted audio** treatment when ready,
  toggles back to original audio when tapped again, and does not open post
  detail from its protected tap area.
- Updated Explore sharing to lead with the discovery itself: image and video
  posts now say “Check out this {species},” while audio posts say “Listen to
  this {species},” followed by the public post link.

### Insights

- Fixed successful scans revealing carousel pagination and completion feedback
  before the identification title and result content. The saved core result now
  appears as one synchronized transition while optional reference enrichment
  continues progressively in the background.
- Replaced the still-image laser sweep with a fast native focus treatment. When
  Naturebook isolates a clear subject, the analyzing image now uses Lens-style
  corner brackets, a dimmed exterior, and the full-strength laser sweep
  contained inside the selected area. Broad or ambiguous scenes show no fallback
  box and retain the original full-image scan animation. The two scan treatments
  never appear together, and the full cropped image is still analyzed.
- Improved fullscreen video viewing with the same streamlined custom play/pause
  and mute controls used elsewhere, while keeping carousel dots in their
  standard gallery position. Fullscreen videos now begin playing immediately and
  inherit the Insight carousel's current sound setting. Video playback now loops
  while the video remains selected in both carousel sizes.
- Added a protected center play/pause tap area to Insight video carousels so
  playback taps no longer open the fullscreen media viewer.
- Paused Insight-sheet video playback before opening the fullscreen media
  carousel so sound cannot continue from the covered sheet underneath.
- Replaced native Insight-sheet video chrome with the streamlined Explore-style
  player, removing skip controls and the progress bar while preserving the
  center play/pause target and mute control.
- Fixed candidate review so **Reanalyze species** remains available for
  cloud-backed and multi-image scans and reliably opens the reanalysis flow
  after the nested review sheet closes.
- Added consistent playback, seeking, mute, and audio-boost haptics to Insight
  media while avoiding repeated feedback from timers or playhead updates.
- Added tap-to-seek and playmarker dragging to completed scan audio pages.
  Dragging the rest of an Insight media page continues to move between carousel
  items.
- Smoothed completed-scan audio playmarkers and hardened first playback after an
  audio-boost source change. Prepared sources now wait for an idle handoff,
  rendered files are fully reopened and decoded before publication, and an
  unexpected decode stop falls back to the original recording at the last
  confirmed position instead of leaving playback frozen.

### Account & Billing

- Fixed logout so signing out on one simulator or device clears only that local
  session instead of revoking the same account everywhere, and linked RevenueCat
  customers with Supabase/public identity attributes so Test Store support
  lookups can match Pro status back to Naturebook accounts.

### Scans

- Updated standalone-audio tiles in the Scans library to use the species
  reference photo with a waveform badge. Opening the scan still presents the
  recording spectrogram and playback controls. Reference-photo loading now uses
  the standard media skeleton instead of a technical pending-state message.
- Updated collection cover cards to use the species reference photo when their
  selected cover scan contains audio without visual media.

### Analytics

- Consolidated product analytics under PostHog so app events, session funnels,
  and backend events share one tracking system, with clearer client event names
  for scan completion, queueing, thermal throttling, errors, and species
  dictionary page loads.

### Startup

- Fixed startup recovery for devices carrying the accidental optional-queue V48
  SwiftData store by migrating them forward to V49, and added redacted
  copy/share diagnostics when TestFlight/debug builds enter safe mode.
- Fixed startup recovery for devices with V42/V43 SwiftData stores by routing
  them through source-isolated migration plans instead of the full historical
  chain that can trigger SwiftData's equal-model-reference validator.
- Updated V42 startup recovery to skip the older V42→V43 bridge and repair
  directly to V49 after TestFlight devices still fell back to safe mode.
- Added a legacy-store rescue path so known older SwiftData stores that still
  cannot migrate are archived safely and replaced with a fresh persistent
  library instead of reopening in safe mode on every launch.

### Species Dictionary

- Fixed **Community sightings** so its initial request always starts when a
  species page appears, instead of silently skipping the section before loading.
- Added **Community sightings** after observation charts. Species pages now
  preview six exact-species public Explore posts and can open a paginated grid,
  while respecting each viewer's Explore visibility and privacy rules.
- Added durable species dictionary enrichment queueing so new and existing
  sparse species records can backfill Wikipedia, GBIF, reference image, habitat,
  lookalike, and group-tag details through the scheduled workers.

### Capture

- Upgraded audio spectrograms with denser detail, smoother rendering, and a
  shared polished palette across recording, review, Insight playback, and scan
  thumbnails.
- Improved large-photo handling so gallery scans, reanalysis images, and profile
  avatar previews are bounded before staging, reducing memory pressure when very
  large local photos are selected.
- Added automatic audio submission when a recording reaches the full time limit
  and confirm-before-submit is turned off.
- Added video recording controls so Pro video scans show remaining time, can be
  canceled before staging, and open staged clips in a full-screen preview that
  can be dismissed with a downward swipe or removed before identifying.
- Added Pro short video scans from the visual shutter: tap still takes a photo,
  while a brief hold latches into a 5-second video recording with saved playback
  and image-based thumbnails.
- Enabled native iOS stabilization for Pro video recordings, while resetting the
  prepared movie output after stop, cancel, or failure so still-photo capture
  keeps its normal resolution and latency.
- Added clearer haptic feedback for video recording start, finish, successful
  staging, and recording failures.
- Fixed a crash that could happen after tapping stop on a Pro video recording
  while Naturebook extracted the clip's audio.
- Pro video clips now prefer compression for lighter scan-library playback,
  Explore sharing, and cloud storage while keeping AI analysis frames sampled
  from the original recording.
- Improved Pro video staging so upload-safe clips still stage when playback
  compression is slow or unavailable.
- Fixed video scan submission so unusable video audio no longer blocks
  identification, and background replay keeps the staged video clip attached.
- Hardened video scan submission so saved video captures require a durable
  playback clip instead of silently falling back to sampled frames.
- Added server-tracked upload sessions for scan media so staged videos, images,
  and audio have lifecycle state before final scan persistence.
- Fixed video scan upload signing for production tables that still required a
  public media URL before staged uploads were promoted.
- Added server-side reconciliation for scan media uploads so stranded video
  staging objects can repair existing cloud scans and abandoned upload sessions
  are cleaned up automatically.
- Added server-side scan ingestion job tracking so accepted video and
  mixed-media scans expose processing, finalizing, retryable failure, and
  completion state for recovery.
- Hardened server scan recovery so ingestion jobs record the exact media
  manifest and reconciliation only abandons staged media after active leases and
  retry windows have expired.
- Added a sanitized server replay intent for staged scan ingestion so retry and
  repair tooling can recover accepted media requests without storing raw media
  bytes.
- Added scheduled server replay for resumable staged scan ingestion so image,
  video, audio, and description scans can recover after app exits or transient
  backend failures.
- Hardened legacy scan recovery so image, description, and audio compatibility
  endpoints now write the same server ingestion ledger before returning success.
- Added a media-ingestion contract test matrix so image, video, audio,
  description, replay, status, repair, and Explore sharing contracts are checked
  together before backend deploys.
- Improved scan media health monitoring with incident-action guidance for each
  detected issue code, including owner, next step, runbook, and sample-field
  hints.
- Hardened identification so processed materials like wool rugs, leather goods,
  wooden furniture, paper, textiles, prepared food, toys, and artwork are kept
  out of the species dictionary even when made from biological material.
- Updated iOS offline recovery so queued scans respect server ingestion job
  state instead of resubmitting while video/media finalization is still in
  progress.
- Fixed cloud-hydrated video scans so sampled analysis frames stay hidden behind
  the playable video instead of appearing as standalone Insight carousel images.
- Fixed video scan upload signing so five sampled inference frames plus the
  playback clip fit the staging contract, and repaired staged media rows that
  were blocked before the scan record existed.
- Improved camera shutter feedback so photo captures and video recording start
  with a stronger, prewarmed haptic cue, and video recording begins almost
  immediately after a brief hold.
- Updated video scan analysis so Pro video scans sample five ordered frames,
  treat accompanying audio as evidence from the same video, and are no longer
  described as images.
- Added a Pro paywall carousel slide for video scans and improved feature text
  wrapping.
- Added video scans to the Pro paywall comparison table.
- Fixed the Pro paywall purchase button so it stays anchored to the bottom of
  the sheet.
- Kept non-Pro long-presses photo-first so holding the shutter does not
  interrupt capture or open the paywall.
- Fixed non-biological scan saving so captures that omit ecology metadata are
  saved with an unknown ecology fallback instead of failing in the backend.
- Fixed network timeout results so they keep the "Network timeout" title,
  explain automatic retry, and no longer show non-biological collection or
  retention messaging.
- Hid live viewfinder hint pills once single-scan content is staged or
  multi-scan staging is full.
- Fixed video staging cleanup so canceled or failed captures discard temporary
  playback/audio files, and visual analysis only starts after the offline queue
  has durable ownership.

### Explore

- Fixed feed audio and video controls so the center Play/Pause region controls
  playback without opening the post; taps outside it still open detail, and
  double taps continue to like.
- Changed Explore video transitions so feed autoplay always resumes muted;
  opening a post still inherits the feed video's current mute choice, while
  returning from detail resets the feed to muted.
- Fixed normalized audio media refresh so scans with durable recordings always
  receive ready audio asset rows, including a production backfill for audio
  shared before the database refresh contract supported standalone audio.
- Added a device-local, per-post “Boost audio” option to standalone Explore
  audio feed and detail menus, with adaptive gain, gentle rumble reduction,
  clipping protection, synchronized settings, and position-preserving switching
  while the original recording remains unchanged; active boosted clips show a
  small “Boosted audio” badge on the spectrogram, and saved boost settings
  restore quietly without showing action-progress messaging.

### Insights

- Added direct **Boost audio** and elapsed/total timestamp badges to Insight
  audio spectrograms, positioned above the overlapping result card using the
  carousel attribution-tag treatment.
- Added device-local, per-scan “Boost audio” controls to completed scan-library
  Insights with standalone audio. Mixed-media scans apply one setting to every
  audio page, preserve playback position while switching, restore quietly, and
  leave the original recording unchanged.
- Added the original allowlisted Field trips preview to Explore: regional
  checklist quests could auto-start from new scans, unlock levels sequentially, show active
  checklist progress on public profiles, and publish Field trip pages with
  species snapshots, likes, and comments without creating Explore feed posts or
  map points.
- Expanded Field trips with guided trip detail pages, explicit Start, curated
  item tips, a Field trips-only Community segment with For You, Following, and
  Recent filters, template Community previews, and up to 3 pinned published
  trips on profiles.
- Added Field trip Seasonal Challenges: curated, explicit-join, non-competitive
  challenge pages with schedule/counts, after-join-only progress, completion
  badges, challenge-specific published entries, and optional Explore hashtag
  suggestions without auto-posting or auto-tagging.
- Added in-app Field trip activity for comments, replies, and followed-author
  publications without sending APNs or creating Explore post rows, map points,
  or widgets. Typed Field trip cards can appear in unfiltered Explore Recent and
  Following.
- Added public video Explore posts: shared video scans can now appear in Explore
  and Ask the Community with muted playback in feed/detail and in-app thumbnail
  play indicators on compact surfaces.
- Removed the play badge from Explore Home Screen widgets so video posts appear
  as clean still thumbnails there.
- Fixed Explore videos so opening an author profile from feed, post detail, or
  comments now stays inside the Explore navigation stack instead of layering a
  profile sheet over the active video surface, with profile-to-scan navigation
  capped so users cannot build an endlessly nested stack.
- Fixed Explore video playback so shared video posts autoplay when opened, fill
  their square preview, and use a centered play/pause control that fades during
  playback instead of a static marker; muting or unmuting one Explore video now
  applies to the rest.
- Fixed video Explore sharing so composer-selected video clips publish, edit,
  and request Community ID from the server media source list, while failed media
  snapshots no longer leave the Share sheet showing a phantom Explore post.
- Improved video Explore sharing repair so scans with a surviving local `.mp4`
  can restore missing cloud video media before publishing.
- Hardened video media recovery so cloud scans keep ready-state image/video
  media records for future sharing and playback repairs.
- Fixed Explore video audio metadata so posts only mark video as audio-backed
  when the captured video manifest actually includes an audio companion.
- Added standalone audio to Explore sharing with waveform playback and a
  fail-closed publication check: speech is transcribed and moderated before the
  share succeeds, so rejected or failed checks create no public post.
- Added approved Explore audio to public web share pages with native,
  user-initiated playback and audio-safe social metadata. Audio-only posts
  remain excluded from Home Screen widgets.
- Fixed standalone-audio R2 cleanup so user scan deletion, the 30-day
  non-biological purge, and failed-ingestion rollback do not orphan recordings.
- Added public-audio health checks, privacy-safe moderation telemetry, web
  reporting, and CI contracts for moderation and lifecycle behavior.
- Consolidated public-audio moderation on Gemini 2.5 Flash with structured
  speech and non-speech classification, removing the separate OpenAI dependency.
- Hardened Gemini audio moderation against media prompt injection, preserved MP4
  typing for audible videos, and added transport plus ingestion-owner CI checks.
- Added privacy-safe, content-addressed audio moderation attestations so
  unchanged clips reuse decisions while changed media, models, or policy rules
  automatically require a fresh Gemini check.
- Added legacy audio repair during Explore sharing: surviving local recordings
  upload to staging, become durable scan media, and are moderated before the
  post can become public; missing local recordings remain unavailable.
- Repaired early production `scan_media_assets` constraints so staged and
  durable standalone audio rows are accepted during legacy sharing recovery.
- Replaced raw database constraint text during media-upload preparation with a
  concise retry message while preserving technical details in structured Edge
  logs.
- Added Explore post management actions to the Insight top menu so published
  scans can be edited or opened without returning to the Share sheet.
- Added a View insight action to your own Explore post menus, including posts
  opened from an Insight sheet or your Profile's published scans.
- Fixed notification-opened comment reply threads so parent comments and replies
  include the same emoji reaction controls as regular Explore comments.
- Hid reference images on shared human identifications so Explore pages show
  only the user's media.

### Scans

- Fixed newly empty scan libraries showing a blank screen instead of the
  first-scan empty state, including after switching from a previously signed-in
  account to a ghost session.
- Improved offline queue reliability so image, video, audio, and description
  scans keep retry state across app restarts, show retry/needs-attention status,
  and no longer discard user media after a fixed number of transient failures.
- Fixed queued scan retry from Insight sheets so Retry now gives visible
  feedback, refreshes the open scan state, and no longer duplicates the existing
  cancel control.
- Capped automatic offline retries with jittered backoff so repeated scan
  upload, analysis, cloud-deletion, or collection-sync failures pause for
  attention, and repeated server replay failures turn terminal, instead of
  retrying indefinitely.
- Added Image and Video media filters to the Scans filter sheet.
- Restored the Explore posts scan filter so the Scans library can show scans
  that have already been shared to Explore.
- Hardened launch recovery so a damaged local scan library can be quarantined
  safely without signing the user out.
- Fixed recent TestFlight upgrades so existing local scan libraries open
  normally instead of launching in safe mode after a schema update.
- Fixed a startup safe-mode loop caused by a no-op historical schema version
  being included as a separate SwiftData migration stage.
- Fixed local libraries blocked by duplicate schema checksums by retrying
  startup with short, recent-only migration plans before legacy rescue or safe
  mode.
- Improved launch migration selection so fresh and already-current local
  libraries open without validating the full historical migration plan, while
  recent older libraries use the smallest source-specific plan available.
- Fixed offline-queue schema upgrades so existing queued scans initialize their
  durable retry state instead of repeatedly reopening in safe mode.

### Profile

- Added an Edit profile picture action to the Profile identity menu so the
  avatar picker is available alongside name and username editing.
- Fixed repeat observations moving an achievement's original unlock date
  forward. Repeat scans still update the latest-interaction date, while
  retroactive-notification decisions remain tied to the scan that earned the
  achievement.
- Made profile names optional; clearing a custom name now restores the public
  username as the author label across Profile and Explore.
- Fixed V47 queued-media library upgrades so queued scans are snapshotted and
  recreated with durable retry metadata, avoiding a SwiftData startup crash
  during TestFlight upgrade checks.
- Added broader startup migration safety checks so queued image, video, audio,
  description, and mixed-media scans are tested together before release.
- Improved safe-mode diagnostics when a local library upgrade fails, keeping the
  store in place while reporting an upgrade-specific recovery reason.

### Insight Sheet

- Video scan media now starts muted playback when its Insight sheet opens, loops
  while analysis is running, and keeps a bottom-left sound status toggle.
- Fixed account-library video scans whose cloud record still listed sampled
  frames so Insight opens the playable video instead of a thumbnail sequence.
- Video scans that only have sampled frames available now fall back to the
  middle frame instead of filling the Insight carousel with all five samples.
- Hid reference images for human identifications so Insight shows only the
  user's captured media.
- Added fullscreen playback for video scan media from the Insight carousel.
- Added field-note visibility controls to the Field notes edit sheet, with
  Published and Private badges on shared Insight and Explore note cards.
- Fixed empty Field notes cards so Published or Private badges only appear once
  there are saved notes.
- Added a Non-biological pill and retention notice to non-biological Insight
  results, and hid biological-only field notes, tags, and collection actions
  from those scans.
- Simplified dog and cat Insight subtitles so pet-label scans show only the
  scientific name in the taxonomy line.
- Replaced the local New discovery pill with a richer bottom milestone banner
  for achievements and scans that add a species to the shared species
  dictionary, while preventing foreground iOS achievement notifications from
  stacking over it.
- Seeded legacy domestic cat and dog achievement completions silently so older
  qualifying scans do not trigger surprise retroactive unlock banners.
- Updated video scans so Insight opens the saved clip as the primary media item
  while scan tiles and previews keep using the poster thumbnail.
- Fixed pending video scans so playback can resolve the saved local clip
  immediately after submission.
- Fixed Overview interactions so longer ecological interaction notes wrap fully
  instead of truncating.
- Improved Insight overviews with a compact, location-aware invasive status
  summary that can show the assessed region, confidence, and Naturebook's
  rationale when available.
- Hid the upgrade plan card from the confidence details sheet for Pro users.

### Insight Chat

- Added Field chat as a bottom-sheet experience from biological Insight
  toolbars, with one saved conversation per scan, prompt chips, typed
  follow-ups, safety guardrails, and server-side token tracking.
- Moved Add to collection into the Insight header menu below field notes,
  freeing the bottom toolbar for Chat.
- Expanded Field chat's private scan context so answers can use review
  provenance, observed traits, ecology metadata, species group tags, and
  image/capture-quality signals without sending image data or public Explore
  content.
- Improved Field chat recovery and trust cues with offline read-only messaging,
  in-thread failed-send retry/edit, safety guidance headers, answer actions,
  private answer feedback, and append-only field-notes handoff.
- Added a subtle, steady rainbow glow behind the Field chat toolbar button to
  make the AI entry point easier to notice without moving or restyling the
  native button label.
- Field notes cards now show up to 10 preview lines before truncating longer
  notes.
- Field chat summaries now use human-readable observation labels instead of
  internal scan IDs.
- Simplified Field chat answer actions to icon-only copy and inline feedback,
  with thread summaries and feature feedback in the sheet options menu.
- Field chat sheet feedback is now saved privately with the scan instead of
  being telemetry-only.
- Field chat quick prompts now refresh with AI-generated, scan-specific
  follow-up ideas based on the saved observation and recent chat.
- Field chat now checks scan availability before opening so scans owned by
  another signed-in account are hidden with a clear unavailable toast instead of
  launching into a 403 error.
- Increased Field chat message text size so questions and answers are easier to
  read.
- Field chat now offers Review alternatives and Reanalyze species actions when
  follow-up wording suggests the current ID is wrong, uncertain, a different
  species, mismatched to visible traits, or worth checking again.

### Image Viewer & Reference Gallery

- Added a full-screen Insight image viewer so tapping a scan image opens a
  fit-centered, swipeable carousel with zoom and reference attribution.
- Added the same full-screen image viewer to Species Dictionary reference
  galleries.
- Added swipe-down dismissal to the full-screen Insight image viewer.
- Fixed the full-screen Insight image viewer so fit-to-screen images stay
  vertically centered.

### Community Identification (Identify)

- Added an Identify tab to Explore for Ask the Community identification
  requests, with an Insight-sheet CTA, community request queue, taxonomy search,
  disagreement prompts, and backend consensus storage.
- Consolidated Identify Requests and Activity into one filtered dashboard:
  12 open request cards under **Identify requests**, followed by 10 grouped
  **Recent activity** rows. Complete paginated feeds remain reachable through
  **See all requests** and **See all activity**, with stack titles **Identify
  requests** and **Identify activity**.
- Added service-backed Identify Activity for suggestion bursts, standalone
  consensus changes, and immutable resolution milestones. Requests and Activity
  load independently, share All/Yours/organism filters, refresh together, and
  keep request browsing available when only Activity fails.
- Identify Activity now attributes ID suggestions with each contributor's
  public username instead of their first and last name.
- Updated Recent activity outage copy so Activity failures no longer identify
  the unavailable section as Explore.
- Added owner-only Community request options with an Edit Request sheet for
  updating request notes and location sharing.
- Added reporting to Community request detail menus for requests owned by other
  users.
- Replaced the Community request loading spinner with skeleton request cards.
- Unified Explore error states around the Dictionary unavailable layout and
  Retry action style.
- Added Community identification notifications for new IDs, resolved requests,
  and helped consensus outcomes, with a dedicated Profile push preference.
- Added a View action to the Ask the Community confirmation toast so new
  requests can open directly in the Community detail page.
- Added Ask the Community as the recovery path when users reject every
  identification candidate.
- Added AI-derived starting suggestions to the Community Suggest ID sheet.
- Fixed resolved Ask the Community publishing so owner-approved species
  consensus now confirms the scan species, creates a minimal Dictionary record
  for new GBIF-backed taxa, and makes eligible media available for species
  reference images.
- Fixed Ask the Community request ownership after account identity changes so
  requests stay associated with the signed-in user and remain visible under
  Yours.
- Fixed the Ask the community request sheet title casing and kept Send/Save in
  the sheet toolbar so create and edit requests use the same form style.
- Fixed Identify request cards so their submitted-ID badge refreshes after
  someone suggests, withdraws, or restores an ID from the detail screen.
- Fixed existing Ask the community request actions in the Insight share flow
  with Edit/View buttons plus a Publish to Explore option and visible review
  disclaimer.
- Updated Community request detail images to extend into the top edge of the
  sheet, matching the Insight image presentation.
- Updated open Identify request cards and loading skeletons to hide AI-derived
  names and show only the scan image with a compact submitted-ID count overlay.
- Rebuilt Community identification around versioned Naturebook taxonomy, queued
  consensus processing, and projection-driven Explore graduation so unresolved
  requests stay out of normal Explore until verified.
- Removed the unused identification-review action from Insight and candidate
  review flows.
- Polished Community identification sheets with icon close controls and a
  cleaner disagreement reason field.
- Kept internal Community identification consensus labels out of the public
  identification timeline.

### Profile & Guest Account Polish

- Added a Share Naturebook card on Profile and a matching Settings resource.
  Before the App Store listing is live, shares use the served Naturebook
  homepage instead of an unimplemented `/invite` route.
- Added cat and dog scan achievements that unlock when you document your first
  domestic cat or dog.
- Added the cat and dog achievements to public Explore author profile sheets.
- Fixed achievements so deleting the qualifying scan from an achievement detail
  sheet refreshes the root Profile achievement card immediately.
- Matched Profile signed-out spacing below the sign-in buttons to the gap
  between the stat cards.
- Fixed Profile published-scan grids so partial rows keep rounded outer image
  corners instead of exposing sharp edges.
- Updated Pro plan card copy to match the current paywall value props for
  unlimited field scans, Pro AI vision, AI chat, multi-capture, Apple Watch
  logging, and expedition mode.
- Pro plan cards now use the intended launch prices and labels for Annual and
  the 7 Day Pass, even while App Store product metadata is settling.
- Added AI chat to the Pro paywall feature comparison table.
- Added guest profile customization: guests can now choose a public profile
  picture, display name, and username before signing in, and those choices carry
  into Apple or Google sign-in.
- Added custom public profile picture uploads for logged-in users, with
  R2-backed avatar storage, Profile picker support, and Explore/Profile identity
  refresh.
- Replaced Explore profile loading spinners with skeleton placeholders that
  match the profile layout.
- Fixed the profile scan heatmap so brand-new or empty libraries still show the
  empty contribution cells instead of collapsing the grid.
- Reordered Profile so identity and stats lead the page, followed by published
  scans, the non-Pro plan card, persona progress, the scan heatmap, and
  achievements.

### Explore Feed & Map Refinements

- Fixed Explore post web links so Universal Links open the matching native
  Explore post when Naturebook is installed.
- Updated Explore post sharing copy so shared links introduce the Naturebook
  public web preview more clearly.
- Added dynamic species-type filters to Explore Map, with horizontal filter
  pills, a detailed filter sheet, and backend-backed category counts for the
  current map region.
- Fixed Explore feed hashtag rows so long hashtag sets can scroll edge to edge
  without being clipped by card padding.
- Fixed the Explore edit-post sheet so the Save footer stays compact instead of
  expanding up the screen.
- Fixed Explore Map selected discoveries so the active waypoint appears above
  overlapping nearby waypoints.
- Fixed Explore Map overlay controls so bottom-anchored actions stay pinned near
  the tab bar when switching from Feed to Map.
- Fixed Explore Map geoprivacy so only open-location discoveries appear on the
  map; obscured and private posts stay off the map.
- Added per-post Explore geoprivacy so share/edit options can keep a post
  private, show an obscured public label, or explicitly make that post open on
  the map without changing the underlying scan default.
- Fixed Explore posts so shared discoveries keep the selected common name from
  the composer instead of drifting to dictionary defaults.
- Added a common-name picker for Explore sharing and editing so posts use the
  known species name you choose.
- Refined Explore hashtag pills with transparent backgrounds, gray borders, and
  blue text on feed cards, post detail pages, and the post composer.
- Updated Explore posts to show usernames on feed cards and post detail headers.
- Updated Explore comment composers so mentions can be inserted from
  autocomplete and resolved mention spans open the user's public profile sheet.
- Added `@username` mentions in Explore comments, with scoped suggestions for
  post authors, visible thread participants, and followed users plus mention
  notifications.
- Added an independent Notifications setting for Explore comment mention pushes,
  while keeping mention activity visible in the in-app Explore notifications
  feed.
- Explore activity and comment mention push notifications now default on for new
  installs.
- Streamlined Explore post details so species education lives in the species
  dictionary, while reference images, observation context, alternate names, and
  a direct dictionary link remain easy to find.
- Fixed Explore map count text so exactly one visible item says "1 discovery in
  view."

### Collections

- Collection thumbnails now fall back to another scan when the selected cover's
  visuals have been archived.
- Moved built-in collection tiles below the main Collections content so
  first-collection guidance appears before Favorites and Non-biological.
- Added a little more top spacing to Collections so the first cards sit more
  comfortably below the Scans toolbar.
- Added a Scans-style Collections filter sheet with sorting plus User-created,
  Smart suggestions, and Built-in collection type filters.
- Added a taller full-width Featured scans collection at the top of Collections
  with a daily rotating set of up to 24 scans from your library.
- Moved collection creation into a blue plus button in the Collections toolbar
  and removed the unused Collections sort menu.
- Converted Favorites, Needs review, and Non-biological into gallery-style
  artwork collection tiles.
- Added smart default Collections that suggest helpful scan groupings from your
  library, such as recent finds, places, review candidates, and common organism
  groups, plus an Explore posts collection, with local hide controls while Needs
  review stays pinned.
- Smart Collection cards now use varied matching scan covers, except Recent
  finds, instead of always reusing the newest scan thumbnail.

### Scans Library

- Added a full Scans filter sheet for sorting, category, dates, location, tags,
  naturalist details, photo quality, identification state, weather, season, and
  taxonomy.
- Scans filters now stack with search and sorting, with a visible active-filter
  count and a clear action that keeps the current search text.
- Changed the Scans and Collections active-filter badge to red so it stands out
  from the blue filter button.

### Describe Modality Improvements

- Fixed Describe suggestions so tapping a prompt chip no longer leaves the
  bottom toolbar hidden.
- Updated the Describe add button so empty inputs show a secondary outline state
  and filled inputs show the active filled state.
- Fixed non-biological correction reanalysis so the explanatory prompt no longer
  remains in the Describe text field as if it were user-entered notes.
- Fixed reanalysis submissions so Describe text entered for the current analysis
  is consumed into the submission and cleared from the input afterward.
- Fixed capture bottom controls getting hidden by stale keyboard state after
  leaving Describe or canceling staged input.

### Species Dictionary & Taxonomy Tree

- Added an Explore Tree scope filter so the Tree defaults to All species and can
  be toggled to My scans for a personal scanned-species taxonomy.
- Added a scheduled species model-content worker so newly materialized
  Dictionary species can hydrate habitat, lookalikes, and group tags outside of
  user scan sessions.
- Added extra species dictionary data fetches so undiscovered species can still
  load dictionary pages when users navigate to them.
- Reduced Explore bottom navigation to Observations, Field trips, and Identify,
  with Feed/Map grouped inside Observations and Requests/Index grouped inside
  Identify.
- Added a searchable Species Dictionary catalog with category browsing,
  Dictionary detail pages, and species reference imagery.
- Added Dictionary category browsing with a Recently Added featured species
  card, a full-width Your Region map card when local entries are available, an
  All row, plus region rows backed by dictionary-native range metadata.
- Added high-level Dictionary group cards with custom graphics for broad browse
  paths such as Plants, Birds, Insects, Fungi, Mammals, and Reptiles &
  Amphibians, with toolbar search available inside those species lists.
- Moved the Species Dictionary catalog into Identify's **Index** mode and
  removed Dictionary/Index from bottom navigation. Species links now select
  Identify/Index before opening detail, while request links select
  Identify/Requests.
- Disconnected the unfinished taxonomy Tree/galaxy map from MVP navigation while
  preserving its code, API support, and default-off feature flag for future
  work.
- Matched the main camera tab bar icon size, label size, and item spacing to the
  Explore bottom navigation.
- Removed search from the Explore Dictionary Tree view so the header toggle
  opens directly into the pan-and-zoom taxonomy canvas.
- Removed the filled top heading background from the Explore Dictionary Tree
  canvas for a cleaner full-canvas view.
- Updated the Explore Dictionary Tree zoom and locate controls with liquid-glass
  circular button chrome.
- Fixed the Explore Dictionary Recently Added row so its species count reflects
  the newest entries instead of duplicating the full All total.
- Fixed Species Dictionary catalog and overview surfaces so non-biological
  encyclopedia rows are filtered out before they can appear as dictionary
  records.
- Replaced species seasonality line charts with a unified month heatmap that
  shows represented totals, peak month detail, and a clearer unavailable state
  while buckets refresh.
- Fixed similar species so lookalike suggestions load reliably in insight
  sheets.
- Species dictionary galleries now admit more published Naturebook photos by
  lowering the Naturebook reference-image quality gate while keeping the species
  confidence gate in place.
- Explore Dictionary now uses already-granted location access to improve the
  Your Region category, while falling back to the device locale without showing
  a Dictionary-specific permission prompt.

### Community Taxonomy Indexing & Enrichment

- Added a GBIF-backed Community Taxonomy Index so Ask the Community search can
  suggest taxa that are not yet enriched in Naturebook's Dictionary, plus
  first-class species enrichment jobs and the first Birds coverage target for
  future Dictionary-completeness progress.
- Added an internal Community Taxonomy status endpoint so taxonomy coverage,
  GBIF import runs, and species enrichment queue health can be checked during
  rollout.
- Added a bounded GBIF Birds import worker so Naturebook can seed Community ID
  suggestions and future Dictionary coverage metrics without mirroring all of
  GBIF.
- Added safer Community Taxonomy import operations with database cursor
  tracking, lightweight coverage status checks, an operator script, and
  production deploy smoke checks.
- Added smarter dog and cat scan labels so pet results can show a likely breed,
  mix, coat pattern, or body type while keeping Naturebook's species taxonomy
  unchanged.

### Web Scaffolds & Legal Hub

- Added the initial Next.js + Mantine web app scaffold for public Explore share
  pages.
- Added public Terms, Privacy Policy, Community Guidelines, Privacy Choices,
  Support, and Legal hub pages for `naturebook.earth`.
- Added an iOS-to-web theme bridge so Naturebook-opened web pages can follow the
  app's theme preference.

### Offline Sync, Geoprivacy & Edge Functions

- Fixed successful identification returning before its cloud scan row existed,
  which could leave an otherwise completed observation unavailable to Field
  Chat, Explore sharing, field trips, and owner sync. Added owner-authenticated
  recovery for observations already affected by the gap across image, video,
  audio, mixed-media, and non-visual scans.
- Replaced technical Explore and Field Chat sync errors with customer-facing
  retry guidance. A transient Field Chat sync delay no longer hides the action
  permanently.
- Fixed Supabase Edge Function deploy reliability by routing runtime
  dependencies through the function import map and removing deploy-time
  deno.land/esm.sh runtime fetches from function graphs.
- Fixed Insight sharing and Ask the Community requests for older/interrupted
  local scans whose cloud owner row is missing, using guarded server recovery
  before owner-staged media restoration.
- Fixed non-biological corrections so they now explain the result and start
  reanalysis instead of creating an unidentified biological scan with incorrect
  confidence, phantom reference media, or premature Explore sharing.
- Fixed non-biological insight titles so stored taxonomy placeholders now
  display as "Non-biological" instead of "Unknown Subject".
- Fixed Needs review smart collections so they follow the shared non-strong and
  competitive-alternative thresholds instead of every scan that happens to have
  candidates.
- Fixed non-biological scans older than 30 days remaining on device by adding
  local foreground cleanup that mirrors the server purge window.
- Fixed geoprivacy so private scans hide location details across scan cards,
  sharing, achievements, Messages share captions, and public labels, while open
  and obscured scans restore location context at the expected precision.
- Fixed species observation charts timing out on first load by returning core
  public stats quickly while detailed life-stage and sex buckets refresh in the
  background.
- Hardened Edge media request/response handling so chunked or missing-length
  bodies are capped while streaming before V8 heap allocation can run away.
- Removed the global DwC-A continuation bottleneck by deadline-draining fair
  oldest-due queue waves under the existing claim fences, with a hard per-run
  step ceiling and independent oldest-age/backlog/expired-claim production
  monitoring.
- Removed archive-sized JavaScript CRC work from DwC-A assembly by persisting
  checksums for bounded CSV chunks and algebraically composing them in the final
  ZIP step, with cached GF(2) byte operators, fail-closed manifest length
  validation, and migration fencing that preserves worker lock order.
- Reduced share-import, expanded-original-image, local species-chart, APNs
  fanout, collection-sync, and audio-carousel resource usage to prevent OOMs,
  main-thread stalls, and idle battery drain.
- Hardened scan purge jobs so they cannot delete durable public avatar images.
- Added AI-derived sex observation metadata to scan records, the Overview card,
  Supabase persistence, and Darwin Core exports.
- Added native Messages extension groundwork for inserting cached scan images,
  cards, and descriptions into iMessage.

### Beta Feedback & Settings Changelog

- Fixed the proactive beta feedback survey so the third-scan prompt waits until
  the Insight sheet closes instead of competing with the result sheet.
- Added a one-time beta feedback survey with a warm intro screen, proactive
  prompt after meaningful use, Settings access, and private Supabase response
  storage. Manual survey access now resets after a 24-hour thank-you cooldown so
  testers can send fresh feedback again without being proactively re-prompted.
- Added a bundled in-app changelog in Settings for selected release notes,
  feature notes, and in-progress work.
- Simplified the in-app changelog to show dates without version/build labels
  until release versioning is finalized.
