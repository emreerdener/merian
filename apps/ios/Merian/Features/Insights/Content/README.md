# Insight Content

The `Content` directory handles the display of the core ecological data within
an Insight sheet.

The canonical product and lifecycle contract remains
[Insight Sheet](../../../../../../docs/features-and-hardware/05-insight-sheet.md);
this README defines the Content submodule's ownership and verification boundary.

## Purpose

This area is responsible for rendering the detailed biological text, including
the primary ecological description, toxicity warnings, conservation statuses
(IUCN Red List), and the diagnostic visual comparison against confusing
lookalike species.

## Ownership

- `Models/` owns platform-neutral fact data, user-tag validation, queued retry
  copy, and queue phrase/rotation policy.
- `Services/` is the only Content owner that resolves live repositories,
  Supabase tag synchronization, queue scheduling, app events, or haptic
  feedback. Its small closure-based dependency values are initializer-injected
  into the state owners.
- `ViewModels/` owns the rotating fact deck, tag mutation transaction state,
  queued retry single-flight/refresh state, name preferences, and Content action
  routing on the Shell-owned `InsightSheetViewModel`.
- `Views/` owns result composition, SwiftUI task timing, selection, bindings,
  sheets, and Debug fixture controls. Views perform no direct networking.
- `Components/` groups render-only cards, Field-trip progress, header, queued
  retry, scanning, and tag UI. The cross-feature `NamePickerSheet` lives in
  `Core/UI/Components` because both Insight and Explore use it.

Keep screen, route, and component initializer compatibility at the feature
boundary. Every production Content Swift file must remain at or below 600 lines.
Mirrored tests under `MerianTests/Features/Insights/Content` enforce the
directory boundary, Services-only live resolution, view networking ban,
platform-neutral Models, legacy-owner removal, and the line ceiling.

## Audio Subject Routing

Audio results use the existing `SpeciesData` and content router. Human-only
sound remains biological, routes through `BiologicalView`, and presents the
canonical `Human` / `Homo sapiens` identity. Confident non-human presence
without a resolved taxon also stays in `BiologicalView`, but displays
`Unidentified Wildlife`, omits species-match confidence and candidates, and
keeps reanalysis available when the source recording survives. A true
non-biological audio result routes through `NonBiologicalView` and displays the
sentence-cased `No wildlife detected` label with the normal non-biological
retention treatment.

Historical `Unknown Subject` / `Taxonomy Unavailable` audio is presentation-only
compatibility data: a stored biological row receives the safe unresolved label,
while a stored non-biological row displays `No wildlife detected`. Neither path
mutates the record or derives Human from `aiReasoning`. Human aliases, including
legacy `Homo sapien`, are recognized from structured identity fields and always
present the canonical taxonomy.

`BiologicalView` composes the persistent
`Components/FieldTrips/FieldTripProgressCard`. It appears after toxicity and
identification-review content and before Field notes and educational cards when
the view model has server-backed contribution rows. The card shows every
credited outing/Event under the visible **Field trips** header. While eligible
contribution rows are loading, the same position is reserved by a card-shaped,
motion-aware skeleton so later content does not jump when the server response
arrives; empty and failed responses still hide silently. The heading reuses
`InsightCardHeader`; its undivided rows use an uppercase **GOAL COMPLETE**
eyebrow, headline-sized goal name, enlarged goal artwork/check badge,
experience-only subtitle, and a prominent trailing `GoalProgressRing`. The full
row is tappable without a redundant chevron and forwards a card-specific
overview destination that deliberately omits Capture's checklist-item focus. The
card does not load data, cache contribution rows, or trigger celebration
effects.

## Scanning presentation

Foreground and queued scans share `Components/Scanning/ScanningExperienceView`,
which owns the status pill, optional actionable supplemental content, **Did you
know?** card, Field notes, and scan telemetry in that order. This keeps queued
retry timing, errors, and recovery controls ahead of educational content
whenever they are present. Foreground analysis supplies
`InferenceEngine.scanningPhaseText`. `Models/QueuedScanningPresentation` derives
queued phrases and rotation identity from exact queue/server state and reuses
generic engine phrases during ordinary active inference. An exact active-visual
live-to-queue handoff instead continues the foreground scan's ephemeral
contextual phrase order.

