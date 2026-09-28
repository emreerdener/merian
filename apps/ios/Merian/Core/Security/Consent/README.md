# Consent Ownership

This package owns the value, deterministic policy, focused local-persistence,
and cloud boundaries for Merian's versioned adult, Terms, Google Gemini, and
optional PostHog consent system, plus independent OpenAI consent collection. It
is part of [Core Security](../README.md), not a feature-owned presentation
layer.

## Boundaries

- `Models/ConsentPolicy.swift` owns the exact policy versions, provider names,
  and evidence copy. Changing one is a legal and backend contract change, not a
  presentation-only edit.
- `Models/ConsentModels.swift` owns the existing `ConsentManager.*` receipt,
  event, journal, ledger, restoration, and remote-state value types. Keeping the
  nested names preserves source compatibility. Their Codable fields and legacy
  defaults are durable contracts.
- `Models/ConsentErrors.swift` owns the existing storage and ghost-handoff error
  values without acquiring dependencies.
- `Policies/ConsentAuthorityPolicy.swift` selects all-version provider heads and
  selects Gemini/OpenAI streams independently and decides whether fetched Gemini
  required evidence or PostHog evidence is authoritative.
- `Policies/ConsentLedgerOwnershipPolicy.swift` performs value-only account
  activation and ghost-to-permanent ledger or withdrawal-journal rebinding.
- `Policies/ConsentRetryPolicy.swift` owns bounded retry delays and the
  value-only account/generation/cancellation fence.
- `Policies/ConsentSynchronizationMergePolicy.swift` performs the value-only
  remote-to-ledger upsert and derives required-consent, analytics-authority, and
  reapproval-head results without persistence or SDK effects.
- `Policies/ConsentStateProjectionPolicy.swift` derives the current ledger
  owner, required-consent and cloud-readiness gates, pending-upload count,
  reapproval state, and fail-closed analytics SDK permission. It has no live
  effects.
- `Coordinators/AIProcessingConsentCoordinator.swift` owns optional OpenAI
  Settings choices, account/SDK/cancellation checks and process-local failed
  withdrawal state. It requires verified persistence before publishing a grant,
  permits withdrawal of any-version grant when collection is closed, and
  schedules the existing synchronization owner. Its choice is not an inference
  authorization.
- `Coordinators/ConsentManagerRuntime.swift` is the package composition root. It
  constructs the repository, mutation service, and coordinators, then connects
  their narrow callbacks to the observable facade without resolving live
  singletons.
- `Coordinators/ConsentCloudSessionCoordinator.swift` owns authenticated-session
  adoption, ordinary and Auth-transition account-work authorization, scheduled
  synchronization admission, inference cloud-readiness orchestration, and
  verified Ghost evidence rebinding. Its injected closures preserve the exact
  account lease, session, generation, and cancellation fences without a direct
  Supabase dependency. After suspended inference synchronization it rechecks
  cancellation, lease ownership, and generation before interpreting cloud proof;
  cancellation or identity invalidation never creates a reapproval marker.
- `Coordinators/ConsentRealtimeCoordinator.swift` owns the account-scoped
  subscription identity, listener and retry tasks, generation fences, bounded
  retry state, stale-event rejection, deinitialization-triggered teardown, and
  coalesced exactly-once removal. It retains started removals in a UUID-keyed
  teardown registry until exact completion so Auth replacement can drain the
  physical channel boundary even when removal ignores cancellation. Its injected
  subscription and timing closures keep the lifecycle deterministic and
  Supabase-free.
- `Coordinators/ConsentSynchronizationCoordinator.swift` owns scheduled and
  active synchronization task identity, same-account coalescing, generation
  invalidation, and exact cancellation draining. It retains every outstanding
  task handle through completion, including superseded and previously
  invalidated work, so a later Auth transition cannot lose an older task
  boundary. It also owns unowned-evidence binding, ordered pending-evidence
  pushes, authoritative fetch, and verified merge sequencing. It depends only on
  the injected repository, remote service, and narrow manager callbacks.
- `Coordinators/RequiredConsentRestorationCoordinator.swift` owns the
  restoration state machine, automatic retry budget, UUID-keyed retry-task
  registry, compare-before-clear completion, cancellation snapshot and exact
  drain, manual retry admission, and the account, SDK-session, and
  synchronization-generation and caller-cancellation fences around every
  transition. Canceled handles remain registered through actual completion and
  cannot regain admission if a manual retry reuses the same attempt number.
  Injected timing, synchronization, context, publication, and failure-reporting
  closures keep it deterministic and independent of live Auth, Supabase,
  logging, and observation infrastructure.
- `Repositories/ConsentLedgerRepository.swift` owns decoded local ledger and
  withdrawal-journal state, independent storage uncertainty, verified writes,
  write-ahead withdrawal recovery, and account activation or ghost-to-permanent
  rebinding. It injects the existing raw store and publishes state only after a
  verified durable transition.
- `Services/ConsentRemoteModels.swift` owns the exact PostgREST insert, causal
  RPC, response, and selected-row wire values plus their column projections.
