# Codebase Cleanup Plan

This RFC defines the cleanup path for Merian after the public web share-page
work lands. The goal is easier navigation and safer future changes, not a broad
architecture rewrite.

## Principles

- Land product work before moving files. Refactors should not be mixed into
  feature commits unless the move is required for the feature.
- Keep behavior-preserving file splits separate from behavior changes.
- Prefer small, reviewable slices with one domain owner per slice.
- Move code toward the narrowest honest owner: feature code under
  `apps/ios/Merian/Features/<Feature>/`, shared app code under
  `apps/ios/Merian/Core/`, persistent models under `apps/ios/Merian/Models/`,
  public web code under `apps/web/`, and backend code under
  `services/supabase/`.
- Prefer product-area-first feature folders over broad type buckets. For large
  features, start with the user-facing surface (`Feed/`, `Map/`, `Identify/`,
  `Catalog/`, `Tree/`) and place that area's `Views`, `Components`,
  `ViewModels`, `Models`, and helpers inside it. Use `Shared/` only for code
  that is genuinely reused by more than one product area.
- Keep tests and docs aligned in the same change when public contracts, file
  ownership, or route shapes move.

## Phase 0: Commit Current Product Work

Before cleanup begins, land the current public web/legal work as its own commit.
That keeps the Next.js app scaffold, canonical `naturebook.earth` links,
legacy-domain compatibility, and policy pages reviewable without unrelated file
movement.

Expected verification:

```bash
cd apps/web && npm run typecheck && npm run build
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
git diff --check
```

## Phase 1: Repo Hygiene And Boundaries

1. Keep generated artifacts ignored:
   - Xcode build output and derived data
   - Next.js `.next/`, cache, coverage, and hosting metadata
   - `node_modules/` and TypeScript incremental state
2. Document root ownership:
   - `apps/ios/Merian/`: native iOS source
   - `apps/web/`: public Next.js frontend
   - `services/supabase/`: migrations, Edge Functions, and backend tests
   - `docs/`: source-of-truth architecture and contract docs
3. Keep `docs/codebase-map.md` and this RFC updated when moving folders or
   changing ownership rules.

## Phase 2: Behavior-Preserving File Splits

Start with files whose size makes local reasoning expensive. Split by existing
responsibility, keep symbols internal/private where possible, and run the build
after each slice.

For Explore and Species Dictionary, keep the vertical product folders intact:

```text
apps/ios/Merian/Features/Explore/
  Shell/
  Feed/
  Map/
  Identify/
  Notifications/
  AuthorProfile/
  Shared/
  Widgets/

apps/ios/Merian/Features/SpeciesDictionary/
  Detail/
  Catalog/
  Tree/

apps/ios/Merian/Features/Scans/
  Shell/
  Library/
  Collections/
  NonBiological/
  Shared/

apps/ios/Merian/Features/Profile/
  Shell/
  UserProfile/
  Settings/
    Plan/
    Notifications/
    Changelog/
    Feedback/
  Shared/
```

When working on the Explore feed, start in `Explore/Feed/`; that folder owns the
observations feed, post cards, post detail, comments, hashtag presentation, feed
formatting, and feed view-model extensions. Map and Community ID logic should
not be placed there.

When working on the Scans private library, start in `Scans/Library/`; that
folder owns individual scan browsing, UI-facing Library state, contained
generation-fenced search/index work, injected export/publication adapters, and
fresh `QueuedScanContext` hydration. `Scans/Shell/` owns tab and navigation
composition, queue snapshot projection and polling, Explore-media incident
state, and thumbnail pipeline coordination. Completed and queued Insight
destinations are pushed by Shell in the existing Scans navigation stack; Library
emits route values and does not present its own sheet. Collection grids, smart
collections, collection detail/editing, mutation orchestration, and catalog
presentation belong in `Scans/Collections/`; the Scans Shell remains the owner
of the shared completed-library query and passes its record set into that
feature and `Scans/NonBiological/`. The latter derives its filtered projection
and owns correction, retention, and bulk-deletion presentation without mounting
another query. Cross-surface Scans-only UI belongs in `Scans/Shared/`, while
controls reused outside Scans, such as `ScanThumbnail`, `EmptyStateView`, and
`CategoryFilterBar`, belong in `Core/UI/`.

