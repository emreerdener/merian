# OpenAI photo integration

Date: 27 September 2026\
Status: dormant photo routing, native capability, safety, V2 metadata,
saved-result usage integration and result-reader checks implemented; production
remains Gemini.

## Decision

Advance the existing OpenAI baseline toward an app-controlled **still-photo**
assignment. The
[completed matched comparison](./identification-gemini-openai-matched-results-2026-09-27.md)
supports this development decision: both providers agreed with five provisional
biological photo references and one mineral control; median provider time was
7.10 seconds for OpenAI and 15.81 seconds for Gemini. These are six reused
development examples, not held-out qualification or an end-to-end app benchmark.

Keep description-only requests on Gemini for the first rollout. Both providers
over-specified the mushroom description. Audio, combined media, compatibility
routes, enrichment and Field Chat retain Gemini. Ordered video snapshots are
also image inputs and are a planned OpenAI visual route, described below; their
current assignment remains Gemini pending separate qualification. A photo's
optional note stays part of the complete observation; never drop it to qualify
for a photo lane. The completed no-note benchmarks remain valid.

The app owns assignments. End-user permission can allow or block disclosure to
the app-selected processor; it is neither a preference nor an instruction to
switch providers. No automatic cross-provider retry is proposed.

## Completed foundations and this slice

The September 26 implementation already supplies complete-input classification,
database-owned assignment, recipient preflight, independent consent evidence,
client compatibility, immutable result provenance, neutral treatment of unknown
scores, and metric restrictions in shared/public consumers. Preserve those
owners; do not rebuild them as a new routing system.

The first completed slice added an independent result-policy boundary in
`_shared/ai/multimodalResultPolicy.ts`. The primary handler prepares it from the
admitted execution snapshot **before quota commitment or invocation**. It
retains the existing Gemini primary task, model, binding, prompt/schema,
confidence and safety combinations; the connection slice adds the exact dormant
photo profile. A missing or unsupported policy refunds unused quota through the
existing retryable failure path. Registering an adapter alone cannot authorize
its result handling.

Normalization now receives an explicit diagnostic threshold from that policy,
instead of deriving one from the account tier. OpenAI evaluation continues to
use an explicitly unqualified policy that retains alternatives even at maximum
raw confidence. This preserves current benchmark semantics and grants no
production authority.

Only an outcome matching the prepared Gemini result profile exposes native
finish/rating signals to the existing media moderation path. Gemini's absent
ratings retain their historical behavior. The dormant OpenAI photo path instead
requires its own complete allowed native moderation disposition; absence of
Gemini ratings cannot approve its media. The evaluation snapshot is rejected
before provider spend or promotion, including when injected into the actual
handler in tests.

That first slice changed the primary result-processing boundary without changing
database assignments, public payloads, consent collection, credential stores,
model requests, prompts, generation settings or existing stored results. The
connection slice below adds its separate capability contract. The runtime
fingerprint is regenerated for each implementation; the completed comparison
retains its original source and hash.

## Provider infrastructure closeout — 27 September 2026

