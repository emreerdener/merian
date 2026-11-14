# Gemini generation 3 compatibility and activation

This contract separates software compatibility, technical provider integration,
model quality, and production activation. Implementation and green CI authorize
none of the production mutations below. Comparative biological accuracy,
moderation effectiveness, confidence calibration, and chat quality remain
**unmeasured**. Integration smokes establish technical compatibility only.

## Release sequence and authorization

1. Authorize and deploy additive compatibility while ordinary routing remains
   unchanged. The cutoff is independently deployable and must reach production
   before November 30, 2026 at 00:00 UTC, even if activation is delayed.
2. Archive the compatible I7/V3 app with Xcode Organizer, following all existing
   signing, consent, exact-source, CI, and distribution gates. Verify the exact
   version/build is available to the intended TestFlight group. The app supports
   legacy assignments before activation. An upload or processing build alone is
   insufficient.
3. Prepare and review an activation release manifest using
   `services/supabase/scripts/prepare_gemini_release.ts`. This is read-only. The
   input supplies the app version/build/source fingerprint, intended TestFlight
   group and availability-check time, exact backend SHA and project reference,
   finite release window, authorization reference, and explicit spending cap.
   The prepared record freezes the current complete assignment set, generated
   function identities, profiles, exact identity aliases, tariff version, and
   synthetic smoke case digests/reservations. Review its full scope and cost.
4. Explicitly authorize the backend activation release for that target and SHA,
   including bounded paid smokes and protective suspension. Supply the exact
   JSON as `gemini_activation_release` to the backend workflow's manual
   dispatch. Empty input means compatibility deployment only. The prerequisite
   check runs before backend mutations. Existing production concurrency, source
   controls, release holds, migrations, ACL audits, function deployment, and
   mandatory technical checks remain required.
5. The release deploys every required function, checks each live bundle
   identity, completes the authorized smoke cases, rechecks identities and the
   frozen assignment set, and atomically installs the new revision. It then
   verifies routing, protocol selection, function identities, and unchanged
   feature holds. Completion is reported only after these agree.

One explicit release authorization covers deployment and its final activation;
there is no second model-toggle request. TestFlight availability is a manually
checked prerequisite, never a trigger. There is no TestFlight polling,
availability-attestation service, or cross-system release orchestrator.
Compatibility migrations, ordinary workflow pushes, and CI cannot activate the
new models. Independent feature holds stay unchanged.

The release record retains app build/source identity, backend SHA, target,
configuration digest, expected previous routing revision, authorization,
deployment evidence, smoke ownership and outcomes, and activation/verification
records. Registration and exact retries preserve the original record. Stale,
changed, partially deployed, superseded, or suspended releases fail closed. A
retry never represents a superseded revision as the current active release.

## Profiles and presentation

`_shared/ai/geminiProfiles.ts` owns the versioned candidate settings. They
retain `generateContent` and `@google/genai@2.24.0`. New profiles use an
explicit thinking level and omit sampling parameters, numeric thinking budgets,
seeds, and `candidateCount`. Both product tiers share the identification model
and settings; quotas and entitlements are unchanged.

| Operation                     | Candidate model / thinking |    Old token ceiling | New ceiling |
| ----------------------------- | -------------------------- | -------------------: | ----------: |
| Multimodal identification     | 3.8 Flash / Medium         |                 8192 |        8192 |
| Legacy vision identification  | 3.8 Flash / Medium         | Free 4096 / Pro 8192 |        8192 |
| Description identification    | 3.8 Flash / Medium         | Free 2048 / Pro 4096 |        8192 |
| Legacy audio identification   | 3.8 Flash / Medium         |                 2048 |        8192 |
| Ordinary/protected Field Chat | 3.5 Flash-Lite / Low       |                  700 |        4096 |
| Field-note summaries          | 3.5 Flash-Lite / Minimal   |                  450 |        1024 |
| Suggested questions           | 3.5 Flash-Lite / Minimal   |                  220 |        1024 |
| Species overview              | 3.5 Flash-Lite / Minimal   |                 1500 |        2048 |
| Lookalikes                    | 3.5 Flash-Lite / Minimal   |                  300 |        1024 |
| Group tags                    | 3.5 Flash-Lite / Minimal   |                  100 |         512 |
| Discovery search              | 3.5 Flash-Lite / Minimal   |                  700 |        2048 |
| Publication-photo moderation  | 3.5 Flash-Lite / Minimal   |                  512 |        2048 |
| Audio moderation/transcript   | 3.5 Flash-Lite / Minimal   |                 4096 |        4096 |

Identification receives a common Medium configuration. Helper increases allow
operation-specific reasoning headroom. Audio transcription capacity is
preserved; reducing it requires a separate tuning experiment. Visible-answer,
transcript, array, schema, response-byte, and safety limits remain independent
of provider ceilings. Prompts retain biological requirements, grounding, and
application schemas; any necessary behavioral prompt changes require their own
versions.

New verified V3 identification results use provisional display bands Strong
≥0.85 and Possible ≥0.65, with the existing 0.99 diagnostic-candidate behavior.
Historical presentation stays unchanged. These display bands do not grant
calibration, rewards, automatic verification, or qualified-metric eligibility.