When working on the Profile tab, start in `Profile/UserProfile/`; that folder
owns identity, published scans, achievements, persona, terrarium, heatmap, and
the profile stats actor. Settings rows and account actions belong in
`Profile/Settings/`; plan/paywall surfaces live in `Profile/Settings/Plan/`,
push toggles in `Profile/Settings/Notifications/`, bundled release notes in
`Profile/Settings/Changelog/`, beta survey flows in
`Profile/Settings/Feedback/`, and cross-area profile state lives in
`Profile/Shared/`.

Suggested first targets:

| File                                                     | Cleanup Direction                                                                                                                   |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `apps/ios/Merian/Core/AI/InferenceEngine.swift`          | Split hydration, reference image loading, local classification, persistence, and result mapping into focused extensions.            |
| `apps/ios/Merian/Core/Network/MerianNetworkClient.swift` | Move feature-specific endpoint groups into extension files or feature-owned network helpers while keeping shared transport in Core. |
| `apps/ios/Merian/Core/Utilities/UserDefaultsKeys.swift`  | Separate keys, typed settings store, migration helpers, and cloud sync preference code.                                             |

Rules for this phase:

- Do not rename public API at the same time as splitting files.
- Preserve call sites unless the old shape forces circular ownership.
- Prefer extensions in sibling files first; move types across folders only after
  the split compiles cleanly.
- Commit each large file split independently.

Implemented Explore slices:

- `Explore/FieldTrips` now uses feature-owned Models, Services, ViewModels,
  Views, and grouped Components, with live networking isolated to Services and
  production files kept below the pass's 600-line review guard.
- `Explore/Identify` now applies the same product-area boundary to its
  dashboard, complete feeds, request detail, taxonomy search, and feedback flow.
  Its presentation and asynchronous-state tests live under
  `MerianTests/Features/Explore/Identify`; wire decoding remains under Core
  network tests.
- `Explore/AuthorProfile` now separates typed routes and presentation policy,
  live dependency adapters, `@MainActor @Observable` profile/report state,
  views, and grouped components. Generation-fenced library refreshes supersede
  in-flight pagination. Its views call no endpoint, deterministic feature tests
  mirror the production owner, and the published-scan grid layout shared with
  Profile and Species Dictionary lives in Core UI.
- `Explore/Map` now separates focus/request and projection models, the live map
  dependency adapter, generation-fenced loading/filtering state, camera/gesture
  views, and grouped rendering components. Map views perform no endpoint lookup,
  and focused tests mirror presentation, spatial cache, and view-model policy.
- `Explore/Feed` now separates route/composer/presentation models, live endpoint
  and realtime adapters, catalog/comment/hashtag/post-detail state owners, route
  hosts, and grouped catalog/comment/composer/detail/card/media components. Feed
  views and components contain no direct networking; Feed and hashtag refresh
  and pagination discard stale results through request identity or generation
  state. Focused tests mirror the feature, and production files stay at or below
  the pass's 600-line review guard.
- `Explore/Notifications` now separates decoded values, row and reply-route
  presentation, live catalog/read/comment/reply adapters, generation-fenced
  catalog and reply-thread state, thin sheet hosts, and focused row/thread
  components. Views and components contain no endpoint or singleton access;
  refresh supersedes pagination, route replacement discards stale reply work,
  failed refresh keeps the last successful catalog cursor usable, and later
  authoritative reply pages replace bounded notification fallback content.
  Focused tests mirror the feature. Shared comment-avatar fallback moved to
  `Explore/Shared/Models` because both Feed and Notifications consume it.
- `Explore/Shell` now separates root-mode and initial-route policy, narrow live
  app-event/root-route/haptic-action dependencies, latest-wins notification
  preparation with token-checked success/failure commits, staged-to-pending
  navigation state, the root navigation host, sheet/lifecycle/event modifiers,
  and root picker and bell components. `ExploreView` retains view-local
  `NavigationPath`, tab, sheet, Insight-handoff, and playback state. Shell views
  contain no endpoint or singleton lookup, focused tests mirror navigation and
  notification-handoff policy, and every production Shell file stays below the
  pass's 600-line guard. Cross-surface Field-trip route values moved unchanged
  to `Explore/FieldTrips/Models`.