- `Services/ConsentRemoteMapping.swift` owns pure wire-to-ledger mapping,
  immutable-payload comparison and exact timestamp conversion.
- `Services/ConsentRemoteService.swift` routes known AI providers to fixed
  append dependencies, validates causal append results, performs receipt
  read-back recovery, and requires exact immutable receipt and causal-event
  matches before accepting successful or ambiguous read-back evidence. Timestamp
  checks compare decoded instants against the decoded timestamp sent on the
  wire, without a tolerance; reformatting a decoded `Date` can truncate another
  millisecond. A truly empty successful query is absence; a present row that
  cannot map is `invalidResponse`, never absence. Its narrow closure
  dependencies keep these rules deterministic and independently testable.
- `Services/ConsentRemoteService+Live.swift` is the sole direct PostgREST/RPC
  owner. It has two receipt inserts, three causal append RPCs, four ID-scoped
  read-backs, and seven concurrent authoritative reads, including the
  independent all-version OpenAI head.
- `Services/ConsentMutationService.swift` constructs adult, Terms, Gemini,
  OpenAI and PostHog evidence and owns the privacy-sensitive local write
  ordering. Its injected clock, UUID, and app metadata make mutation behavior
  deterministic; it has no network, task, singleton, provider-SDK, or logging
  dependency.
- `Services/ConsentMutationService+Live.swift` is the sole adapter from those
  mutation dependencies to the process clock, UUID generation, and `Bundle.main`
  app metadata.
- `Services/ConsentCloudSessionCoordinator+Live.swift` is the sole adapter from
  the cloud-session coordinator's dependencies to live Supabase Auth,
  account-work leases, account-deletion cleanup state, test execution, and
  bounded failure logging.
- `Services/ConsentRealtimeCoordinator+Live.swift` is the sole direct
  analytics-consent Supabase Realtime owner. It constructs the owner-filtered
  `user_analytics_consent_events` INSERT stream, maps channel status,
  subscribes, and removes the channel selected by the coordinator.

All extracted production owners stay below 600 lines. Models and policies
contain no Supabase, Observation, URLSession, singleton, persistence, task,
logging, or SDK effects; the repository contains no network, SDK, task, or
singleton dependency; and the service cores likewise have no Supabase or
singleton dependency. The coordinator cores likewise contain no direct Supabase,
singleton, logging, or SDK dependency. These owners remain `@MainActor` where
their compatibility-nested model types require the manager's existing isolation.

[`ConsentManager.swift`](../ConsentManager.swift) remains the live observable
facade and public compatibility boundary. It owns mutable observable state,
PostHog application, lifecycle entry points, final synchronization-merge
publication, and the Auth-transition drain. The runtime owns package assembly;
the mutation service owns evidence construction and local write ordering; the
state policy owns derived projections; and the cloud-session coordinator owns
session/lease workflows, Ghost rebinding, and inference admission. The facade
therefore no longer owns mutation construction, derived-state algorithms,
cloud-session orchestration, synchronization or restoration retry task identity,
restoration transitions and retry accounting, pending-push/fetch/merge
mechanics, direct JSON, raw-store, PostgREST, RPC, channel, or listener work.
Its Auth-transition barrier still drains synchronization, restoration, and
Realtime teardown before the session can change.

[`ConsentLedgerStore.swift`](../ConsentLedgerStore.swift) remains the throwing,
fault-injectable raw-byte store for the atomic ledger file, legacy migration,
and independent Keychain analytics-withdrawal journal. The repository, not the
store, owns decoding, structural validation, and publication of live state.

Debug UI-test processes select `InMemoryConsentLedgerStore` through the default
manager initializer. Both ledger bytes and the analytics withdrawal journal are
process-local, so synthetic approvals cannot read or alter the ordinary durable
ledger or survive into a later normal launch. Explicit injected stores and the
normal durable initializer path retain their existing behavior.

## Compatibility

Do not change JSON field names, policy text or versions, provider identifiers,
Keychain keys, Supabase table/RPC contracts, restoration timing, account fences,
or inference admission as part of a structural extraction. A wire or durable
contract change must follow the repository's API/Supabase procedures and update
all producers, consumers, tests, and canonical documentation together.

## Verification