Foreground visual analysis begins with morphology-only generic copy. A
qualifying Apple Vision category replaces it immediately. The current toolchain
then publishes five validated, image-specific dominant-color, saturation,
lighting, light-contrast, and surface-detail cues from the bounded local
derivative on the shared 2.3-second phrase clock. A future eligible Foundation
Models provider may replace that deterministic trait deck with richer complete
cues. Source priority is monotonic, so generic or category text cannot return
after more-specific context arrives. Every currently available phrase appears
before the active deck loops to its first phrase. Partial streamed cue objects
never reach the view. The pill never claims a species, confidence, candidate
match, records or range lookup, or completed Gemini result. Audio-only,
Describe, and queued processing keep their existing cloud-analysis phrase decks.

Trait cues render as natural verb-led copy such as **Analyzing gray and green
colors**, **Reviewing softly colored areas**, and **Observing light and shadow
areas**, never a labeled `Color: description` field. The internal trait kind
selects wording but is not exposed in the pill. Internal midpoint buckets such
as **moderate color levels** and **balanced light and dark** are never rendered.

`ConfidenceBadge` retains its opacity-only label transition and intrinsic native
Button bounds as text widths change. The Debug-only
`-seedProgressiveAnalyzingFlow` fixture advances generic → Vision category →
visible trait on explicit badge taps and verifies the accessibility frame after
each transition. Release builds contain neither the seed argument nor its
fixture behavior.

The Debug-only `-seedQueuedRetryPresentationFlow` fixture supplies a scheduled
connection retry and a missing-media attention row. Its raw error field contains
a sentinel that UI automation must never find; the test instead verifies safe
reason copy, countdown/action eligibility, and suppression of **Retry now** for
missing media.

When a live request loses connectivity after this sheet opens, the engine may
publish a queue presentation only from the exact typed scan-and-attempt owner.
Existing queued content then replaces analyzing content without exposing queue
orchestration: while online, the pill keeps the current contextual phrase and
exhausts every unseen phrase before revisiting a seen phrase. Queue upload,
server-state, save, and offline/online changes do not reset its cursor.
**Waiting for connection** temporarily overlays that deck and consumes no
phrase. Only an active visual owner may keep presentation-owned carousel media;
a prepared visual handoff has generic copy without media, and audio or Describe
handoffs retain nonvisual copy. A stale caller receives no contextual state. No
saved/automatic-resume message is shown, and the handoff must not create a
synthetic **Network timeout** result or error haptic.

This behavior remains release-gated, but the source boundary is remediated. The
catch path now retains exact local presentation authority after durable
ownership retirement solely to publish queue takeover, and queue-backed Identify
does not enter the generic inline transport replay. A protected gated URLSession
regression proves the exact queued view binds after that ordering. **Analysis
delayed** remains an inference error placeholder, so a saved service failure
cannot receive non-biological success treatment. See the
[live scan connectivity handoff incident](../../../../../../docs/incidents/2026-08-live-scan-connectivity-handoff-gap.md)
for remaining exact-SHA and device closure evidence.

Queued scans supply snapshot telemetry but do not add a separate title,
media-kind summary, or file-size label. `Models/QueuedRetryPresentation` is the
only customer-copy resolver for retry state. It maps stable machine codes to
safe connection, service, processing, local-media, consent, entitlement,
retry-limit, terminal, or neutral explanations and never renders
`queueLastErrorMessage`. An HTTP `402`, whether stored directly or through the
inference-prefixed fallback code, resolves to entitlement guidance and **View
plans**. An online future deadline shows a live automatic-retry countdown plus
**Retry now** when useful. Offline work explains that it will continue when
connectivity returns, with no numeric countdown or **Retry now** action. A
dedicated local navigation action such as **View plans** may remain available
because it does not dispatch queue work. Once the deadline elapses, the helper
and retry action disappear because the analyzing state already communicates the
attempt. Consent, entitlement, missing-media, and terminal states use their
dedicated explanation or action instead of a misleading retry. Keep
`ScanningStatusBadge` on the shared pill for UI-test and accessibility
stability.

