# OpenAI photo integration

Date: 27 September 2026\
Status: first result-policy slice implemented locally; production remains
Gemini.

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

1. **OpenAI safety and result contract.** Choose and document the actual
   photo-media safety mechanism before composing OpenAI in production. A
   successful identification or lack of refusal is insufficient evidence to copy
   Gemini's moderation meaning. Define allowed, rejected and unavailable
   dispositions, any extra call/cost, and behavior before promotion. Extend
   versioned provenance for reasoning effort and image detail; preserve old
   Gemini values and neutral OpenAI confidence. Exercise candidate output,
   refusal, malformed output, safety denial/unavailability and replay offline.
2. **Dormant runtime and admission.** Reuse the adapter behind an exact
   photo-only binding, complete-input checks, server-owned assignment and the
   existing atomic lease. Coordinate accepted client protocol, native/public
   readers, disclosure collection, usage units and reviewed pricing. Prepare
   GitHub-to-Supabase secret synchronization through the existing deployment
   workflow; never retrieve the GitHub secret locally. Keep the assignment
   disabled until its release conditions are satisfied. Neither a secret nor a
   consent grant activates it.
3. **Qualification and controlled activation.** Freeze the precise supported
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

Local verification passed: **2,129 Edge tests plus 278 steps**, with the six
existing disposable-database tests ignored in this local run; **444 standard
tooling tests plus 34 steps**, **60 isolated evaluator tests plus 29 steps**,
the DTO/media contracts and all ten shell suites. The exact recursive formatter,
lint, function-entrypoint type check, 101 generated function configs, dependency
graphs, generated runtime fingerprint, Markdown and diff checks also passed. The
source-contract tests were updated to retain the latency boundary through the
new safety-signal owner. Independent read-only review found no actionable
runtime or contract issue. Hosted candidate validation and deployment are
separate evidence; this record claims neither.