`MerianTests/Core/Security/Consent` mirrors this ownership. The owner-named
manager suites retain behavioral coverage, `ConsentLedgerOwnershipPolicyTests`
covers pure rebinding semantics, `ConsentLedgerRepositoryTests` covers
fail-closed loading, no publication or notification after a failed write,
verified write-ahead recovery, fallback persistence, exact-intent retry, and
ordered account rebinding, and `ConsentRemoteServiceTests` covers exact receipt
and causal-event payload mapping, immutable receipt read-back verification,
malformed-present-row rejection, response validation, ambiguous-write recovery,
independent current/head mapping, and synchronization fencing.
`ConsentRealtimeCoordinatorTests` deterministically cover same-account
idempotency, owner replacement, stale-event fencing, inactive-channel repair,
stream completion and subscription failure retries, bounded backoff, stop-time
retry cancellation, explicit and deinitialization cleanup even when the listener
ignores cancellation, exactly-once channel removal, and the disabled-live
policy. They also prove that coordinator and manager Auth-transition drains stay
open until a cancellation-uncooperative removal completes.
`ConsentSynchronizationMergePolicyTests` cover deterministic evidence upsert,
duplicate current/head handling, authority derivation, and authoritative
absence. `ConsentSynchronizationCoordinatorTests` cover shared same-account work
and single failure reporting, exact cancellation drain for current, superseded,
and previously invalidated tasks—including different-account active-task
replacement—stale-generation merge rejection before persistence, and stable
pending-evidence ordering before authoritative fetch.
`ConsentRestorationCoordinatorTests` cover duplicate-session retry preservation,
bounded failure escalation, manual retry reset, stale-account cancellation and
exact cancellation drain even when sleep ignores cancellation, and
replacement-task retention when an older retry completes. They also reuse an
attempt number after manual retry and prove the canceled timer cannot reenter
the state machine. `ConsentStateProjectionPolicyTests` cover cold-start versus
resolved-session ownership, fail-closed authority, account-qualified pending
counts, and cloud-readiness projection. `ConsentMutationServiceTests` cover
deterministic evidence metadata, privacy-close-before-write behavior, durable
failure ordering, and no-op withdrawal restoration.
`ConsentCloudSessionCoordinatorTests` cover account-work lease adoption and
finishing, post-suspension stale-lease and stale-generation rejection,
first-scan binding of complete unowned evidence through the real
synchronization-service pipeline—pending pushes, receipt read-backs,
authoritative fetch, durable merge, and cloud-ready projection—without admitting
another account's persisted evidence. They also prove that an invalidated
inference generation returns an account-change failure without persisting
reapproval state, and cover Ghost rebinding through the runtime's actual
repository with final-session verification. `ConsentArchitectureTests` freezes
the exact twenty-three-file inventory, declaration and storage-call relocation,
dependency exclusions, runtime composition, mutation/state/cloud owner
boundaries, PostgREST/RPC, Auth-session, app-metadata, and analytics-consent
Realtime confinement to their respective live adapters, `ConsentRemoteWire`
confinement to the four remote-service files, and the 600-line review ceiling
for every extracted owner and the facade.

The product and presentation contract is documented in
[`04-onboarding.md`](../../../../../../docs/features-and-hardware/04-onboarding.md#versioned-consent-evidence).
The manager behavioral contract is documented in
[`09-core-managers.md`](../../../../../../docs/development-guides/09-core-managers.md#consentmanager-required-consent-restoration).
The wire contract is documented in
[`05-api-contracts.md`](../../../../../../docs/backend-and-data/05-api-contracts.md#causal-consent-append-rpc-contract).
Release readiness remains governed separately by
[`production-consent-readiness-2026-08-03.md`](../../../../../../docs/legal/production-consent-readiness-2026-08-03.md).

## Optional OpenAI permission

`ConsentPolicy.openAIConsentCollectionEnabled` is `true`; optional permission
collection remains available independently of beta processing eligibility.
`openAIBetaOptInDeferred` allows an absent OpenAI choice for beta processing but
never creates a grant. `canProcessOpenAI` requires a current account, reliable
storage and no pending or explicit all-version withdrawal; `hasGrantedOpenAI`
continues to report actual current-version evidence. Required onboarding stays
unchanged. `AIProcessingPrivacySection` is available in Settings and in the
saved-scan **Review permission** sheet. Naturebook owns provider assignment;
granting permission neither selects OpenAI nor retries a scan. Account
availability is projected from the same observed/SDK identity and transition
checks used at mutation. Opening the disclosure captures the expected owner;
account replacement, SDK mismatch, transition or cancellation rejects the
action. Existing grants remain withdrawable if collection is later disabled.
Settings displays **On during beta** without claiming a grant and offers a real
withdrawal from that state. The withdrawal action reads **Turn off future OpenAI
processing** and the same action text is recorded; existing receipts are never
rewritten. Successful offline actions persist in the existing ledger and later
synchronize in causal order. Failed writes show an unsaved error; failed
withdrawal closes the local choice for this process and stays retryable, without
claiming durable revocation across restart. The existing separate Keychain
withdrawal journal remains PostHog-only. OpenAI evidence never becomes Gemini
required proof.

`AIProcessingConsentCoordinatorTests` covers explicit collection without an
implicit grant or cloud receipt, independent permissions and parents, closed
collection, historic withdrawal, account/dialog cancellation, persistence
failures and ownership rebinding. A local grant only makes explicit retry
available; the existing inference path synchronizes consent and performs fresh
recipient preflight before dispatch. The remote tests cover fixed OpenAI
dispatch, cross-provider ambiguous-write rejection and owner-scoped head
mapping. See the
[implementation and remaining rollout work](../../../../../../docs/rfcs/identification-provider-openai-consent-2026-09-26.md).