Implemented Insights slices:

- `Insights/Media/Carousel` now separates platform-neutral gallery, focus,
  selection, interaction, animation, and audio-presentation Models; ordered page
  and transient availability Builders; narrow live audio-session, boost,
  telemetry, and haptic Services; contained AVPlayer playback/observation
  owners; render-only Components; and focused Pages. The two root carousel views
  remain stable composition entries, direct live resolution is Services-only,
  mutable playback/seek/observer state remains private and co-located, and no
  carousel view performs networking. Focus, animation, gallery, availability,
  audio-policy, dependency-routing, and architecture tests now mirror the Media
  owner. Every production Carousel Swift file stays below the pass's 600-line
  guard. Cross-feature `AsyncLocalImageView` moved from the Carousel to
  `Core/UI/Components`; its live loader resolution now belongs to a narrow
  `Core/UI/Services` dependency adapter. The pager, domain-neutral page value,
  zoom host, pagination dots, and hero scroll-edge treatment used by Insights
  and Field Trips moved to `Core/UI/Components/MediaCarousel`; each feature
  retains its own ordering and reuse-key projection. The platform-neutral
  selection resolver consumes a model-owned candidate contract rather than the
  SwiftUI-backed Insight page value. The shared pager preserves controllers for
  equal ID/reuse keys and invalidates the native data-source cache for sequence
  or key changes; the extracted audio render surface reads live player progress
  through a closure without widening player ownership.
- `Insights/Sharing` now separates platform-neutral Share presentation values,
  Services-only publication, Community, detail, cache, event, repository, and
  feedback adapters; focused root-view-model extensions; a contained share-state
  request/revision owner; an observable Community request draft; thin Views; and
  stable Share Components. The 773-line Explore-sharing aggregate and old nested
  Community sheet path were removed. Existing component, route, root action,
  copy, accessibility, and endpoint contracts remain stable; views and
  components perform no networking; and every production Sharing Swift file is
  below 600 lines. Deterministic tests lock dependency routing, presentation
  copy, same-scan mutation versus reconciliation, replacement-request fencing,
  Services-only live resolution, and the new ownership map.
- `Insights/Content` now separates platform-neutral fact, custom-tag,
  queued-retry, and phrase policy Models; preferred-name, Supabase tag, queue,
  event, and feedback Services; contained fact, tag-transaction, queued retry,
  name-preference, and Content-action ViewModels; focused Views; and grouped
  Components. The former `Cards/` and `NamePreferences/` paths and mixed
  `UserTagsMutationController` owner were removed. Queue animation and exact
  one-second/350-millisecond task timing remain view-local; retry completion is
  request-fenced, tag persistence rolls back before suppressing external
  effects, committed tag snapshots are ordered and account-fenced, and render
  layers perform no networking. Mirrored Content tests lock bounded/control-free
  validation, dependency routing, rollback/effect ordering, cloud-snapshot
  ordering and account attribution, queued copy and phrase policy, Services-only
  live resolution, shared name-picker ownership, and the 600-line
  production-file ceiling.

Implemented cross-feature slices:

- `Features/FieldChat` now owns the private Pro conversation experience shared
  by Insights, Explore posts, and Species Dictionary pages. The historical
  `Insights/Chat` aggregate files were replaced by platform-neutral Models,
  Services-only live adapters, subject-generation-fenced observable state,
  focused Views, and grouped Components. Existing `InsightChat...` public and
  host-facing names remain source-compatible. Wire DTOs and strict response
  validation remain in Core Network, while feature and wire tests now mirror
  their respective owners. Architecture coverage enforces the cross-feature
  location, Services-only singleton resolution, platform-neutral Models, and a
  600-line production-file ceiling. Follow-up audit work centralized readiness
  task ownership, made prompt trigger ordering deterministic, restored canceled
  sends to same-UUID retry state, and re-privatized file-local helpers.

Implemented Scans slices:

