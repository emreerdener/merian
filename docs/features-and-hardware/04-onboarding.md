# Onboarding Flow

Naturebook gates the main workspace, hardware initialization, ordinary
background/provider sync, and inference behind both completed onboarding and
current legal consent. Consent reconciliation itself remains available while
the required gate is closed. This
document explains the four-step permission flow, versioned consent receipts,
and the three-part required completion gate.

> [!WARNING]
> **Release status:** the internal-testing screen and evidence model are
> implemented. The P1 local-ledger merge and PostHog withdrawal defects are
> closed in source, as are the account-restoration, Realtime, and OAuth
> lifecycle findings. Exact-SHA CI, counsel approval, and operator evidence
> still block production. Treat the
> guarantees below as required invariants until every item in the
> [canonical consent readiness record](../legal/production-consent-readiness-2026-08-03.md)
> is closed. Internal test builds may continue; do not submit the candidate for
> production or enable strict enforcement yet.

---

## Architecture

| File | Role |
|---|---|
| `Steps/Models/OnboardingStep.swift` | Defines the four steps in order |
| `Shell/ViewModels/OnboardingViewModel.swift` | `@Observable @MainActor` — owns `currentStep` and the injected `AppSettings.hasCompletedOnboarding` flag |
| `Core/Security/ConsentManager.swift` | Owns the local append-only consent ledger, current policy versions, account synchronization, and inference gate |
| `Shell/Views/OnboardingView.swift` | Root view, switches content based on `currentStep` |
| `Steps/Welcome`, `Steps/CameraPermission`, `Steps/LocationPermission`, `Steps/Ready` | One self-contained SwiftUI view per onboarding step |
| `Steps/Shared/OnboardingStepWrapper.swift` | Shared step layout and action-button chrome |
| `Permissions/Location/LocationPermissionDelegate.swift` | `CLLocationManagerDelegate` for native location permission priming |

---

## The Steps

```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case camera
    case location
    case ready
}
```

| Step | Component | What happens |
|---|---|---|
| `.welcome` | `WelcomeStepView` | Branding screen — no permission request |
| `.camera` | `CameraPermissionStepView` | Requests `AVCaptureDevice` camera permission |
| `.location` | `LocationPermissionStepView` | Requests `CLLocationManager` when-in-use authorization via `LocationPermissionDelegate` |
| `.ready` | `ReadyStepView` | Names Google Gemini as the recipient of observation data for AI-powered identification and presents three initially-off, left-aligned switches in internal-testing order: optional usage/diagnostics, required 18+ self-attestation, and required Terms/data-sharing permission with an inline Terms link. **Start scanning** requires the two required switches only. |

The first three step views use `OnboardingStepWrapper` for consistent layout
and action chrome. The ready step uses a dedicated layout so the disclosure,
linked acceptance statement, switches, and disabled state remain one clear
surface.

---

## State Transitions

```swift
func advanceStep() {
    if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
        currentStep = next
    }
}

func completeOnboarding(analyticsEnabled: Bool) {
    consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
        analyticsEnabled: analyticsEnabled
    ) // durable local write first
    AppTelemetry.trackOnboardingCompleted()  // fires before flag write — activation funnel signal
    hasCompletedOnboarding = true            // writes through AppSettings/UserDefaults("hasCompletedOnboarding")
}
```

`completeOnboarding(analyticsEnabled:)` is called on the `.ready` step. It first
appends the current adult-confirmation receipt, Terms receipt, Gemini grant,
and optional analytics grant to the append-only local ledger, then records the
activation event when analytics is allowed and writes the onboarding flag. The
local legal action is therefore durable before the workspace can open. The
full lifecycle requires both `hasCompletedOnboarding` and
`ConsentManager.hasCurrentRequiredConsent`:

- `AppLifecycleManager.handleActivePhase()` requires both gates before it
  initializes active hardware work or drains queued submissions.
- `AppLifecycleManager.handleInactivePhase()` still uses completed onboarding
  to stop an existing camera session during system interruptions.
- `AppLifecycleManager.handleBackgroundPhase()` always records the background
  time used by session-timeout recovery; it does not submit provider work.

This means during onboarding or whenever current required consent evidence is
absent: no camera session starts, no inference request is built, and no offline
submission drain runs.

---

## The `hasCompletedOnboarding` Gate

`OnboardingViewModel` exposes `hasCompletedOnboarding` as a computed property backed by its injected `AppSettings` boundary:

```swift
var hasCompletedOnboarding: Bool {
    get { appSettings.hasCompletedOnboarding }
    set { appSettings.hasCompletedOnboarding = newValue }
}
```

`MerianApp.swift` reads this flag together with the observable consent manager
to choose `OnboardingView` or `CaptureWorkspaceView`. Production construction
uses the shared managers; tests inject isolated settings and consent ledgers.
An older install with completed onboarding but no current receipt enters
directly at `.ready`, without repeating the camera and location primers. A
material adult policy, Terms, or Gemini disclosure change increments its policy
version and routes every account without that version back to the same step.

## Versioned Consent Evidence