## Protocol and lifecycle matrix

Entitlement protocol 3, media schema versions, and history consent/capability
versions are preserved. Accept exact tuples; I7 is capability, never caller
model authority.

| Request family      | Compatible old tuple    | New tuple               |
| ------------------- | ----------------------- | ----------------------- |
| Fresh Identify      | I6                      | I7                      |
| Description history | Schema 1 / E3 / I6 / H7 | Schema 1 / E3 / I7 / H7 |
| Photo reanalysis    | Schema 2 / E3 / I6 / H8 | Schema 2 / E3 / I7 / H8 |
| Audio reanalysis    | Schema 3 / E3 / I6 / H9 | Schema 3 / E3 / I7 / H9 |
| Video reanalysis    | Schema 4 / E3 / I6 / H9 | Schema 4 / E3 / I7 / H9 |

| Boundary                        | Contract                                                                                                   |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Compatibility deployment        | Existing routing remains selected; I6 and I7 work                                                          |
| Activation/fresh admission      | New identification requires I7 before quota acquisition                                                    |
| Unadmitted saved legacy request | Retain bytes; a successor requires explicit user action and a new identity                                 |
| Already admitted request        | Keep original assignment, tuple, digests, and canonical bytes, including I7 work admitted to legacy models |
| Recovery                        | Original evidence and assignment remain authoritative                                                      |
| Completed replay                | Return stored result without provider invocation or substitution                                           |
| Ordinary reads                  | I7 accepts V1/V2/V3; older readers retain exact supported contracts                                        |
| History pages                   | Reader 13 inherits every reader-11 snapshot plus V3; reader 12 remains denied                              |

Reader 12 remains the separate video-source/evidence capability. Reader 13
grants no mutation, execution, or additional consent authority. Frozen
retained-source catalogs and existing request/result bytes must never be
rewritten to simulate a new assignment. Initial-analysis and publication feature
holds remain independent of model routing and retain their existing
source-archive and readiness gates. The retained V1 source archive continues to
resolve its original committed Git blobs. A future initial-analysis rollout must
register a separately reviewed, content-addressed source catalog built from a
committed I7/V3 implementation before lifting its feature hold. Do not relabel
the old catalog or manufacture a revision from an uncommitted checkout; model
activation grants no initial-analysis installation authority.

Failed or expired quota reservations cannot be rebound to a changed model or
policy under their existing request identity. Such retries fail closed and
retain their admitted evidence; a successor requires a new user-created request.
Publication moderation verifies the entire media cohort before admission, then
builds the selected request from cached verified bytes using the admitted model
and its repository-owned transport guard before proof persistence and dispatch.

## Responses, identity, and accounting

The shared bounded normalizer supports SDK and direct REST envelopes, at most 32
parts, and existing byte limits. It accepts typed `thought` and opaque
`thoughtSignature` metadata, discards thought-marked text, and concatenates
application text in order. Neither thought text nor signatures are persisted or
exposed. Calls remain stateless without automatic continuation. Tool calls and
media output are rejected; application JSON, safety, finish status, required
fields, unknown keys, and value bounds retain strict validation.

Requested model is immutable admission evidence. Existing `model` fields keep
that meaning. Returned model is the bounded provider `modelVersion`, separately
stored in an invocation receipt. V3 completed results bind requested settings to
verified returned identity. Pre-dispatch V3 can carry an unknown returned
identity; it is not a completed result. Durable result writers require the
matching reservation/attempt receipt for V3.

Aliases are versioned exact allowlists, initially exact configured IDs only.
Missing, malformed, or mismatched returned identity rejects the result while
retaining independently valid usage. A 2.5 request returning 3.x is an identity
mismatch, never migration authority. Unknown suffixes are not accepted by family
matching.

Prompt, candidate, thinking, cached, tool, and total counters are separate.
Cache is a subset of prompt tokens. Nonzero thinking is valid. Partial evidence
remains partial; missing/invalid counters are not invented as zero. Identity,
finish status, and valid counters are extracted before semantic answer
rejection. Unparseable/oversized responses and unknown pricing preserve
unresolved liability.