- `Scans/Library` now separates sort/filter and Sendable search models, ad-hoc
  search actors, narrow export/publication/event/haptic dependencies, observable
  Library state, and a contained generation-fenced search coordinator. Library
  views perform no endpoint or singleton lookup, focused action tests replace
  every live closure and lock publication side-effect ordering, full posting
  snapshots build off-main with cooperative cancellation, existing search/filter
  tests retain deterministic debug completion, and every production Library file
  stays below the pass's 600-line guard.
- `Scans/Shell` now separates typed navigation/session and incident-presentation
  models, queue/record and thumbnail-pipeline Services, observable queue and
  incident state, the root view, and focused toolbar/tab/presentation
  components. Views and components resolve no endpoint, Supabase, app-container,
  shared loader, or background actor. Incident refresh rejects canceled and
  stale-account responses while preserving one account-replacement trailing
  request; focused tests mirror navigation, data-store, thumbnail, and overlap
  policy. Every production Shell file stays below the pass's 600-line guard.
- `Scans/Collections` now separates membership/catalog/smart presentation
  models, save-first mutation and smart-suggestion services, observable catalog,
  detail, selection, and smart-detail state, a feature-owned collection-action
  alert, and Collections-local card/catalog components. The Shell-owned
  completed-library query replaces four duplicate Collections queries;
  Collections views/components perform no fetch or singleton lookup. Focused
  tests lock validation, protected-system-folder handling, rollback and
  side-effect ordering, catalog filtering/empty-state independence, smart share
  mapping, and catalog/detail/selection membership-sensitive refresh identity.
  Every production Collections file stays below the pass's 600-line guard.
- `Scans/NonBiological` now separates stable presentation/correction and
  immutable erasure models, narrow purge/database/file/routing/feedback
  Services, observable filtered and mutation state, a thin destination, and
  status Components. The Collections card and root app route converge on the
  Shell-owned typed destination, which consumes the Shell record query instead
  of mounting another fetch. Focused tests lock copy and routing parity,
  eligibility refresh, mixed-media snapshot mapping, completion ordering,
  failure restoration, and overlapping deletion rejection. Actor coverage locks
  the commit-time eligibility fence so a stale snapshot cannot erase a scan
  reclassified as biological, while the UI fixture locks native Back behavior
  and Collections-tab preservation. Every production NonBiological file stays
  below the pass's 600-line guard.
- `Scans/Shared` now separates detached queued-row policy, injected grid
  interaction feedback, single-delete orchestration, Scans-only grid
  composition, and deletion alert presentation. Shared views/components perform
  no persistence read, endpoint call, loader/repository use, or app-container
  lookup. Cross-feature `ScanThumbnail` projection/rendering and
  `EmptyStateView` moved to `Core/UI`, while immutable backfill inputs moved
  beside the Core image actor. The thumbnail loader has a feature-neutral
  service owner, cancellation-fences results from shared cache work, and keys
  tile tasks by pixel size and audio/reference policy. Queued grid and Insight
  values share one manual-retry eligibility rule on `ScanQueueState`. Focused
  tests mirror thumbnail presentation/loading, queued recovery and callback
  ordering, and deletion outcomes. Every production Shared file stays below the
  pass's 600-line guard.

Implemented Profile slice:

- `Profile/UserProfile` now separates typed Profile, identity, achievement, and
  publication models; narrow live Services; generation-fenced observable state;
  grouped Views; and presentation-only Components. Views and components issue no
  endpoint calls and resolve no app-container, network-client, haptic, or
  image-loader singleton. `ProfileDatabaseActor` owns SwiftData projections; the
  live dependency adapters own actor creation and local route lookup.
  Published-scan refresh supersedes in-flight pagination, Profile refresh
  rejects stale account generations, canceled current loads return to a
  retryable state, and achievement foreground loading clears when a background
  refresh supersedes it. Avatar selection/upload work is request- and
  account-fenced and consults the live view presentation slot before committing
  a prepared preview or error. The long-lived post-inference Profile actor is
  container-identity-scoped and refreshes its projection before every award
  evaluation. Focused tests mirror all state owners, persona boundaries,
  recovery presentation, achievement policy, actor-cache replacement, and
  projection behavior. Every production UserProfile file stays below the pass's
  600-line guard.
