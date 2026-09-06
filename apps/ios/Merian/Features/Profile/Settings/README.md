# Settings

The `Settings` directory owns the user-facing configuration screens, preference
controls, data export, subscription management, and account lifecycle actions
for the Profile tab.

## Structure

- **Models** contains Settings-only presentation values. Cross-feature display
  values, such as `ComplimentaryScanDisplayState`, belong in `Core/UI/Models`.
- **Services** contains small closure-based live adapters for account lifecycle,
  export, preference, review/share, and debug actions.
- **ViewModels** contains `@MainActor @Observable` state for sign-out, account
  deletion, export, and serialized geoprivacy updates.
- **Views** owns the root Settings route, detailed preference pages, and the
  account-deletion sheet. Views retain navigation, sheet, binding, focus, and
  animation timing.
- **Components** owns Settings-only section composition plus reusable rows and
  banners grouped by Shared, Plan, and Developer responsibility.
- **Plan** owns paywall and plan presentation models, RevenueCat adapters,
  purchase/restore state owners, views, and components.
- **Feedback** owns survey wire and presentation models, the submit adapter,
  draft/validation/submission state, choice components, and the thin survey
  host.
- **Notifications** owns notification preference models, authorization and
  remote-registration adapters, observable permission state, and its view.
- **Changelog** owns bundled release-note models and presentation.

## Ownership boundaries

Views and components do not call endpoints or resolve the Supabase client,
notification center, application container, camera manager, repository, or
RevenueCat action singleton. Live side effects are confined to the matching
`Services` dependency value and injected into the observable state owner or
component. State owners without environment-owned inputs use their subarea's
default live dependency value; `ProfileView` explicitly composes the adapters
that require its environment-owned managers. `PlanCard` continues to observe the
canonical shared entitlement snapshot for reactive display, while purchase and
subscription actions use a narrow RevenueCat action adapter.

`ProfileView` is the composition boundary for environment-owned geoprivacy and
hardware dependencies. `GeoprivacySettingsViewModel` serializes writes and
coalesces queued selections to the latest value. The injected preference action
persists expedition mode before reconciling hardware constraints; the leaf
picker and preference component resolve neither live owner themselves.

Asynchronous actions preserve one authoritative interaction session. Export,
feedback, sign-out, deletion, purchase, restore, and code-redemption owners
reject conflicting overlap. Notification authorization refreshes are
generation-fenced so a replaced request cannot overwrite newer state. Failed or
superseded work cannot publish stale success or error feedback into its
replacement.