[PR 87](https://github.com/emreerdener/merian/pull/87) merged at
`2f733e83ae24fa90d8a222cf6635905fda265720` and
[production deployment 1819](https://github.com/emreerdener/merian/actions/runs/36363524196)
passed candidate validation, deployment and backend smoke checks. The deployment
log confirms the existing GitHub Production `NATUREBOOK_OPENAI_API_KEY` was
synchronized to Supabase project `qlarqavoqhkuwzmevrmf` and its stored digest
was verified. This closes the current infrastructure milestone; the optional
secret synchronization was not skipped.

OpenAI dispatch remains source-disabled and assignments remain Gemini.
Permission collection, released-reader verification, held-out qualification and
activation below remain deferred, separate work. The
[new optimization plan](./identification-optimization-preserving-results-2026-09-27.md)
can now proceed while preserving the current explanation format. It does not
require repeating the closed concise-explanation experiment.

## Remaining slices

1. **Finish activation prerequisites.** The dormant connection described below
   is implemented, including the result-reader boundary below. Release and
   verify the compatible reader before activation. The September 27 accounting
   follow-up implements primary multimodal failed/uncertain coverage and native
   pricing; see the
   [current accounting contract](../backend-and-data/04-database-schema.md#primary-identification-attempt-accounting).
   Source implementation alone does not establish deployed readiness. The
   closeout above records successful deployment and verified GitHub-to-Supabase
   synchronization of the existing Naturebook OpenAI key. Permission collection
   is deferred at the owner's request and remains an activation prerequisite.
   The source gate remains false and all assignments remain Gemini. A secret,
   consent grant or catalog edit cannot enable dispatch.

2. **Qualification and controlled activation.** Freeze the precise supported
   photo envelope, quality/safety/failure/latency/cost acceptance limits and a
   separately budgeted held-out comparison. Existing exploratory cases remain
   development evidence. Validate the released client and full persistence path,
   including optional-note preservation, refusal, uncertain execution,
   account/permission changes and saved-result recovery. Then request the
   concrete operation and target for activation through the existing exact-SHA
   release process. There is currently no reviewed percentage-routing control;
   do not invent one through an environment variable.

The
[provider onboarding contract](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md)
and
[Supabase deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md)
own the cross-surface and release requirements. Wider iOS distribution
separately requires archive/upload and genuine released-build install-over
verification. Development-build use on the owner's phone does not complete those
checks.

## Photo safety and metadata slice

The disabled `openai_photo_v1` adapter now requests pinned inline input/output
moderation in the same Responses request. It reuses the measured model, prompt,
low reasoning effort and high image detail. Completed benchmark profiles and
their request hashes stay frozen. Still photos retain all optional observation
text; unsupported audio, description-only and sampled-video observations fail
before dispatch.

The
[canonical safety policy](../development-guides/10-safety-and-moderation.md#dormant-openai-photo-policy)
defines allowed, rejected and unavailable decisions. Rejection discards the
draft, including malformed generated JSON; unavailable moderation never produces
an approvable draft. No native result is translated into invented Gemini ratings
or an account strike. Tests use synthetic responses and no provider credential.
No separate moderation request is added; actual latency, billing and safety
effectiveness still require qualification of this precise binding.

Version 2 provenance records native `max_output_tokens`, `reasoning_effort` and
`image_detail`. Version 1 retains its exact stored shape. The executable
contract owns the version dispatch, strict key sets and generated Swift
decoders; the forward database migration extends only the bounded pure
validator. Immutable scan/job copies, recovery authority and privileges are
unchanged. Existing V52 opaque JSON storage preserves either version without a
SwiftData migration.

Provenance describes configuration; it does not approve a runtime profile or
media promotion. Bounded future configuration identifiers within the existing
scan operation and variant vocabulary remain readable and unqualified. Exact
production-profile matching remains the responsibility of admission and result
policy. V2 can never receive Gemini confidence bands or score-based rewards.
Entitlement protocol remains 3. The connection slice separately advertises
identification capability 4, while permission collection and all server
assignments remain unchanged. This capability proves the requesting client can
read V2; it does not solve history compatibility on another, older device.

## Dormant connection slice

Migration `20260927175708_prepare_openai_photo_routing.sql` separates the quota
policy's `model` from optional `provider_model` in the existing per-input
binding and immutable attempt. NULL means the saved Gemini quota model; OpenAI
requires the exact photo/GPT/permission tuple and identification capability 4.
No catalog, quota policy, rollout or consent row changes. Other input profiles
retain Gemini.

New six-argument preflight and eleven-argument reservation overloads carry
`p_identification_protocol` independently of `p_client_protocol`. Native request
preparation and both transports retain capability 4 through retries in
`X-Merian-Identification-Protocol`; the entitlement header stays 3. Legacy ABIs
remain available and deny fresh alternate-provider assignments. Internal retries
must recover capability from the original owner's exact saved attempt, never a
worker header. Recipient expectation can only reject assignment drift.

The registry resolves the exact dormant photo binding. `production.ts` has a
constant-false source gate before credential lookup and invocation; the handler
refunds that unused lease. Tests inject a synthetic execution through the
existing seam. Allowed native moderation reaches the existing media promotion
and durable scan path, while refusal/unavailable/uncertain outcomes retain
existing settlement and recovery. No Gemini safety scores or account strikes are
synthesized.

Saved scans preserve reported cached tokens for both providers. OpenAI
additionally retains native output and cache-write counts; candidate tokens
exclude reasoning because Responses output already includes it. The existing
scan trigger writes one ledger entry, labels `openai_responses_tokens_v1`, and
retains unknown values as NULL. An OpenAI result with entirely missing usage
still counts as an unpriced event. No OpenAI tariff or second success writer is
introduced. Failed/uncertain attempts that never save a scan still have the
previously documented accounting gap; closing that gap and qualifying pricing
are activation requirements.

**The connection slice identified a history blocker.** Older protocol-3 apps
read `identification_provenance` directly from PostgREST and cannot decode V2.
Gating a new identification request does not protect another older device
reading that account's history. Resolve this with a reviewed reader
rollout/history projection before emitting V2 results. Do not omit provenance
and thereby restore legacy Gemini confidence meanings. No SwiftData schema
migration is required. The following slice implements the read boundary; its
release remains an activation prerequisite.

## Result-reader compatibility slice

The new migration retains the existing owner/public visibility predicates and
adds a current-reader check for visible V2 rows. Null/V1 reads continue
unchanged. A visible V2 row without exact identification protocol 4 fails the
entire query with `426 client_update_required`, even if the query omits
provenance. It never silently removes observations from a mixed page or
reinterprets their scores. Private/non-live/tombstoned rows that were already
invisible remain invisible without a capability error. Service projections keep
their existing access.

The native SDK factory shares the dispatch capability constant and sends it on
history, single-scan and metadata-update requests. Actual SDK requests are
covered using an isolated URLSession transport. All four Edge endpoints also
check the current reader for stored or reconstructed completed results,
including concurrent completion and ingestion recovery. The primary handler
checks fresh V2 emission as well. Only the existing service-authenticated replay
worker bypasses client decoding; its original admission proof remains required
to do provider work.

This boundary deliberately requires older apps to update when they encounter a
newer result. Already installed binaries may show a generic sync failure; local
observations remain intact, but fresh/mixed history cannot finish hydrating
until updated. The implementation cannot retrofit an upgrade UI into those
binaries. Ship and verify the capable reader before enabling OpenAI, and
preserve the reader/guard during provider rollback while V2 results exist. There
is no SwiftData migration or rewrite of existing provider/confidence facts. The
[API contract](../backend-and-data/05-api-contracts.md#identification-result-readers)
owns the exact request and error semantics.

## Update-required UX slice

The native app now has one **Update Naturebook** prompt for exact identification
and history compatibility denials. **Update app** opens the verified Naturebook
App Store listing; **Not now** retains local access and the pause. The
account/build-scoped record prevents repeat history reads and same-build manual
retry loops, including completed-result recovery. Opening the store is not an
update acknowledgement. After a changed installed release/build, history retries
automatically and saved scans can be retried explicitly without losing their
completed-result ownership. The shared root defers behind deletion recovery,
Apple cleanup, and onboarding.

This adds no provider activation, database migration, quota change, or automatic
paid rerun. Public availability of a compatible release and the previous-build
upgrade check remain release prerequisites. Already installed old binaries
cannot gain this prompt remotely. See the
[presentation contract](../system-architecture/10-event-and-presentation-routing.md#update-required-presentation).

## Video snapshots as an additional visual route

The product captures about five seconds and sends five ordered image snapshots,
not the video file, for identification. An image-capable provider can process
these snapshots. Preserve `multimodal_video_frames_v1` as a distinct assignment
so photos and frames can be switched independently. Add a separately versioned
OpenAI frame binding using the same transport and native moderation machinery;
include every frame, its order/lineage and available timing/context. Never
relabel frames as still photos merely to pass the current photo-only validator.

The existing photo comparison stays frozen. A small separately approved frame
comparison must check sequence handling, uncertain/refused results, full media
promotion/recovery and the latency/cost of five images. Image moderation covers
only submitted frames, not every instant of the retained playback clip. Review
that product safety limit before activation. Observations containing audio keep
the complete Gemini binding until an audio-capable assignment is qualified;
never silently drop audio or split one observation into unapproved extra calls.

## Activation and return to Gemini

Prepare the exact disabled binding, target/SHA, client minimum, permission
readiness, runtime secret mapping, safety policy, accounting coverage and
qualification evidence as one reviewable activation change. Activation remains
separate from merging or deploying compatible infrastructure.

The future rollback changes **fresh** assignments back to a still-supported
Gemini binding after rechecking that recipient's permission. A changed recipient
must stop an already prepared request through the existing preflight-expectation
check; it must not silently disclose to a different provider. Already committed
or uncertain attempts retain their quota/recovery ownership and cannot be
automatically resent. Completed scans replay their saved result and provenance.
Preserve readers for any OpenAI results already saved; rollback must not rewrite
their scores or delete observations.

## Verification

The result-reader slice passed **2,148 Edge tests plus 342 steps**, including
all four endpoints' initial, quota-race and ingestion-race replay paths. The
complete disposable migration replay and **415 database assertions across 65
files** passed. Tests switch to actual anonymous, authenticated and service
roles and cover mixed pages, omitted metadata projections, private/public
visibility, malformed headers, metadata edits and unchanged scores. Database
lint found no errors; advisor error gates passed with 103 security and 79
performance warnings. The complete tooling suite, 355 migration-contract tests,
all 101 function entrypoint checks, regenerated runtime identity, DTO/media
contracts, recursive formatting/lint and Markdown checks also passed.
Independent read-only review verified the SQL/native boundary and the
service-client replay fix.

The new native SDK request test and relevant preflight/provenance suites passed:
**21 Swift Testing cases across four suites**. The complete native rerun was
attempted but the repository build wrapper refused to start while another
checkout's Xcode build used the shared simulator. That build was left running;
the prior complete native result below does not certify this reader slice.
Hosted native checks and reader-first release verification remain separate. This
slice made no paid provider request, deployment or production mutation.

### Earlier dormant connection evidence

The dormant connection slice passed **2,145 Edge tests plus 286 steps**, a
complete disposable migration replay, and **407 database assertions across 64
files**. These include headerless worker admission with original-client proof,
rejection of missing/invalid capability and changed recipient, atomic quota
rollback, immutable replay, native safety promotion and exactly-once unpriced
accounting when usage is missing. Database lint found no errors; security and
performance advisor error gates passed with the same 103 and 80 existing
warnings. The task-owned disposable database was stopped after validation.

The source gates also passed: 444 standard tooling tests plus 34 steps, 60
isolated evaluator tests plus 29 steps, the DTO/media contracts and ten shell
suites, 354 migration-contract tests, all 101 function entrypoint checks,
generated bundle fingerprints, recursive formatting/lint, iOS guardrails and
Markdown checks. Independent read-only review verified the capability and
worker-ABI fixes. No live provider calls or production mutations ran in this
slice.

The full native unit gate passed **1,372 XCTest cases and 3,013 Swift Testing
cases across 465 Swift Testing suites**, using the checkout-local simulator
cache. The earlier hosted iOS failure at `8eb8c95d4` identified the generated
V1/V2 DTO file crossing the ordinary source-size ceiling. Both architecture
inventories now explicitly name that generator-owned file; generated-contract
validation and all ordinary source ceilings remain enforced. Hosted validation
of the completed connection commit remains separate from this local evidence.

Focused tests cover the current Gemini profiles and confidence boundaries,
unchanged refusal and media-signal projection, unqualified-score alternatives,
invalid/mismatched policies, and an actual handler rejecting an OpenAI
evaluation snapshot before commitment/invocation/promotion. This is offline
source evidence; it neither calls a provider nor qualifies OpenAI safety or
biological accuracy.

First-slice local verification passed: **2,129 Edge tests plus 278 steps**, with
the six existing disposable-database tests ignored in this local run; **444
standard tooling tests plus 34 steps**, **60 isolated evaluator tests plus 29
steps**, the DTO/media contracts and all ten shell suites. The exact recursive
formatter, lint, function-entrypoint type check, 101 generated function configs,
dependency graphs, generated runtime fingerprint, Markdown and diff checks also
passed. The source-contract tests were updated to retain the latency boundary
through the new safety-signal owner. Independent read-only review found no
actionable runtime or contract issue. PR #84's first-slice hosted checks,
including the disposable database candidate gate, also passed at `744cd89eb`.
That is source validation, not deployment or activation evidence.

The photo-safety/metadata slice passed **2,141 Edge tests plus 280 steps**,
including the disposable-database cases; a complete migration replay and **406
database assertions across 63 files**; and **13 native tests in two suites**
covering live decoding, local save/reopen, historical sync and confidence
interpretation. Database lint and the security/performance advisor error gates
passed; their existing warnings remain outside this change. Standard tooling and
isolated evaluator counts remain 444 plus 34 steps and 60 plus 29 steps,
respectively, with DTO/media checks and all ten shell suites passing.

The candidate workflow now explicitly includes photo safety in its offline,
network/credential-denied adapter step. The exact recursive formatter and lint,
354 migration-contract tests, generated DTO validation, 101 function configs and
dependency graphs, entrypoint type check and runtime fingerprint check passed.
XcodeGen 2.45.4 regenerated the project without a source diff, and iOS project,
Markdown and diff checks passed. The focused native run used the checkout-local
build wrapper and retained its result bundle outside the build cache.
Independent safety and contract review verified rejection precedence and aligned
V2 identifier patterns and task vocabulary across Deno, SQL and Swift. Hosted
checks for this new slice are separate evidence; no live provider requests or
hosted mutations were performed.