- `Profile/Settings` now separates root and subarea presentation models, narrow
  account/export/preference/notification/RevenueCat Services, observable
  lifecycle state, thin Views, and grouped Components. Views and components
  perform no endpoint, Supabase SDK, notification-center, app-container,
  repository, or platform-action lookup. Account deletion still delegates its
  durable protocol and recovery to `SupabaseManager`, with local purge behind a
  small adapter. Feedback, notification, export, sign-out/deletion, and plan
  state have deterministic suites; an architecture test locks the live-service
  boundary and 600-line ceiling. Cross-feature complimentary-scan display state
  moved to `Core/UI/Models`. The Profile Shell composes the environment-owned
  geoprivacy and hardware adapters. Geoprivacy writes are account-fenced,
  serialized, and latest-selection-coalesced; expedition mode persists before
  constraint reevaluation; notification refreshes discard stale generations; and
  sign-out, deletion, export, survey, purchase, restore, and redemption actions
  reject conflicting overlap.
- `Capture/Shell` now separates deterministic media and presentation models,
  closure-based live Services, responsibility-specific view-model extensions,
  grouped goal/media/shared Components, root Views, and routing/lifecycle/
  presentation Modifiers. Services alone construct the live network client,
  remote-media URL session, connection prewarm, share/account lookups, keyboard
  platform actions, and feedback adapters. Models remain deterministic. An
  encapsulated operation-state owner contains route handoffs, timeout
  protection, import coalescing, crop ordering, and mutable task handles in
  private storage. The external-import owner performs its retry decision and
  task-handle release atomically on the MainActor, closing the completion-time
  lost-wakeup window. UI-only pager, focus, expansion, scroll, and exact
  dismissal timing remain in Views and Modifiers. Mirrored tests retain the
  canonical workspace selector, add deterministic policy and operation-state
  coverage, and enforce the live-service and Models boundaries plus a 600-line
  production-file ceiling. Cross-modality composing layout moved to
  `Capture/Shared/Utilities`, and the image wrapper shared with Insights moved
  to `Core/Media`; Shell Models now remain free of SwiftUI and UIKit imports.
- `Capture/Scan` now separates platform-neutral still/video requests, prepared
  results, and sampling policy; narrow camera/context/Photo Library/media/
  entitlement/feedback Services; bounded still, frame, playback, and WAV
  preparation; photo/video/semantic-feedback view-model actions; and a
  generation-fenced still/pre-recording/recording/progress task owner. Scan
  views/components perform no networking or global service resolution, and every
  production file stays below the 600-line guard. The unused shutter control was
  removed. Cross-feature crop encoding moved to `Core/Media`, while the crop
  view and presentation-only flash control moved to `Core/UI`. Capture-specific
  source/ crop metadata remains in `Capture/Shared`, and Profile owns its own
  bounded avatar-crop presentation value. Callers inject haptic/camera effects
  so the shared controls remain passive. Detached media work now propagates
  parent cancellation, and newly created WAV/compressed-playback files remain
  leased until staging accepts them so timeout-losing or otherwise unconsumed
  results cannot leak artifacts. A staged video finalizes its recording
  generation and cancel UI before the optional PhotoKit save completes, while
  the capture task still retains the original recording through that save.
  Mirrored tests lock sampling, playback presentation, task replacement,
  lifecycle overlap rejection, temporary-file transfer and cleanup, detached
  cancellation, dependency routing, ownership, platform-neutral Models, and the
  line ceiling.
- `Capture/Submission` now separates deterministic admission/media/goal/latency
  Models, normalized staged payload and sendable context values, narrow live
  admission/context/deferred-update/telemetry Services, and visual, nonvisual,
  Describe, admission, and presentation view-model extensions. Submission has no
  view layer and its ViewModels issue no endpoint calls. The actor-backed grace
  owner races context acquisition alone against 150 ms; late context is
  committed to the durable queue before the remote update, whose service makes
  at most one retry after 500 ms without triggering inference. Endpoint,
  transport, and task cancellation are terminal. Queue rejection, queue-only
  routing, connectivity loss, supersession, and unavailable foreground ownership
  cancel context work with no consumer; a timeout-losing late merge retains only
  the service and bounded telemetry inputs rather than the workspace view model
  or complete display-image collection. Queue-first persistence and the exact
  scan/foreground-generation identity remain intact. Mirrored tests lock
  deterministic policy, context-race and cancellation, retry behavior, existing
  submission parity, ownership boundaries, removal of the three former aggregate
  files, and the 600-line production-file ceiling.