`ConsentPolicy` currently pins adult policy and Terms versions `2026-08-03`,
Gemini disclosure version `2026-08-04.1`, PostHog disclosure version
`2026-08-04`, and providers `google_gemini` and `posthog`. The exact displayed
statement is stored with each action, along with a client-generated UUID,
device action time, platform, app version, and app build. Adult eligibility is
self-attested on every supported iOS version; Naturebook does not collect a
birth date or exact age.

`ConsentManager` writes an append-only JSON ledger to
`UserDefaultsKeys.legalConsentLedger` immediately, including while the first
anonymous Supabase session is still being created. It later binds unowned
records to that account and synchronizes them to:

- `public.user_adult_eligibility_receipts`;
- `public.user_terms_acceptance_receipts`;
- `public.user_ai_consent_events`, whose `granted` and `revoked` rows form an
  immutable permission history; and
- `public.user_analytics_consent_events`, whose latest `granted` or `revoked`
  row is the account-wide PostHog choice. Absence of a grant means analytics is
  off.

All four tables use owner-only RLS and explicit authenticated `SELECT` and
column-level `INSERT` grants. Clients have no `UPDATE` or `DELETE` path and
cannot supply `recorded_at`; the latest server-recorded provider event
determines cloud permission. Client-generated IDs make retries idempotent.
Database ghost-to-signed-in merge policies reparent every synchronized
immutable row without coalescing evidence. After server completion, iOS now
rebinds the complete local adult, Terms, Gemini, and analytics ledger to the
permanent UUID in one verified write. Ghost-synchronized records follow the
server mapping; every other ghost-owned record remains pending for the
permanent account. A durable handoff suppresses analytics across restart until
pending actions are pushed, authoritative state is refetched, and throwing
verified queue removal succeeds. Analytics INSERT events are in the owner-scoped
Realtime publication. The client tracks the channel owner and confirmed
subscriber separately from auth-session assignment, fences stale listeners by
generation, and retries failed subscriptions for the same account with bounded
backoff. Auth observation and foreground/session adoption both ensure the
owner-scoped channel, while foreground refetch remains the recovery path for a
missed event. When returning to an account, synchronization activates that
account's local ledger and pushes its pending evidence before refetching remote
state, so an offline revocation cannot be hidden by the previously active
account. Analytics stays closed throughout that restoration and is applied only
after the authoritative merge succeeds.

Before any identification provider request is constructed or dispatched,
`MerianNetworkClient` calls `ensureCloudConsentForInference()`. That method
requires the current local adult, Terms, and Gemini versions, creates or
resolves the Supabase session, and verifies that all required evidence reached
the active account. The database repeats the check inside both service-only
`reserve_ai_quota` overloads immediately
before provider admission, so an outdated or modified client cannot bypass it.
Missing or revoked evidence fails with `403 ai_consent_required` and no Gemini
dispatch.

The first row in Settings → Resources is the optional Analytics & diagnostics
control. Settings intentionally provides no Gemini processing opt-out:
Naturebook has no non-AI identification mode, so a user who does not permit the
required processing cannot use the scanner. Historical or remote AI revocation
events remain supported and close the local workspace gate immediately. The
required analytics-withdrawal invariant is immediate facade shutdown, identity
clearing, SDK opt-out/closure, account-wide synchronization, no
withdrawal-triggered PostHog request, and no change to core functionality. The
configured-host transport gate closes before `reset()` and cancels PostHog
3.69.0's reset-time feature-flag reload locally while preserving
`reset → optOut → close`; see completed `CONSENT-001` in the readiness record.
Before OAuth installs a session that can replace the current account, the app
synchronously suppresses analytics and stops consent Realtime. It reconciles
the SDK's actual session on success or failure, and only the newest overlapping
transition may reopen analytics for a currently granted account.

---

## Permission Philosophy

Each permission step presents the rationale for the request before triggering the system dialog. This "permission priming" pattern maximizes grant rates by ensuring users understand the value before iOS shows the system alert.

- **Camera**: Required for visual capture. If denied, the camera shutter is
  unavailable; non-camera modes remain the alternative.
- **Location**: Optional. It improves identification context and scientific
  record quality; **Skip for now** continues without an OS grant.

> [!NOTE]
> **Progressive Disclosure**: Push Notification and Photo Library permissions
> are deliberately omitted from the initial onboarding flow to reduce drop-off.
> Notifications are conditionally requested via a half-sheet after the first
> successful scan resolve, or if the user actively flips the
> Discovery/Achievement toggles in Settings. Enabling **Save to camera roll**
> presents the add-only Photos explainer for automatic photo and video writes;
> gallery import separately requests read/write access. Explicitly Downloading
> media also uses add-only access but does not require the automatic setting to
> be enabled. Receiving a file explicitly shared from Photos is a document
> import and adds no Photo Library permission request. See
> [Camera Roll and Captured-Media Export](./27-camera-roll-media-export.md).

---

## Re-entering from a Deep Link

Most transient navigation events cannot present Capture sheets until onboarding
and current required consent are complete. Photos document imports are the deliberate exception: the file is
copied into `ExternalImageImportStore` before the event is published, so an
unfinished onboarding flow may ignore the transient event without losing the
photo. `CaptureWorkspaceView` checks the durable inbox after onboarding and
current required consent, then routes the item through the normal quota, crop,
confirmation, and submission flow.