`QueuedScanContext.canRetryNow` delegates its state/deadline baseline to
`ScanQueueState.isManualRetryEligible`, the same policy used by the Scans grid's
detached snapshot. `QueuedRetryPresentation` remains authoritative for
connectivity- and reason-specific visibility, and a retry action still
re-fetches the durable row before mutation.

`QueuedContentView` keeps the one-second polling task, 350-millisecond explicit
retry refresh, phrase clock, animation, and Debug handoff marker view-local so
cancellation and focus timing stay unchanged. `QueuedContentViewModel` owns the
retry single-flight and refresh request identity. `QueuedContentDependencies`
owns scheduler, durable-row re-fetch, queue mutation, event, and feedback
effects. A stale delayed completion cannot clear a newer retry request.

Custom tags follow the same local-first contract. `UserTagValidation` owns the
50-label, 64-character, 256-byte, and control-character limits;
`UserTagsViewModel` restores the prior tags when persistence fails and starts no
cloud or search-index effect until the save commits.
`UserTagsCloudSyncCoordinator` serializes committed snapshots in mutation order
and retains the authoring account ID so delayed work cannot cross an Auth
transition. `UserTagsDependencies` contains the authenticated, account-fenced
Supabase RPC and typed search invalidation event. Cloud synchronization remains
a best-effort mirror of already committed local state: a remote failure is
logged through the private error boundary and does not roll back the SwiftData
tag or its local search invalidation.

The deterministic queued-audio UI fixture uses that badge as an explicit
post-assertion handoff control. It first proves queued navigation, shared
scanning content, and decoded audio playback, then taps the badge to replace the
exact seeded row with its completed record. Do not reintroduce a fixed delay:
hosted simulator accessibility startup can be much slower than local rendering.
The coordinator performs that transaction on the exact environment
`ModelContext` bound to the open Insight sheet and immediately invokes the
existing production queue-promotion path with the same context. The library
event still refreshes the parent Scans surface; the deterministic transition
does not depend on a cross-context merge. The coordinator is enabled only for
the exact Debug UI-test seed; normal app sessions and Release builds retain
ordinary badge behavior.

The companion `-seedLiveQueueHandoffFlow` fixture opens a normal live Insight in
analyzing mode with its exact image-backed queue row already committed. The seed
uses the same scan ID and the real `fieldtrip-park-flowering-plant` asset for
the engine's in-memory image and the Documents-backed queue image. UI automation
must observe that live state before tapping the shared badge.

The Debug-only action then calls the typed production queue-presentation
boundary. The test captures the `AnalyzingMediaCarousel` accessibility value,
which combines the animation-session continuity token and selected page
identity, and requires the exact value after the pending queue snapshot binds.
It also requires the overlay and analyzing badge to remain present, the queued
trash action to become visible and hittable, and that action to open the queued
**Cancel upload & delete** confirmation before cancellation. The sheet must
still expose only the invisible `QueuedPresentation_<scan-id>` state marker,
keep normal AI-analysis copy, omit the saved/continuing explanation, avoid
**Network timeout**, dismiss through `InsightSheetCloseButton`, and leave the
same tile in Scans. The trigger and continuity/state markers are absent from
Release and ordinary Debug sessions.

## Verification

Regenerate the project before running the focused Content and affected Shell
suites:

```bash
make xcodegen
xcodebuild -project Merian.xcodeproj -scheme Merian \
  -destination 'id=<BOOTED_SIMULATOR_ID>' \
  -only-testing:merianTests/InsightContentActionsTests \
  -only-testing:merianTests/UserTagsViewModelTests \
  -only-testing:merianTests/QueuedContentViewModelTests \
  -only-testing:merianTests/QueuedScanningPresentationTests \
  -only-testing:merianTests/InsightQueuedRetryPresentationTests \
  -only-testing:merianTests/InsightContentArchitectureTests \
  -only-testing:merianTests/InsightQueuedHandoffTests \
  -only-testing:merianTests/InsightFieldTripContributionTests test
```

`InsightContentArchitectureTests` enforces ownership folders, platform-neutral
Models, Services-only live resolution, the render-layer networking ban, retired
path removal, shared Core name-picker ownership, and the 600-line
production-file ceiling.