- `Capture/Staging` now separates the ephemeral aggregate, capacity policy,
  chronological modality nodes, small media wrappers, and UIKit-backed image
  bundle. Submission owns the live/replay timeline, aligned media projection,
  and exact hand-written `Identify*` request descriptors; their Swift names,
  Codable fields, JSON keys, legacy fallback ordering, and sparse replay indexes
  are unchanged. `ActiveScanToolbar` consumes the canonical staged order without
  a duplicate sort. Mixed tests were rehomed to Staging, Shell, Submission, and
  Core Utilities owners, with deterministic projection/descriptor tests and a
  new Staging architecture/600-line guard.
- `Capture/Describe` now separates deterministic prompt, subject, tag-ranking,
  and text-composition Models; narrow preference, feedback, keyboard, subject
  delay, and speech-manager Services; observable prompt and lifecycle
  ViewModels; workspace-scoped Views; and layout-focused Components. The former
  aggregate input view, Managers folder, Manager label, and tag-tracker
  singleton were removed. Cross-feature `SpeechManager` moved to `Core/Hardware`
  without changing its AppDI, permission, audio-session, or teardown contract.
  Delayed subject inference is text- and prompt-flow-generation-fenced;
  dictation startup, stop/restart, and partial-result delivery share a separate
  session generation so stale non-cooperative completion cannot mutate
  replacement state. Replacement dictation also cancels without invoking shared
  teardown while startup is configuring, waits for that startup before entering
  the shared speech manager, and stops a cancellation-ignoring stale success
  before replacement. Verified-start status clears a request when the shared
  manager is busy or never reaches recording. UI-only focus, UIKit scrolling,
  sheet presentation, and tag auto-advance timing remain in Views/Components.
  Mirrored tests lock prompt behavior, exact text composition, stable tag
  ordering, inference and dictation overlaps, Core speech lifecycle, ownership
  boundaries, platform-neutral Models, concrete-hardware-free ViewModels, and
  the 600-line ceiling.
- `Capture/Record` now separates immutable audio presentation and layout policy,
  the only concrete audio-manager/haptic adapter, UI-only idle and scrub state,
  a thin full-screen view, and focused components. Shell resolves the live
  manager snapshot and retains permission and record/pause/resume/stop/review
  controls; Submission retains queue-before-inference orchestration. The shared
  audio-session coordinator has its own `Core/Hardware` owner, and
  `AudioCaptureManager` receives maximum-duration feedback from AppDI instead of
  resolving haptics. Manager-owned start/resume handles plus a generation fence
  reject late activation, DSP, and countdown commits across lifecycle changes;
  duplicate resume requests coalesce. The coordinator commits one-shot lease
  ownership only after successful activation. Failed replacement restores the
  prior configuration; failed rollback or first activation deactivates partial
  state instead of publishing unknown ownership. Reusable palette/raster/layout
  policy moved to `Core/Media`, the SwiftUI spectrogram moved to `Core/UI`, and
  the audio/video countdown badge moved to `Capture/Shared`. Mirrored feature,
  hardware, and media suites lock presentation, scrubbing, feedback injection,
  DSP/noise-floor and raster behavior, transition/lease concurrency, ownership
  boundaries, platform-neutral Models, and the 600-line production-file ceiling
  without changing the 15-second WAV, confirmation, staging, submission, copy,
  accessibility, or audio-session contracts.
