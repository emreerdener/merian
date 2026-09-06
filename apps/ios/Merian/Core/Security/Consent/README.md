# Consent Ownership

This package owns the value, deterministic policy, focused local-persistence,
and cloud boundaries for Merian's versioned adult, Terms, Google Gemini, and
optional PostHog consent system. It is part of [Core Security](../README.md),
not a feature-owned presentation layer.

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
  decides whether fetched Gemini or PostHog evidence is authoritative.
- `Policies/ConsentLedgerOwnershipPolicy.swift` performs value-only account
  activation and ghost-to-permanent ledger or withdrawal-journal rebinding.
- `Policies/ConsentRetryPolicy.swift` owns bounded retry delays and the
  value-only account/generation/cancellation fence.
- `Policies/ConsentSynchronizationMergePolicy.swift` performs the value-only
  remote-to-ledger upsert and derives required-consent, analytics-authority, and
  reapproval-head results without persistence or SDK effects.
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
- `Services/ConsentRemoteService.swift` maps between wire and durable consent
  values, validates causal append results, performs receipt read-back recovery,
  and requires exact immutable receipt and causal-event matches before accepting
  successful or ambiguous read-back evidence. A truly empty successful query is
  absence; a present row that cannot map is `invalidResponse`, never absence.
  Its narrow closure dependencies keep these rules deterministic and
  independently testable.
- `Services/ConsentRemoteService+Live.swift` is the sole direct PostgREST/RPC
  owner. It preserves the two receipt inserts, two causal append RPCs, four
  ID-scoped read-backs, and six concurrent authoritative reads.
- `Services/ConsentRealtimeCoordinator+Live.swift` is the sole direct
  analytics-consent Supabase Realtime owner. It constructs the owner-filtered
  `user_analytics_consent_events` INSERT stream, maps channel status,
  subscribes, and removes the channel selected by the coordinator.

All extracted production owners stay below 600 lines. Models and policies
contain no Supabase, Observation, URLSession, singleton, persistence, task,
logging, or SDK effects; the repository contains no network, SDK, task, or
singleton dependency; and the service core likewise has no Supabase or singleton
dependency. The coordinators likewise contain no direct Supabase, singleton,
logging, or SDK dependency. These owners remain `@MainActor` where their
compatibility-nested model types require the manager's existing isolation.

[`ConsentManager.swift`](../ConsentManager.swift) remains the live observable
facade and owns consent mutation, session adoption, the observable restoration
projection, derived admission state, PostHog application, lifecycle triggers,
and the decision to request each durable transition. It assembles the
repository, synchronization, restoration, remote-service, and Realtime owners
and remains the account/session authority that starts repair or stops work
before account replacement. Its Auth-transition barrier drains synchronization,
restoration, and Realtime teardown before the session can change. It no longer
owns synchronization or restoration retry task identity, restoration transitions
and retry accounting, pending-push/fetch/merge mechanics, direct JSON,
raw-store, PostgREST, RPC, channel, or listener work.

[`ConsentLedgerStore.swift`](../ConsentLedgerStore.swift) remains the throwing,
fault-injectable raw-byte store for the atomic ledger file, legacy migration,
and independent Keychain analytics-withdrawal journal. The repository, not the
store, owns decoding, structural validation, and publication of live state.

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
the state machine. `ConsentArchitectureTests` freezes the fifteen-file
inventory, declaration and storage-call relocation, dependency exclusions,
sole-facade repository/service/coordinator consumption, PostgREST/RPC and
analytics-consent Realtime confinement to their respective live adapters,
`ConsentRemoteWire` confinement to the three remote-service files,
coordinator/merge-policy wiring and state ownership, and the 600-line review
ceiling.

The product and presentation contract is documented in
[`04-onboarding.md`](../../../../../../docs/features-and-hardware/04-onboarding.md#versioned-consent-evidence).
The manager behavioral contract is documented in
[`09-core-managers.md`](../../../../../../docs/development-guides/09-core-managers.md#consentmanager-required-consent-restoration).
The wire contract is documented in
[`05-api-contracts.md`](../../../../../../docs/backend-and-data/05-api-contracts.md#causal-consent-append-rpc-contract).
Release readiness remains governed separately by
[`production-consent-readiness-2026-08-03.md`](../../../../../../docs/legal/production-consent-readiness-2026-08-03.md).