Provider premises were checked on November 14, 2026 against Google's
[3.8 migration guide](https://aistudio.google.com/docs/whats-new-gemini-3.8),
[standard pricing](https://aistudio.google.com/docs/pricing), and
[thinking contract](https://aistudio.google.com/docs/thinking).

Effective-dated returned-model pricing includes the January 2027 tariff change.
Historical ledger rows are not repriced. Receipt settlement and existing
admission quota accounting remain distinct. Support-operation, background-job,
and smoke usage events are inserted by their receipt transaction, using the
returned identity for pricing while `model` keeps the requested identity. The
old best-effort path and chat-message trigger must not insert a second estimate.
A valid provider envelope is not application acceptance. Receipt-first usage
rows keep `outcome=unknown` and `provider_response_only=true` until there is
known acceptance at insertion; the append-only ledger is never rewritten or
repriced. Strict application decoding records a separate, immutable
`application_outcome` on the receipt using its original ownership token. A
semantic rejection therefore retains usage and returned identity without
claiming success. Ordinary and protected chat share the same closed answer
decoder; notes and suggestions reject missing, unknown, or mistyped fields
before safety filtering. Shared overview, lookalike, and group-tag responses
validate their native response schemas, enums, and value limits before the
adapter records application success. Defaults and truncation cannot manufacture
a successful provider answer. Missing outcome acknowledgement stays unknown; it
cannot justify another invocation. Species execution completion is recorded
separately only after downstream persistence succeeds. Reconciliation reads
these durable outcomes alongside the original ledger rather than treating an
unknown outcome as either success or zero liability.

These content-free receipts outlive quota/job cleanup; opaque historical IDs
provide no dispatch or cancellation authority after their owner is gone.
`internal.gemini_unresolved_liabilities` exposes content-free unresolved quota,
background-job, and smoke execution evidence to privileged reconciliation. No
dashboard or cleanup may equate missing responses, expired leases, or zero known
cost with zero provider liability.

## Bounded integration smokes

`gemini-release-smoke` is service authenticated and accepts only `release_id`
and `case_id`. It resolves inputs and profiles from the closed server catalog
and checks the release's exact configuration/function identity. There is no
public model, prompt, endpoint, media, or settings override. Synthetic inputs
exercise the same deployed request builders, adapters, normalization, identity
checks, and receipt accounting used by production while ordinary routing is
still legacy. No independently held workflow is enabled.

The authorization freezes exact cases, one call per case, conservative per-case
reservations, a hard cumulative cap, stop rules, and a finite window. Missing
spending authorization prevents the activation release. Ownership and dispatch
intent persist before the provider call; response facts persist before outcome.
Concurrent claims yield one execution owner. Exact retries read existing
evidence. A crash after possible dispatch and before persisted response is
uncertain, may not run again automatically, and cannot count as passing
evidence. Lease expiry never proves non-invocation. Failed, uncertain,
unresolved, or over-reservation cases stop the release.

## Suspension, cutoff, and recovery

Every transport owner rechecks its original assignment revision, suspension,
cutoff, and current ownership immediately before invocation. The existing
product permit is not a transport witness. A worker paused after obtaining that
permit and resumed after suspension must stop without a provider call.

If post-activation verification fails, the authorized protective response
suspends fresh admission and uninvoked dispatch for the affected revision
atomically. It cannot suspend a newer revision. Reads, completed replay,
persisted-outcome completion, settlement, and existing-evidence recovery remain
available. No implicit model rollback or provider replacement occurs. The
release stays incomplete/unhealthy until an authorized repair or resumption.

Only a still-owning live worker's explicit non-invocation evidence can settle an
unused provider liability. A recorded permit alone proves neither invocation nor
non-invocation. Existing feature owners retain their cancellation and eligible
reserved-hold release transactions; the new receipt path does not bypass them or
refund already consumed admission counters. Ambiguity around transport remains
potentially in flight. Never automatically reinvoke, replace, refund, or relabel
such work. Suspension cannot recall an in-flight request.

Background species work with a received response but unsuccessful downstream
persistence remains unavailable for automatic reclaim. Both current and legacy
claim routines skip it, and the binding trigger rejects forced replacement.
Known completion atomically records a completion marker, allowing a subsequent
scheduled refresh to own a new attempt. Already-running legacy jobs at
compatibility installation are potentially in flight, with no invented dispatch
timestamp; they cannot be relabelled as non-invoked or automatically retried.
Recovery requires retained-result completion or explicit reconciliation.

Activation ends new legacy admissions. Existing 2.5 assignments may drain only
before **2026-11-30T00:00:00Z**. Enforce that cutoff at authorization and the
final transport boundary, including resumed work. At cutoff, remaining legacy
admission and dispatch close independently of activation. If candidate routing
has not activated, affected fresh work becomes unavailable. Persisted
outcomes/drafts can finish without another provider call; provably uninvoked
work uses its owning settlement path. The deadline never authorizes an
unvalidated replacement, and old model IDs cannot be assumed to restore old
behavior after provider rerouting.

## Validation and follow-up

Run database catalogs against a freshly reset disposable database. Run the
database-backed function suite separately; its integration fixtures must not
overlap catalog transactions or become the catalog suite's starting state.

Run affected contract generation, immutable-byte/recovery tests,
reasoning-response fixtures, response-identity/accounting tests, SQL
catalog/migration/privileged routine gates, recursive Deno checks,
function/tooling suites, focused native tests, and the repository local iOS
build. Release tests must cover exact retry, wrong
target/SHA/configuration/function identity, assignment drift, concurrency,
uncertain smoke execution, suspension of a paused worker, cutoff boundaries,
January pricing, quota preservation, and replay without invocation.

Paid model-quality evaluation is separate follow-up: matched Low-versus-Minimal
chat comparisons with predeclared quality, latency, truncation, and cost
criteria; modality-specific identification assessment; and separate moderation
false-allow and false-reject criteria. Passing technical smokes does not resolve
those uncertainties.