Core Network's `Endpoints/MerianNetworkClient+Exports.swift` owns the DwC-A
queue request; `MerianNetworkClient+ProductFeedback.swift` owns survey and
Community feedback HTTP submission. Settings keeps its export and survey
Services/ViewModels and the existing survey request model. Transport preserves
15-second export and 30-second survey deadlines, body-ignored success, and
server-denial propagation without enabling exports or adding mutation replay.
The
[Network focused matrix](../../../Core/Network/README.md#enrichment-export-and-feedback-verification)
covers the moved endpoint tests; `FeedbackSurveyTests` now contains only prompt
and cooldown policy, with no shared network override.

`SettingsTabView` remains the route and sheet composition owner. Detailed
screens keep UI-only selection and presentation state locally. Account deletion
delegates live protocol and recovery effects to `SupabaseManager`, which applies
the deterministic classification and phase sequencing owned by
`Core/Network/Auth/`; the sheet supplies its environment `ModelContext` and
private-map reset action to a narrow local-purge adapter. No Settings owner may
reconstruct the server deletion protocol or mutate Auth directly.

All production Swift files in this directory are held to a 600-line review guard
by `SettingsArchitectureTests`. The same test prevents presentation files from
reintroducing direct live-service lookups. Feature behavior is covered by the
mirrored suites under `MerianTests/Features/Profile/Settings`; transport and
shared-manager contracts stay with their canonical Core suites. The focused
selectors and manual matrix are canonical in the
[Profile Settings testing strategy](../../../../../../docs/development-guides/08-testing-strategy.md#profile-settings).

`Notifications/Services/NotificationSettingsDependencies.swift` delegates remote
registration synchronization to `PushNotificationManager`. Settings retains
permission presentation, preference decisions, and stable synchronization
reasons; Hardware retains token/registration lifetime. The request payload lives
in `Core/Network/Endpoints/MerianNetworkClient+Notifications.swift`, not in
Settings. For changes across this boundary, also run the
[notification/public-profile matrix](../../../Core/Network/README.md#notification-and-public-profile-verification):
`NotificationSettingsViewModelTests` covers Settings state, while
`NotificationEndpointTests` and the shared endpoint transport suite cover the
wire request, response handling, and replay policy.

The Profile product-area contract is summarized in
[`06-profile-and-gamification.md`](../../../../../../docs/features-and-hardware/06-profile-and-gamification.md)
and the app-wide feature inventory in
[`07-feature-modules-and-ui.md`](../../../../../../docs/features-and-hardware/07-feature-modules-and-ui.md).

## Feedback campaign policy

`FeedbackSurveyPromptPolicy` suppresses the automatic prompt once the current
campaign has been dismissed or submitted. Settings keeps manual survey entry
available while the campaign is active. `FeedbackSurveyCampaign` retains the
submitted-state display for 24 hours after a successful submission; preparing
the form after that interval permits a fresh draft without rearming the
automatic prompt. `FeedbackSurveyViewModel` owns draft validation and
single-flight submission through `FeedbackSurveyDependencies`.

This is client presentation policy, not a transport cooldown or server-wide
one-submission limit. The
[survey endpoint contract](../../../../../../docs/backend-and-data/05-api-contracts.md#deno-submit-feedback-survey-edge-node)
owns campaign and payload validation. `FeedbackSurveyTests` covers prompt and
cooldown policy; `FeedbackSurveyViewModelTests` covers draft and interaction
state, and the Core Network matrix above covers HTTP submission.

## Purpose

This area provides users with control over their app experience. It manages
general preferences, the Capture workspace, geoprivacy, data export, and account
lifecycle (signing in/out and deletion). It operates in conjunction with the
`ProfileViewModel` and updates global preference state through injected
environment owners such as `AppSettings`, `ConsentManager`, and
`RevenueCatManager`.

Temporary image caching is automatic and is not exposed as a Settings action.
The bounded in-memory thumbnail cache evicts under pressure, while durable scan
media and pending uploads remain under their existing data owners. Settings must
not offer a broad cache-clearing action alongside account lifecycle controls.

## Privacy and processing permissions

Google Gemini processing is required for Naturebook's core identification
experience. Permission is granted through the required onboarding disclosure,
and Settings intentionally provides no Gemini processing opt-out. A user who
does not permit that processing cannot use the scanner. The consent ledger and
inference gates still fail closed when required evidence is missing, outdated,
or revoked by historical or remote account state.

The first row in Settings → Resources is **Analytics & diagnostics**. Its
binding appends an immutable account-wide PostHog grant or revocation through
`ConsentManager`. Absence of a grant is off. Withdrawal opts out and closes the
SDK, synchronizes across devices, and never changes core functionality. The
displayed and applied state comes from the provider-wide greatest accepted
revision across all disclosure versions. An older-disclosure revocation at that
head remains off; only a current-disclosure head grant can reopen PostHog.

That paragraph is the required behavior. The withdrawal transport/order and
offline ghost-account handoff findings are complete in source: reset-time
feature-flag work is rejected locally after the transport gate closes, and a
durable handoff suppresses analytics until local evidence is rebound, pushed,
refetched, and the queue removal is verified. Account restoration activates and
flushes the target ledger before refetch; Realtime has independent channel
ownership, bounded retry, and foreground repair; OAuth account replacement
suppresses analytics before session installation and reconciles the actual
session afterward. The final synchronization merge rechecks task cancellation,
observed user, Supabase SDK session, and synchronization generation before an
account-wide grant can alter the ledger or reopen capture. All tracked findings
are closed in source. Internal test builds may continue; keep public production
held until the same SHA passes the hosted iOS and Supabase candidate gates and
the external controls in the
[production consent readiness record](../../../../../../docs/legal/production-consent-readiness-2026-08-03.md)
are complete.

## Account deletion

`DeleteAccountSheet` delegates confirmation state to `DeleteAccountViewModel`.
Its injected `AccountDeletionDependencies` delegates the authenticated
`safe-delete` preparation/commit and recovery effects to `SupabaseManager`. That
manager applies `AccountDeletionTransitionPolicy` and `AccountDeletionWorkflow`;
the separate local-purge adapter owns repository access. A validated
pending/`202` or completed/`200` receipt accepts deletion; prepared/`200` and an
arbitrary successful `2xx` do not. Completed means relational cleanup, delayed
R2 verification, provider disposition, and Auth removal are confirmed. A new
commit normally returns pending/`202` because the durable server-side reaper
must sweep and later verify storage before deleting Auth. Accepted pending and
completed receipts are safe points for local sign-out and device-data cleanup.
Public recovery requires an explicit acknowledgement-state Boolean. Legacy
recovery and acknowledgement admit only `pending|completed`; v2 recovery alone
may additionally admit an unacknowledged, provider-neutral `not_committed`
receipt. Before Settings can trigger any local cleanup effect, the extracted
workflow independently rechecks success and `pending|completed`, so a malformed,
prepared, or noncommitted receipt cannot authorize sign-out or erasure. While
sign-out purchase continuity is pending, the Settings action and confirmation
button remain disabled. The server independently returns
`409 purchase_continuity_pending` so a stale or second client cannot delete the
source or exact bound anonymous destination; the user must finish sign-out
first.

The manager's v2 path first persists `capability_preparation_pending`, then
creates or loads the read-after-write-verified device-only Keychain envelope.
New envelopes contain separate recovery and acknowledgement proofs. Before any
destructive commit, it sends both proofs through non-destructive prepare,
requires a valid prepared receipt, persists `capability_prepared_pending`, and
then persists `capability_intake_pending`. The transition blocks ordinary Auth
and account work while retaining its exact cached session. Relaunch uses public
proof recovery rather than starting another deletion. Existing v1 proofs keep
their legacy intake/replay path; they are not rewritten into v2 mid-recovery.
The workflow checks task cancellation before its first recovery marker. The
legacy branch checks again after its intake marker; the v2 branch checks before
preparation, after the non-destructive response and before the prepared/intake
marker pair, and after that pair before destructive commit. A cancelled task
preserves any durable evidence already written for recovery and dispatches no
later destructive request.

A valid accepted receipt advances through `capability_cleanup_pending`, durable
manual-provider notice recording, verified local Supabase sign-out, synchronous
private-map derived-state reset, complete active-schema purge, verified
account-derived preferences cleanup, server acknowledgement, and
`capability_retirement_pending`. The cleanup preserves device settings, consent,
the deletion marker, and the manual Apple notice. After durable local cleanup,
the shared runtime-reset owner refreshes observable settings and clears legacy
gamification, the generation-fenced Explore app badge, and RAM image state. V2
acknowledgement uses only its independent second proof after local cleanup.
Verified Keychain removal precedes marker clearing; the recovery overlay remains
visible with bounded retry while a phase is unresolved.

Definitive cancellation is separate from accepted-deletion cleanup. For v2,
`not_committed` or a genuinely unknown proof retires only the unused proof and
intent, preserving local data and restoring only the same eligible cached
session. Legacy unknown proofs and ambiguous errors retain the barrier. A
received `409 purchase_continuity_pending` permits legacy rejection retirement;
v2 additionally requires recovery to establish `not_committed`. The workflow
admits success and failure results only for the exact transition session and
generation; stale prepared-v2 failures cannot enter recovery classification.
Cached-session restoration revalidates before marker removal and performs no
failable telemetry or entitlement work afterward. The workflow persists
`capability_rejection_retirement_pending` before verified proof removal and
clears the marker last, without signing out or purging. A matched committed
capability's `account_deletion_recovery_expired` permits conservative cleanup
with the manual notice and expiry-tolerant acknowledgement; the distinct
`account_deletion_recovery_preparation_expired` never authorizes erasure.

Core Network owns the six wire methods, pure receipt/proof validation, and
deterministic deletion classification and sequencing, not Settings or the
Keychain store. See its
[ownership guide](../../../Core/Network/README.md#account-deletion-and-recovery-ownership),
[preparation receipt contract](../../../Core/Network/README.md#preparation-receipt-contract),
and
[integration checklist](../../../Core/Network/README.md#account-deletion-integration-checklist).
The checked-in four-field preparation response has a dedicated native receipt
and a shared Deno/Swift fixture. That source-level compatibility does not make
the workflow above a claim of successful live end-to-end execution.

Every accepted-deletion or public-recovery receipt must also contain
`manual_provider_revocation_required`. When true, `SupabaseManager` records the
durable app-level notice before sign-out. The root app then presents Apple's
Settings/support instructions on launch and foreground until the user explicitly
confirms removal. New Apple accounts normally use automatic server-side
revocation; this fallback exists for accounts authorized before a refresh token
could be captured. The confirmation sheet explains both paths.

Older binaries do not implement the required accepted-receipt field or durable
notice. App Store availability of the supporting build is not proof that those
clients received the fallback. Public promotion requires either an enforceable
minimum-supported-build control with a clear update path back to this in-app
deletion flow, or an independent server-delivered manual fallback.

The server owns all ordering and retry semantics. The app must not send a target
user ID, attempt to delete the Auth identity directly, or retry individual
cleanup phases. Account detachment and private-content clearing are verified
before Auth removal, while media deletion continues through the existing durable
storage-cleanup outbox.

Every submitted scan also contributes mandatory Scientific Data. Account
deletion leaves that observation as an ownerless tombstone with exact
coordinates/elevation, time, taxonomy, identification, environmental, quality,
and provenance facts unchanged. It removes account attribution, media, private
free-form notes, semantic/public location labels, device context, and custom
tags. `DeleteAccountSheet` must state both sides of this boundary and must not
describe account deletion as deleting every submitted scan. Geoprivacy governs
public display, not this restricted backend retention.

The complete boundary and required update procedure are canonical in
[`17-scientific-observation-retention.md`](../../../../../../docs/backend-and-data/17-scientific-observation-retention.md).
The Apple-specific capture, deletion ordering, legacy fallback, and production
gate are canonical in
[`20-sign-in-with-apple-account-deletion.md`](../../../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md).

## Plan and prelaunch purchase testing

Settings → Plan is the canonical manual entry point for `PaywallView`. Every
release build enables the advisory local meter, while Supabase remains the
authoritative quota boundary. Debug builds can bypass only the local meter from
Settings → Feature Flags or with `MERIAN_DISABLE_FREE_SCAN_LIMIT=1`; the backend
still reserves quota and applies the durable plan limits. Purchase QA should
open Plan directly instead of relying on a quota-triggered presentation.

The paywall is ready only when RevenueCat's current offering resolves packages
for both `pro_week` and `pro_annual`. A successful RevenueCat login proves the
Supabase customer identity was linked, not that StoreKit returned products.
Simulator Test Store, local StoreKit, and TestFlight/App Store sandbox setup are
documented in
[`02-revenue-and-identity.md`](../../../../../../docs/features-and-hardware/02-revenue-and-identity.md#prelaunch-purchase-testing).

## Complimentary display and exhaustion

When the server's entitlement mode is cut over, Settings → Plan is one of only
two places that shows the complimentary countdown; Results is the other.
`PlanCard` uses the current-launch server snapshot to show scans remaining out
of three and explicitly keeps the separate daily Flash allowance visible. It
never calculates a calendar expiry.

After the third durable Pro result, the card shows exhaustion and an Upgrade to
Pro action. That result and all earlier stored Pro results remain fully
viewable. Only new Pro actions lock; an ordinary compatible capture can still
use the daily Flash policy. Before online launch verification succeeds,
complimentary-only actions remain locked, while paid RevenueCat offline access
is preserved.

The paid **7 Day Pass** product, price treatment, and purchase copy are
unchanged. Public Pro badges continue to use paid status rather than
complimentary functional access. See
[Three Complimentary Pro Scans](../../../../../../docs/backend-and-data/18-complimentary-pro-scans.md).

In a Debug simulator build, Settings → Developer → **Preview Pro scans** opens a
deterministic gallery of the real Settings card and Results badge. Its segmented
control covers three, two, one, and exhausted states. The gallery uses a local
presentation override and never mutates the signed-in account, server ledger, or
RevenueCat purchase state. Visible counters say “3 Pro scans remain” or “1 Pro
scan remains”; internal entitlement code retains its complimentary names.

## Preference layout

The top general-preferences section begins with Theme. **Open Explore on
launch** follows Theme and sits directly above Notifications. The toggle uses
`safari.fill` and the user-facing description:

> Show Explore when you launch Naturebook. Close it to return to Scan, Record,
> or Describe.

The setting is opt-in. `opensExploreOnLaunch` registers a `false` default in
`UserDefaults`, persists through `AppSettings`, and participates in
`reloadFromDefaults()` so externally changed defaults are reflected in the
running settings model.

The section previously named **Capture** is now **Workspace**. It continues to
own Camera, Audio, **Reorder modes**, Field trip goals, and confirmation
preferences; the rename does not move those controls or change their behavior.

### Reorder modes

`captureModeOrderRaw` stores a comma-separated permutation of `visual`, `audio`,
and `describe`; the registered default is `visual,audio,describe`.
`CaptureMode.userOrder(from:)` ignores unsupported values and appends any
missing supported modes. `CaptureWorkspaceView` writes that healed sequence back
when necessary. The Settings reorder UI itself always emits one entry per
supported mode.

The workspace samples the first decoded mode in its initializer. Therefore a
fresh workspace opens directly into the user's first mode, whether that is Scan,
Record, or Describe. Audio-first does not start the camera, and
Description-first mounts the text workflow immediately. Reordering while the
workspace already exists preserves the active mode and reanchors that page in
the new sequence; the new first mode becomes the default on the next fresh
workspace launch. The same decoded sequence supplies the equal-width icon
segments in `MediaModeToggle`; changing the preference rebuilds those segments
once while preserving the active page and its accessible mode name.

## Fresh-launch contract

`MerianApp` samples `opensExploreOnLaunch` once when a new process is created.
It may present the generic Explore feed only after onboarding and current
required consent are complete. Returning from the background never resamples the
preference and never reopens Explore.

Explicit user intent always outranks the generic launch destination. A Photos or
Files image handoff dismisses Explore and continues through the normal
staging/crop workflow. Deep links and tapped notifications replace the generic
feed with their requested Explore post, community request, scan Insight, or
Scans library destination. While the initial Explore sheet is visible, Capture
does not start camera hardware; dismissing the sheet returns to the configured
Scan, Record, or Describe mode. Presenting Explore also marks its one-time
**New** chip as seen.

## DEBUG milestone previews

Developer settings can enqueue representative payloads through the production
`MilestoneToastPresenter` without changing user progress or notification
authorization:

- achievement previews, including long-title coverage;
- `Preview New to Naturebook notification`
  (`Settings_PreviewNewToMerianNotification`); and
- `Preview Field trip progress toast`
  (`Settings_PreviewFieldTripProgressToast`), which shows the goal artwork,
  goal-complete title, outing name, and typed tap destination used after a saved
  scan.

Use the Field trip preview at compact and large widths, with VoiceOver and
Reduced Motion, to verify wrapping, artwork readability, timeout, manual
dismissal, haptics, and the tap target. Preview payloads bypass RPCs, progress
mutation, achievement persistence, dictionary mutation, analytics, and local
push delivery.

The presenter is obtained from the `AppDIContainer` environment; Settings does
not construct or overlay a second milestone singleton. Its ordinary cache and
preference results are typed `ToastPayload` values rendered by
`merianSystemFeedback`. While Settings is the foremost mounted feedback host it
renders the shared milestone stack; dismissing Settings restores the prior host
without repeating haptics/VoiceOver or restarting the active timeout. Settings
places ordinary feedback at the bottom and milestone previews at the top, so the
shared modifier keeps both visible; same-alignment surfaces remain mutually
exclusive to prevent Z-plane collisions. Preview taps use the preview
container's environment-injected route coordinator and cannot enqueue a route in
the production container.
