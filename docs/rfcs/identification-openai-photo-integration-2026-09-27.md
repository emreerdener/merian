# OpenAI photo integration

Date: 27 September 2026\
Status: result-policy boundary, dormant photo safety adapter and V2 metadata
readers implemented; production remains Gemini.

## Decision

Advance the existing OpenAI baseline toward an app-controlled **still-photo**
assignment. The
[completed matched comparison](./identification-gemini-openai-matched-results-2026-09-27.md)
supports this development decision: both providers agreed with five provisional
biological photo references and one mineral control; median provider time was
7.10 seconds for OpenAI and 15.81 seconds for Gemini. These are six reused
development examples, not held-out qualification or an end-to-end app benchmark.

Keep description-only requests on Gemini for the first rollout. Both providers
over-specified the mushroom description. Audio, sampled video frames (including
the five snapshots from a five-second capture), combined media, compatibility
routes, enrichment and Field Chat also retain their current Gemini assignments.
A photo's optional note stays part of the complete observation; never drop it to
qualify for a photo lane. The completed no-note benchmarks remain valid.

The app owns assignments. End-user permission can allow or block disclosure to
the app-selected processor; it is neither a preference nor an instruction to
switch providers. No automatic cross-provider retry is proposed.

## Completed foundations and this slice

The September 26 implementation already supplies complete-input classification,
database-owned assignment, recipient preflight, independent consent evidence,
client compatibility, immutable result provenance, neutral treatment of unknown
scores, and metric restrictions in shared/public consumers. Preserve those
owners; do not rebuild them as a new routing system.

The first remaining code slice is an independent result-policy boundary in
`_shared/ai/multimodalResultPolicy.ts`. The primary handler prepares it from the
admitted execution snapshot **before quota commitment or invocation**. It
accepts only the existing Gemini primary task, model, binding, prompt/schema,
confidence and safety combinations. A missing or unsupported policy refunds
unused quota through the existing retryable failure path. Registering an adapter
alone cannot authorize its result handling.

Normalization now receives an explicit diagnostic threshold from that policy,
instead of deriving one from the account tier. OpenAI evaluation continues to
use an explicitly unqualified policy that retains alternatives even at maximum
raw confidence. This preserves current benchmark semantics and grants no
production authority.

Only an outcome matching the prepared Gemini result profile exposes native
finish/rating signals to the existing media moderation path. Gemini's absent
ratings retain their historical behavior. OpenAI has no qualified equivalent
here: absence of Gemini ratings cannot be used to approve its media. The
evaluation snapshot is rejected before provider spend or promotion, including
when injected into the actual handler in tests.

This is a source change to the primary result-processing boundary. It changes no
database assignment, public payload, consent collection, credential store, model
request, prompt, generation setting or existing stored result. The runtime
fingerprint is regenerated for this implementation; the completed comparison
retains its original source and hash.

## Remaining slices

1. **Dormant runtime and admission.** Reuse the adapter behind an exact
   photo-only binding, complete-input checks, server-owned assignment and the
   existing atomic lease. Coordinate accepted client protocol, native/public
   readers, disclosure collection, usage units and reviewed pricing. Prepare
   GitHub-to-Supabase secret synchronization through the existing deployment
   workflow; never retrieve the GitHub secret locally. Keep the assignment
   disabled until its release conditions are satisfied. Neither a secret nor a
   consent grant activates it.
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
Current native protocol 3, permission collection and all server assignments are
unchanged. Future routing must enforce a client minimum that actually reads V2
before producing OpenAI results.

This slice does not yet connect the new adapter to production admission or media
promotion. The next slice must compose the safety disposition before side
effects, settle each failure through the existing attempt owner, preserve native
usage/accounting and gate compatible clients. Recording metadata or constructing
a snapshot is not authority to invoke a provider.

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