- The Capture-wide integration audit verified Shell → Scan/Record/Describe →
  Staging → Submission ownership, chronological media projection, live/replay
  request-key parity, queue-before-inference ordering, and the absence of DTO or
  SwiftData schema drift. It closed two cross-boundary gaps: still shutters and
  video admission/start work are now generation-fenced across scene, mode,
  presentation, teardown, and reset transitions; and the camera preview now uses
  its injected `CameraManager` instead of resolving the singleton. Active video
  keeps its established graceful stop-and-stage semantics. Deterministic overlap
  and architecture guards lock these contracts.
- `Insights/Shell` now separates deterministic presentation values, narrow live
  dependencies, scan-bound state projections, root composition, Shell-only
  components, and embedded-navigation modifiers. The former display and test
  aggregates were removed; the view model, sheet, and content sources are split
  by responsibility while preserving their initializer, route, copy, layout,
  media, lifecycle, accessibility, queued-handoff, and Field-trip contracts.
  Shell Services are the only live network/auth/repository/routing/feedback
  owner, views and view models issue no endpoint calls, mirrored tests lock the
  same behavior, and every production Shell Swift file remains below 600 lines.
  The final audit preserved all 108 former test cases across suites named for
  their responsibilities, rekeyed the critical-result and documentation-contract
  guards to those owners, and made queued-completion polling exit immediately on
  task cancellation. `InsightSheetView+Content.swift` now names its mixed
  root-content responsibility accurately; the largest production Shell file is
  524 lines.

### Completed Scans Collections Persistence Repair

The Collections organization pass now includes the reviewed V50 source-only
SwiftData repair. V50's complete relationship-bearing graph is frozen in
`Models/Schema/SchemaV50Snapshots.swift`, including its historical
`ScanCollection.isDeleted` field and goal-hint companion. The active
`MerianActiveSchemaV50` owner uses `isPendingDeletion` with
`@Attribute(originalName: "isDeleted")`, so the application tombstone survives
save/refetch while the persisted V50 model and Supabase/JSON field `is_deleted`
remain unchanged.

Released V50 stores open as current without a migration plan; the V49
source-isolated plan applies the one required V49 → V50 hop. The full historical
plan is linear through V42 → V49 → V50, while V43...V48 keep source-isolated
repair plans. Disk fixtures prove metadata-based plan selection, tombstone
true/false values, relationship and goal-hint retention, and second-context
reads. Collection mutation and database-actor suites cover exact payload
projection, inbound reconciliation fencing, rollback, and acknowledgement-only
purge. Recovery dispatch treats V50 as current, and checksum fallback tries that
current-store path before the exhaustive V49...V42 source-isolated ladder.

Do not synthesize deletion from transient view state, hard-delete before cloud
acknowledgement, or edit a frozen schema. Any future persisted-model change must
repeat the schema-update procedure and add its own source-isolated recovery
lane.

## Phase 3: Ownership Cleanup

After the large files are split, move code to clearer long-term homes:

- Explore-specific network DTOs and endpoint wrappers should live under the
  narrowest Explore product area when only one area uses them, or under
  `apps/ios/Merian/Features/Explore/Shared/Network/` when reused across multiple
  Explore areas. Only move them outside Explore when another feature depends on
  the same contract.
- Insight-specific export, carousel, and result-rendering helpers should stay
  under `apps/ios/Merian/Features/Insights/`.
- Capture modality code should stay under
  `apps/ios/Merian/Features/Capture/<Scan|Record|Describe>/`.
- `Core/UI` should contain reusable primitives only; one-off feature chrome
  should move back into the feature.
- `Core/Utilities` should shrink over time. New utilities belong there only when
  at least two features use them.

## Validation Gates

Every cleanup PR should run the narrowest relevant checks, plus the full app
build for moved Swift files:

```bash
git diff --check
xcodebuild -scheme Merian -project Merian.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

For web changes:

```bash
cd apps/web
npm run typecheck
npm run build
```

For Supabase function changes:

```bash
cd services/supabase/functions
deno check --config deno.json <changed-entrypoint>.ts
deno task test
```

## Stop Conditions

Pause the cleanup slice and make a smaller plan when:

- a file move requires behavior changes,
- a split touches more than one feature boundary,
- generated Xcode project changes become noisy,
- tests need large rewrites just to follow a mechanical move,
- or an in-progress product bug would become harder to isolate.
