# Identification provider optimization plan

Date: 25 September 2026; implementation updated 26 September 2026\
Status: Shared measurement, experiment controls, uncached OpenAI
control/candidate profiles and the private explanation reviewer implemented
locally; delegated AI review implemented; first paid screen closed inconclusive
after one control result, concise candidate deferred\
Scope: Shared identification foundation, OpenAI photo/text tuning, and Gemini
photo/text tuning, with a later path to qualified production use

## Direction update — 27 September 2026

The
[new optimization plan](./identification-optimization-preserving-results-2026-09-27.md)
now owns future priorities, following verified completion of the provider
infrastructure milestone. Preserve the current explanation format and detail;
concise OpenAI explanations are not a selected next step. The existing
measurement implementation, experiment controls and historical outcomes below
remain unchanged. References below to the first candidate or next optimization
slices describe the earlier plan, not the current work order.

## Decision

Use one optimization effort with a shared foundation and separate, versioned
configuration profiles for each provider. Shared work improves input
preparation, result interpretation and measurement. Each adapter owns the
settings needed to use its model effectively. Measure improvements for each
provider; a beneficial change does not automatically transfer to another model.

The first bounded brevity screen is
[closed as inconclusive](./identification-openai-concise-screen-2026-09-26.md)
after one control result exposed incomplete explanation references. Retain the
existing profile and defer this optional optimization. Production continues to
use Gemini. This plan does not activate OpenAI, alter production Gemini
settings, authorize another paid run, or qualify a provider for production.

The
[alternative-provider guide](../development-guides/22-alternative-identification-provider.md)
owns the implemented adapter and execution contract. This document owns the next
optimization slices. The
[evaluation PRD](../product/04-identification-evaluation-prd.md) and
[SRD](./identification-evaluation-srd.md) retain ownership of formal reference
review, scoring and qualification. Later production assignment follows the
[provider onboarding contract](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md).

## Starting evidence and limits

The
[25 September OpenAI pilot](./identification-openai-photo-text-pilot-2026-09-25.md)
recorded seven normalized results and one unknown execution across eight unique
attempts. Four species results and two non-biological results agreed with
provisional references. The mushroom name did not resolve through the small
frozen taxonomy, so its identity cannot be assessed from the saved record.

OpenAI's successful provider timings were 6.5–7.5 seconds, with a 6.9-second
median. The seven known usage estimates total approximately USD 0.18; the
interrupted attempt's usage and cost remain unknown. Earlier Gemini app runs
used different crops, context and execution paths. These records establish a
working alternative, but do not establish a controlled accuracy, latency or cost
winner.

Preserve all historical inputs, claims, reports and source hashes. The unknown
bison attempt and unscorable mushroom result stay in that history. Future
development runs use new IDs and explicitly declared repeat attempts; they never
replace the earlier outcomes.

## Shared work and provider-specific work

| Area                        | Shared responsibility                                                                           | Provider-specific responsibility                                                        |
| --------------------------- | ----------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Evidence                    | Preserve the observation, relevant context, media order and preparation version                 | Encode the complete supported input for the provider                                    |
| Identification instructions | Define subject classification, supported taxonomic rank, uncertainty and required result fields | Adapt wording where evaluation demonstrates a benefit                                   |
| Output                      | Use the common result contract and domain normalization                                         | Project the schema and decode native output without leaking provider prose              |
| Taxonomy and scoring        | Resolve canonical identities and synonyms; report unmapped answers honestly                     | Preserve provider/model provenance; never inherit another model's confidence thresholds |
| Performance                 | Measure the same boundaries and retain every outcome                                            | Tune reasoning, image processing, response length and provider cache behavior           |
| Cost                        | Keep conservative budgets and expose missing usage                                              | Interpret native input, cache-read, cache-write, output and reasoning units correctly   |
| Evaluation                  | Use the same frozen cases, references, scorer and report definitions                            | Maintain a baseline and at most one candidate per provider in the first round           |

Begin with still photos and descriptions. Audio, sampled-video frames, mixed
media, enrichment, BioCLIP and custom-model training remain later work. A
five-second video contributes ordered snapshots and may include companion WAV
audio; it is not a native-video request. Never discard unsupported evidence to
make an observation fit the OpenAI photo/text profile.

## Architecture for testing and production

Build on the existing shared preparation, request builders, adapters and
normalization. Keep authorization and execution records specific to each entry
point; production must not import evaluator scripts or accept evaluation-only
credentials, profiles or permissions.

| Component             | Evaluation entry point                                                 | Production entry point                                            |
| --------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------- |
| Identification engine | Shared evidence preparation, request building and normalization        | Same qualified implementations                                    |
| Provider profile      | Explicit baseline or candidate selected by a reviewed plan             | Approved server binding for the complete observation              |
| Admission             | Reviewed corpus, processor permission, readiness and experiment budget | User consent, entitlement and authoritative quota/model admission |
| Execution record      | Experiment accounting linked to existing durable run claims/results    | Existing durable scan lifecycle and saved-result replay           |
| Reporting             | Reference agreement, assessment coverage, paired time/cost comparison  | Reliability, latency, usage and drift by profile/input type       |

Profile definitions belong in reviewed code. Give every configuration an
immutable identity and digest covering provider/model/API, supported evidence,
prompt/schema versions, generation settings, output limit, cache policy and
confidence interpretation. Link preparation and normalization versions to the
qualification record. A changed setting becomes a new profile; resuming a run
never changes its configuration. Record requested and returned model
identifiers; a stable alias does not guarantee immutable provider behavior.

The evaluator may exercise an unqualified profile. Production may select it only
after qualification covers that exact configuration, shared implementation and
actual app/Edge path. Moving a tested configuration into shared modules must
preserve request parity and produce new source evidence. Qualification of a
different confidence policy, media path or prompt does not transfer silently.

Use three levels of testing:

1. **Offline CI:** Synthetic fixtures and intercepted transport check request
   construction, schema/refusal/truncation handling, unsupported inputs,
   timeouts, accounting and one invocation. No credentials or paid calls.
2. **Development comparison:** The existing eight examples and provisional
   labels screen a specific hypothesis under one frozen experiment plan.
3. **Production qualification:** Independently reviewed, held-out examples and
   complete app/Edge checks establish suitability for the intended input types,
   uncertainty, negatives, failures, consent, quota, persistence and replay.

Prefer separate evaluation projects/credentials for ongoing work where
practical. Both providers permit an explicitly reviewed shared paid application
project under their recipient-specific readiness versions. Gemini uses
`evaluation_gemini_processor_v1`; its legacy `evaluation_processor_v1` stays
dedicated-only. Both new provider records bind approved input permission to the
exact corpus and selected case set. Credentials stay in their respective local
launcher or approved backend secret store, outside profiles and reports.
Production provisioning follows the existing release procedure when that
integration is requested.

## Slice 1 — Repair shared measurement

Implementation status: the opt-in v2 catalog/projection/report and separate
exploratory comparison are implemented. Standalone v2 live admission remains
blocked; the Slice 2 controller provides the verified experiment path.
Historical v1 behavior is preserved. The
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#shared-measurement-repair-optimization-slice-1)
owns executable formats and commands. The explanation rubric and candidate
controller are implemented below. A reviewed real catalog, fact cards and actual
the selected review method remain pre-dispatch requirements; the candidate is
unqualified.

**Deliverable:** Reliable identity accounting and a report that can compare the
same photo/text examples without overstating its evidence.

- Extend deterministic identity resolution against a reviewed, frozen taxonomy
  catalog that includes canonical names, accepted synonyms and relevant ranks,
  rather than only the expected answers. Ambiguous matches remain unmapped; do
  not invent a match through an unrestricted fuzzy lookup.
- Record explicit mapping outcomes such as matched, ambiguous and unmapped in a
  versioned bounded projection. Retain canonical IDs/ranks and content-free
  diagnostics, not raw provider responses, reasoning or arbitrary name text.
- Keep subject classification measurable when identity is unmapped. Show
  unmapped and unknown counts separately; do not turn them into verified wrong
  species or silently remove them from the scheduled population. Define identity
  assessment coverage and each denominator before dispatch. Genus agreement does
  not validate an unsupported species answer.
- Add a provisional comparison report for exploratory runs. The current formal
  `compare` command rejects exploratory corpora; preserve that distinction.
  Reuse saved-record validation and keep the result `measurement_only`.
- Report provider time and normalization time separately. App upload, Edge
  persistence and rendering remain outside this local measurement. Include
  missing durations, failures and incomplete runs alongside successful timings.
- Preserve the conservative spend guard. Before claiming caching savings, add a
  separately labeled rate-aware estimate using validated native usage, including
  cache writes and reasoning without double counting. Cache storage charges, if
  applicable, must also be accounted for. Missing components remain unknown; a
  reservation or conservative ceiling is not an invoice.
- If shorter explanations are selected for Slice 2, first add the assessment
  below. Identity agreement alone cannot establish explanation quality.

### Explanation assessment required for a brevity candidate

Freeze a small rubric and assessment method before dispatch:

| Criterion            | Required evidence                                                                                                        |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Grounding            | Explanatory claims agree with the supplied observation and reviewed case facts; no invented visible features or evidence |
| Required information | The explanation retains the applicable reasons for the decision and required result information                          |
| Uncertainty          | Limits, abstention and supported taxonomic rank remain clear; brevity does not turn uncertainty into certainty           |

Keep reviewed case facts and rubric expectations in the scorer, separate from
provider input. They must not leak reference answers into identification
requests.

Assess baseline and candidate explanations in memory before `projection.ts`
discards their text. Retain only per-criterion `pass`, `fail` or
`not_assessable`, bounded reason codes, and rubric/assessor versions. Store no
raw explanation, reasoning or response body. Validate the assessment method on
reviewed synthetic examples; word counts, nonempty fields and the tested model's
own assertions do not establish grounding. No extra paid judge calls belong in
this experiment. If a trustworthy assessment cannot be made within this
boundary, defer the brevity candidate. These assessments remain development
evidence, not independent verification of species accuracy.

Primary owners are `projection.ts`, `runContracts.ts`, `scoring.ts`,
`exploratoryReport.ts` and `reports.ts` under
[identification_evaluation](../../services/supabase/scripts/identification_evaluation/README.md).
Changing record or scorer semantics requires a new version and compatibility
tests; historical records remain readable with their original interpretation.

**Exit:** Synthetic tests distinguish correct, wrong, unsupported-specificity,
ambiguous, unmapped, unknown and unattempted outcomes; report regeneration makes
no provider calls. Metric tests cover missing durations/usage, even-sized
medians, fixed-population cost totals and photo/description breakdowns. A
brevity candidate additionally requires the explanation assessment above. No
attempt is made to reconstruct the missing historical mushroom name or revise
old labels after seeing model answers.

## Slice 2 — Add reusable profiles and experiment controls

Implementation status: immutable `gemini_photo_text_v1` and
`openai_photo_text_v1` baseline descriptors, the controller, scoped OpenAI
launcher path and controlled report are implemented and verified offline. Native
baseline requests remain unchanged. The
[tooling contract](../../services/supabase/scripts/identification_evaluation/README.md#reusable-profiles-and-experiment-controls-optimization-slice-2)
owns formats, commands, locking, reservation accounting and stops.

The first candidate and its review method below are implemented behind the new
v2 experiment contract. It admits exactly the uncached control and concise
candidate in that order. The v1 experiment contract still accepts only the two
original baselines. Candidate prompts, cache settings and immutable identities
are defined in reviewed code; packet JSON cannot override them. Offline tests
exercise native parity, review storage, cache stops and interruption recovery.

**Deliverable:** Baseline and candidate configurations that can coexist in one
reviewed source revision, with a single experiment-wide accounting and stop
boundary. Production bindings stay fixed during these evaluation slices.

- Preserve OpenAI's current baseline: `gpt-6-sol`, low reasoning, high image
  detail, strict common JSON schema and an 8,192-token output ceiling that
  includes reasoning. Preserve the exact current `gemini_pro` request profile as
  the Gemini 2.5 Pro baseline. Gemini Flash is outside the first comparison.
- Add explicit evaluation profile identities for candidates. Snapshot model,
  prompt, schema, confidence policy, generation/cache settings and native
  request hashes. Reject unknown settings and unsupported inputs before a
  durable claim. A setting change requires a new profile/run, not a mutation
  during resume.
- Keep task requirements shared while placing native settings in their adapters.
  No client-selected provider, arbitrary endpoint, inherited environment
  override or runtime production selector is introduced.
- Select one change per candidate using the existing token/timing evidence.
  First consider repeated-instruction caching or concise explanation guidance.
  Select caching only after defining the cache controls below; select brevity
  only after completing the explanation assessment in Slice 1. Test these
  separately; do not combine prompt, reasoning and image changes in one
  candidate and attribute the outcome to one of them.
- Keep image detail and evidence fixed initially. Consider medium OpenAI
  reasoning or an adjusted Gemini thinking budget only in a later targeted
  experiment justified by an observed quality or latency problem. Reducing an
  output ceiling is not equivalent to reducing actual generation and can
  truncate required fields or reasoning.
- Optimize cache reuse around stable instructions and schema where supported.
  Keep observation-specific content separate and measure actual reported reuse.
  Do not share observations through conversation state. Cache settings, minimum
  lengths, retention and billing must match the exact model/API in use.

### One controlling experiment record

The legacy `runner.ts` guard accounts for its own run only. The new controller
adds an immutable experiment manifest above the existing run manifests, with a
durable journal for claims, outcomes, completion state and global stops. Freeze:

- Experiment/run IDs, case and evidence hashes, taxonomy/reference/scorer
  versions, source revision and profile digests.
- Run order, case-order seed, comparison window, cache controls, assessment
  rubric and exact decision metrics.
- Per-run request and USD allocations and aggregate experiment limits. The sum
  of allocations must fit those limits; unused allocations cannot transfer
  automatically to another profile.

Keep one active provider/profile run at a time. Before every invocation, take an
exclusive experiment lock, reconcile all linked run claims/results, check global
stop state and both budget levels, and durably reserve the attempt before
dispatch. Use one accounting entry per attempt, linked to its existing run
claim; ledger disagreement or an unresolved earlier claim blocks dispatch.
Launching the next provider or resuming a process cannot bypass this check.

For a completed attempt, replace its reservation with the validated conservative
usage estimate once. Retain the reservation for uncertain execution or missing
usage; never count it as zero or add both reservation and settled estimate for
the same attempt. The rate-aware comparison estimate is separate from this
conservative spend guard.

Any runner stop condition, including unknown execution, operational failure,
model mismatch, missing budget-critical usage or insufficient remaining
allocation, stops **the entire experiment** before another invocation. A run
finishing its full scheduled allocation normally is completion, not a stop.
Persist the stop so other launchers inherit it. Recovery preserves all claims
and reservations and requires a reviewed continuation within the original
aggregate limits; no automatic replay or allocation increase is permitted.

The controller coordinates records without loading provider credentials. Keep
each key and network allowlist in its existing single-provider launcher.

### Cache controls before candidate selection

Both providers already offer automatic prompt caching. Baseline requests can
warm repeated content later used by a candidate. Reported hits alone do not
establish that the candidate caused a saving. See
[OpenAI prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching)
and
[Gemini generateContent caching](https://ai.google.dev/gemini-api/docs/generate-content/caching).

The frozen plan must specify a supported cache-separation method for the exact
API/model and record why it prevents cross-profile warming. Separate run IDs,
API keys, presumed TTL expiry or a routing/accounting key alone are not proof of
isolation. Use the same control method for both arms, preserve identical
observation evidence, and include any request-affecting control in fingerprints.
If separation cannot be established, defer a caching candidate. If contamination
is discovered after dispatch, retain all results and mark the affected time/cost
comparison inconclusive; do not remove warmed cases after the fact.

Declare initial cache conditions and report cache reads, writes, misses and
unknowns for both profiles, including the first request. Reuse earned within
each arm's scheduled calls is part of that arm's total cost. For other candidate
types, apply the same comparability check before attributing time/cost changes
to the candidate. No additional prewarming, token-count, judge or cache-object
creation requests are included in round one. In particular, Gemini explicit
cache objects and their setup/storage lifecycle are deferred.

Primary owners are the evaluator's `profiles.ts`, `providers.ts`,
`runContracts.ts`, `admission.ts`, `runner.ts` and `files.ts`, together with the
pure request builders under
[`_shared/ai`](../../services/supabase/functions/_shared/ai/README.md).
Production `production.ts`, quota/model admission and consent remain unchanged.

**Exit:** Offline tests exercise every proposed profile, fingerprint changes,
schema compatibility, complete-input rejection, native usage interpretation and
one-invocation behavior. Baseline parity tests still pass. No live calls are
needed to finish this slice. Synthetic multi-run/crash tests prove aggregate
allocations, reservation reconciliation, exclusive execution and a stop in one
profile blocking all remaining profiles after restart.

## First candidate decision — concise OpenAI explanations

Decision recorded 25 September 2026; implemented locally 26 September 2026. The
[executable candidate contract](../../services/supabase/scripts/identification_evaluation/README.md#concise-openai-candidate-and-private-review)
owns accepted versions and commands. No real calibration or paid comparison has
been completed for these profiles.

### Hypothesis and scope

Test whether more focused `ai_reasoning` reduces OpenAI provider time without
losing evidence, useful reasons or uncertainty. Use OpenAI first; there is no
paired Gemini token/timing evidence that justifies a Gemini tuning candidate. Do
not add a second candidate just to fill the original 32-call allowance.

The seven successful pilot attempts recorded 216–361 visible output tokens and
30–111 reasoning tokens. These are whole-response counts, not explanation-only
counts; discarded prose cannot establish whether any explanation was verbose.
Three attempts reported 3,906 cached input tokens each and four reported zero.
Historical records did not retain cache-write counts. These observations justify
controlling caching and measuring a small hypothesis, not predicting a saving.
The historical pilot remains unchanged.

OpenAI's
[latency guidance](https://developers.openai.com/api/docs/guides/latency-optimization)
identifies reduced generation as one possible improvement. It does not establish
that changing this field will materially improve our request. If the eight-case
screen fails its existing 10% threshold, retain the original configuration and
close this hypothesis without a prompt sweep.

Use the same `gpt-6-sol` model, low reasoning, high image detail, 8,192-token
ceiling, strict schema, input bytes, normalization and unqualified confidence
policy in both arms. Change only the following instruction in the candidate:

> For ai_reasoning, prefer one concise sentence stating the strongest
> observation-supported reasons for the result. Use a second or third sentence
> when needed to preserve important limitations, uncertainty, or distinctions
> from alternatives. Avoid repeating the result name or adding general
> background unless it helps explain this observation. Never omit required
> evidence or qualifications to shorten the answer. All other field requirements
> remain unchanged.

This is task guidance, not a new word limit, output-token limit, schema
reduction or request for hidden reasoning. Both arms still provide the existing
user-facing explanation and required identification fields.

### Cache control for this hypothesis

Use these two new evaluation-only profile identities:

| Profile                                 | Role                 | Difference from the implemented OpenAI baseline |
| --------------------------------------- | -------------------- | ----------------------------------------------- |
| `openai_photo_text_uncached_v1`         | Experimental control | Explicit-only caching with no breakpoints       |
| `openai_photo_text_concise_uncached_v1` | Candidate            | Same cache control plus the instruction above   |

Keep `openai_photo_text_v1` immutable. The control is not a replacement baseline
for the historical pilot or for production.

The
[Responses caching documentation](https://developers.openai.com/api/docs/guides/prompt-caching)
states that GPT-5.6 and later requests with
`prompt_cache_options: { "mode": "explicit" }` and no explicit breakpoints do
not read or write the prompt cache. Apply that setting to both new profiles and
verify that neither request contains a breakpoint, prewarming, a previous
response reference or conversation state. Do not add run-specific prompt salts
or rely on cache keys or presumed expiry. This makes cross-arm warming
irrelevant to the proposed comparison, subject to runtime verification.

Require explicit, valid zero `cachedTokens` and zero `cacheWriteTokens` for
every attempted call. Missing counts, nonzero counts or unsupported settings
stop the experiment and make its performance conclusion inconclusive; no
fallback request is allowed. An absent counter remains unknown; never infer zero
from configuration. Preserve the charged outcome and reservation rules. This is
an implemented native configuration; account support and actual cache counters
remain unverified until an authorized live run.

A favorable result would apply to this caching-disabled control only. It would
not prove that the candidate beats today's automatically cached profile in
production. Record that limit in the comparison and carry the exact cache
configuration into any later qualification. Testing cache reuse itself remains a
separate question.

### Delegated explanation review — decision updated 26 September 2026

The owner has delegated this analysis to the active assistant. Use the v3
experiment contract and explicitly label assessments `assistant_local_v1`. The
assistant reviews the evidence and explanation with the same rubric; the owner
need not complete a practice form or grade each case. No additional paid judging
model is introduced. These are provisional AI assessments, which may share model
errors and do not establish independently verified biological truth.

The earlier owner-operated, local reviewer remains available through v2 for
someone who chooses to perform human review. Its actual-owner calibration rule
remains unchanged. The synthetic examples below now serve as rubric examples and
automated regression fixtures for the delegated path; a known answer key does
not establish an independent review or qualify an AI assessor. Never create an
owner calibration certificate from assistant choices.

Before dispatch, prepare one private fact card for each of the eight cases from
the exact supplied evidence. Freeze the card digest with the input digest and
rubric version. A card records visible/described features, relevant missing
information, acceptable decision reasons and the limits of supported rank, plus
bounded codes for each applicable explanation requirement. It must allow valid
equivalent wording and multiple defensible observations. Do not require an exact
reference phrase or assume that a provisional species label establishes all
diagnostic details. An ambiguous case stays ambiguous. These cards and reference
labels are reviewer inputs only and never enter a provider request or a public
report.

Present the evidence, fact card, normalized decision and applicable user-facing
explanation fields together. Score these three criteria independently:

| Criterion            | Pass                                                                                                                             | Fail                                                                             | Not assessable                                                            |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| Grounding            | Each material explanatory claim is supported by the evidence or reviewed facts                                                   | An invented or contradicted feature materially supports the answer               | The reviewer cannot verify a material claim from available evidence/facts |
| Required information | Specific, relevant reasons connect the observation to the classification or abstention; applicable required information survives | Empty, generic or circular justification; a necessary decision reason is omitted | The reviewed card does not establish what a useful reason would be        |
| Uncertainty          | Wording and supported rank reflect the evidence limits, including appropriate abstention                                         | Unsupported certainty or specificity, or a material limitation is concealed      | Available evidence/facts do not establish the relevant uncertainty        |

Use bounded reason codes: `supported`, `invented_evidence`,
`contradicted_evidence`, `missing_decision_reason`, `generic_justification`,
`unsupported_certainty`, `unsupported_specificity`, `missing_limitation`,
`insufficient_reference`, `reviewer_unsure`, `review_unavailable`. Do not offer
a free-text response field or default any criterion to pass. A short answer may
pass; a long answer may fail. Existing identity, false-biological, completeness
and supported-rank checks remain separate requirements.

Hide profile, token counts, durations, costs and previous ratings until each
rating is committed. Do not describe sequential single-reviewer assessment as
fully blinded: wording or run order can reveal the arm. Do not revise reference
facts or prior ratings after seeing the other arm. Unexpected but plausible
claims that the frozen card cannot support are `not_assessable`, not
automatically false.

### Assessment storage and failure behavior

Implement the review inside the local run, before the in-memory explanation is
released. Display only the needed user-facing fields, never hidden reasoning,
provider diagnostics, auth state or a whole raw response. Use a private local
view with escaped text, no third-party assets, no browser storage, no response
logging and no response caching. In delegated AI mode, the assistant processes
the bounded view in its session; that service may retain conversation/tool
context. Do not promise local-only handling for AI review. Use only the
task-approved cleared evaluation corpus and do not export screenshots, full
responses, hidden reasoning or private observations into a review archive.
Evaluation artifacts still contain no explanation prose. Bind the view and
submitted scores to the current attempt; an arbitrary JSON score supplied by
packet data is not a completed review.

Persist the bounded provider outcome and budget settlement before waiting for
reviewer input; review time must not inflate provider or normalization time.
Keep the corresponding explanation only in memory for the active review. Freeze
the final assessment under a new versioned record linked to experiment, run,
attempt, profile, evidence/fact-card digests, rubric, assessor method and an
opaque reviewer reference. Store only these bindings and criterion enums/reason
codes. Existing v1/v2 attempts remain unchanged and readable; their missing
assessments never become passes. Include assessment-file digests in the frozen
report inputs so reports regenerate without raw text.

The run must not dispatch its next paid call while an assessment is pending. If
the view closes, the process exits, review times out, or evidence cannot be
assessed, preserve any durable provider outcome/cost and stop further dispatch.
A missing review makes quality inconclusive. Do not classify a durably completed
provider call as unknown just because review failed, and do not repeat inference
to recover discarded text. If interruption precedes durable outcome storage, the
existing uncertain-claim reservation rule still applies.

### Optional human-review calibration (v2)

Use invented cases only for calibration. Fix expected ratings before exposing
them to the reviewer. The reviewer completes every item, then sees discrepancies
and repeats the calibration before a real run if any material criterion was
missed. This checks rubric comprehension, not expertise or production accuracy.
At minimum cover these anchors. The expected findings identify the targeted
criterion; the reviewer must still score all three criteria independently:

| Invented observation and example explanation                                                                                                                           | Expected assessment                                                                               |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| A smooth gray pebble with no visible living structures; “Its mineral surface and lack of visible biological structures support a non-biological classification.”       | All pass                                                                                          |
| The same pebble; “Visible gills and a spore print identify a fungus.”                                                                                                  | Grounding fails: `invented_evidence`                                                              |
| A spotted mushroom with underside and base unobserved; “The cap supports a mushroom identification; the missing underside and base prevent a reliable species choice.” | All pass                                                                                          |
| The same limited mushroom view; “This is definitely the named species; no further features are needed.”                                                                | Uncertainty fails: `unsupported_certainty`; required information fails: `missing_decision_reason` |
| The pebble; “It is a pebble because it is a pebble.”                                                                                                                   | Required information fails: `generic_justification`                                               |
| A blurry distant organism with no diagnostic detail; “The image does not show enough detail to identify it reliably.”                                                  | All pass, valid abstention                                                                        |
| An explanation invokes a diagnostic trait absent from the supplied facts and not visibly verifiable, without asserting it was observed                                 | Grounding is `not_assessable`: `insufficient_reference`                                           |
| No accessible evidence or no completed review                                                                                                                          | All `not_assessable`: `review_unavailable`                                                        |

An automated test can validate schema, bindings, persistence and known synthetic
ratings; it cannot prove a person's semantic review happened or replace that
review with keyword matching. Only mark human calibration complete from the
actual reviewer's recorded choices. V3 delegated review requires no human
calibration; its versioned assessments and report must identify the assistant
method and the absence of independent human validation. No human calibration has
been performed for real use yet.

### Bounded execution and completion

Narrow the proposed first round to **16 requests**: these two OpenAI arms on the
same six photos and two descriptions. Omit Gemini tuning and cross-provider
performance claims from this hypothesis. Freeze the per-run USD allocations,
source, rate card, facts and exact order before the existing execution approval.
The broader 32-call architecture is a ceiling, not a reason to spend it.

Primary metric: combined median provider latency. Keep the existing 10% minimum
gain, cost guard, per-input-group limits and full-population eligibility rules.
All three explanation criteria must pass for every case in both arms; a failed
or unassessable baseline also prevents a preservation claim. Output-token counts
are diagnostic, never a replacement for quality, elapsed time or billable cost.
One shared OpenAI rate-card digest must cover both profiles, including explicit
zero cache activity.

The local implementation includes the private reviewer, synthetic calibration,
versioned bounded assessments, report gate, two exact native profiles and
controller admission. The offline demonstration labels all choices and results
synthetic. If v2 human review is selected, real calibration must come from the
owner's choices. The selected v3 path records user delegation and a null
calibration digest, and applies the same stop/quality rules to actual assistant
ratings. Prepare a paid packet only after the offline gates pass. Do not add a
generic judge service, new production router, larger corpus or parameter sweep
for this test. If review cannot be completed reliably within these boundaries,
defer brevity and retain the existing profile instead of weakening the quality
check.

## Slice 3 — Run one bounded comparison

**Deliverable:** One paired exploratory report with a disposition for each
candidate and explicit limits on what the sample supports.

The original first-round ceiling allowed eight development examples across four
profiles, **32 provider requests total**: a baseline and candidate for each
provider. The selected concise-explanation hypothesis above narrows the next
proposed campaign to two implemented OpenAI profiles and **16 requests**. Their
CLI admission requires the v3 delegated-review plan (or optional v2 human plan)
and completed private review setup. Do not add a parameter sweep, automatic
retries, cache-prewarming calls or extra cases to this ceiling. If only one
candidate has a justified hypothesis, omit the other candidate's eight calls.

Before dispatch, freeze:

1. The exact cases, prepared bytes, observation context, provisional references,
   taxonomy, scorer, output requirements and measurement boundary. Prepare one
   packet for both providers; provider encoding may differ but evidence must
   not.
2. One source revision containing all profiles, the requested/returned-model
   checks, case-order seed, run execution order and comparison time window.
   Record every intentional configuration difference. Historical app timings are
   context, not the new control group.
3. Each candidate's single hypothesis, primary metric and decision limits. Keep
   safety, uncertainty and supported-rank requirements common to both.
4. The controlling experiment manifest, per-run allocations and total USD budget
   using current reviewed pricing and conservative reservations. The 32-call
   proposal is not spending authorization.
5. Provider-specific input permission, credential/readiness and retention
   records. Both providers permit reviewed shared paid application projects
   through their explicit recipient-specific records; the legacy Gemini record
   remains dedicated-only. Simulator access and a stored GitHub secret do not
   supply a local Gemini credential. Resolve access through the existing
   contract before scheduling a paid run.

Retain one provider/profile per live run and the existing narrow credential and
network permissions. Match the frozen case order and record execution timing.
Apply the predeclared cache controls and show cache-hit, no-hit and
unknown-usage observations separately. A small sequential run cannot remove
every service-load effect.

Use Slice 2's experiment-wide stop across all profiles. Retain each claim and
outcome, including scheduled cases left unattempted. A reviewed continuation
cannot silently replay uncertain attempts or expand the experiment budget.

**Exit:** Account for every scheduled case. Deliver per-case decisions, mapping
coverage, provisional reference agreement, unsupported specificity, false
biological assertions, valid abstentions, completion/failure counts, median and
range of provider time, and known/unknown estimated cost. Compare each candidate
to its own contemporaneous baseline before comparing providers. Eight examples
support a development screen, not a dependable tail-latency distribution or
independently verified accuracy claim.

### Exact metrics for the development screen

For each provider, compare its candidate with its own baseline over the same
fixed allocation: six photos and two descriptions. Publish the combined result
and separate photo/description summaries with their denominators. Never
substitute a surviving subset for the scheduled population.

| Metric                  | Definition and eligibility                                                                                                                                                                                                                                                                                                                                           |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Primary latency measure | Successful-identification median provider duration in milliseconds. A `normalized` biological, non-biological or valid abstaining result qualifies. Both arms must normalize all eight cases and have finite positive provider durations for all eight; otherwise the complete latency verdict is inconclusive.                                                      |
| Median calculation      | Sort eligible durations; use the central value for odd counts and the arithmetic mean of the two central values for even counts. Version this new exploratory report definition; existing reports retain their nearest-rank p50 semantics.                                                                                                                           |
| Cost measure            | Sum the rate-aware estimated USD cost over the full fixed allocation, including all billable attempts and components. Use validated rates and usage, with no double counting of cache or reasoning units. Report unknown amounts/counts alongside known totals; missing usage or unattempted cases prevents a complete cost verdict. Do not use median request cost. |
| Additional costs        | Include setup, storage and cleanup charges in any future experiment that permits those operations, with allocation fixed in advance. Round one forbids the extra operations; ordinary in-request cache read/write costs remain included.                                                                                                                             |
| Diagnostics             | Report all completed-call and failure durations, normalization time, per-case paired changes, mapping/assessment coverage and all excluded or missing measurements. These do not replace the chosen primary metric.                                                                                                                                                  |

For latency, let `B` be the baseline median and `C` the candidate median. For
cost, use the respective full-allocation totals. In either case calculate
`improvement_percent = 100 * (B - C) / B`, with `B > 0`; a zero or unknown
baseline makes the percentage unassessable. Positive values indicate
improvement. Apply the same definitions within each input-type summary. Use full
precision for decisions and round only for presentation.

## Decision rules and stopping point

Use these proposed screening rules when preparing the frozen run plan:

- A candidate must preserve evaluability and completion and introduce no new
  observed reference disagreements, false biological assertions, unsupported
  specificity or contract/safety failures versus its baseline. An unmapped
  answer cannot conceal a regression; unresolved quality comparisons are
  inconclusive.
- A brevity candidate must also pass the frozen explanation rubric for every
  scheduled case, with no unresolved assessment or new failure versus baseline.
- For a speed/cost candidate, freeze either combined latency or combined total
  cost as primary. Require `improvement_percent >= 10` for that metric and
  `improvement_percent >= -10` for the other. Require both metrics to be
  assessable and neither to regress more than 10% in either input-type summary;
  an aggregate gain cannot hide a photo or description regression. These are
  development screening targets, not production limits or claims of statistical
  significance, especially for the two descriptions.
- Missing billable usage blocks a cost-saving conclusion. Missing outcomes or
  incomparable evidence blocks a complete quality/performance verdict. Retain
  the baseline when the result is inconclusive or the benefit is too small.
- Stop after this round with a written recommendation: retain baseline, retain
  candidate for further qualification, or investigate one concrete remaining
  problem. Another experiment needs a named question; more testing is not an
  automatic next step.

The optimization milestone is complete when the shared measurement fixes,
versioned profiles and comparison report are reviewed and documented. It can
finish successfully with no provider switch.

## App-controlled assignment foundation

The subsequent
[matched comparison plan](./identification-gemini-openai-matched-comparison-2026-09-27.md)
prepares the existing Gemini Pro and OpenAI baselines on the same eight
development inputs. It does not restart the closed concise screen or advance
formal qualification counts.

The [input-routing slice](./identification-provider-input-routing-2026-09-26.md)
derives a complete-input profile before admission and records a private backend
assignment. All rows remain Gemini. Users decide whether to permit data
processing; they cannot pick or approve the model/provider assignment. Denied
permission blocks that request without triggering another provider. This adds
infrastructure, not production qualification, a live comparison or authority to
enable OpenAI.

## Later milestone — Production qualification and integration

Advance only a promising profile through the existing
[provider onboarding contract](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md).
This is separate from the eight-case optimization milestone:

1. Freeze intended complete-input support and acceptance limits, then qualify
   the exact configuration on independently reviewed held-out evidence. Keep
   development examples outside that held-out set. Establish provider-specific
   confidence interpretation; historical Gemini meanings stay intact and raw
   OpenAI scores remain unqualified until that work is complete.
2. Integrate processor-specific consent, authoritative model/quota admission,
   persistence/client compatibility and any required migration. Test the real
   app/Edge path, including refusal, partial output, account/deletion fences,
   unknown execution and durable replay. Local request parity alone does not
   establish app latency or Edge memory/media compatibility.
3. Retain a fixed, reviewed server binding initially. A later binding may select
   OpenAI for qualified photos/descriptions and Gemini for audio-containing
   observations only when the selected task supports all included evidence.
   Sampled frames and mixed media require their own qualification. Enrichment
   tasks retain their separate assignment and quota/cache lifecycle.
4. Record profile/configuration digests with admitted attempts and a promotion
   record linking qualification evidence, compatible app/backend versions,
   source SHA, rollout checks and a still-eligible rollback binding. Apply the
   existing exact-SHA release procedure and operation/target authorization;
   evaluation success is not activation. A future traffic selector requires its
   own implementation and review.
5. Rollback changes eligible future assignments. Completed scans keep their
   saved interpretation and replay without new inference; in-flight or uncertain
   attempts follow existing recovery/admission. Do not add automatic
   cross-provider retries.

Correctness must hold on a provider cache miss. Keep provider prompt caches
separate from Merian's result replay and species-content caches; qualify content
cache provenance/invalidation before mixing providers. Explicit Gemini cache
objects are a later optimization only if measured reuse justifies their setup,
expiry, cleanup and storage costs. Keep OpenAI `store: false`, and review prompt
cache processing and abuse-monitoring retention separately under
[OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data).

For ongoing operation, measure completion, refusal, invalid output, unknown
execution, latency and known/unknown cost by profile and input type. Keep
diagnostics bounded and content-free. Telemetry can reveal operational drift;
accuracy still requires reviewed regression evidence. Reevaluate changes to
models, prompts, preparation, schemas, generation/cache settings or confidence
policies against their affected risks. Do not expand a paid campaign or promote
a changed profile automatically.

## Verification and references

For documentation-only changes, format the edited Markdown and run the Markdown
and documentation-contract checks. Implementation slices use focused synthetic
tests while iterating, followed by the complete affected Supabase tooling and
Edge gates in the
[testing strategy](../development-guides/08-testing-strategy.md). Keep CI
offline. Database, client and production-release gates apply only when a later
slice actually changes those surfaces.

Current provider references, reviewed 25 September 2026; recheck exact model/API
support and pricing when preparing a candidate:

- [OpenAI model optimization](https://developers.openai.com/api/docs/guides/model-optimization)
  and [GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol).
- [OpenAI reasoning](https://developers.openai.com/api/docs/guides/reasoning),
  [image detail](https://developers.openai.com/api/docs/guides/images-vision)
  and
  [prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching).
- [Gemini thinking](https://ai.google.dev/gemini-api/docs/thinking) and
  [generateContent context caching](https://ai.google.dev/gemini-api/docs/generate-content/caching).
  Use the documentation for the deployed SDK/API; examples for a different API
  do not establish compatibility with the current `generateContent` adapter.

The real eight-case packet, taxonomy, fact cards, pricing and USD 86 ceiling
were reviewed and frozen with delegated AI review. The authorized run completed
one control request before the reference-coverage stop documented below. There
is no automatic next paid comparison. A future brevity test needs prospective
facts covering all assessed explanation fields, frozen before dispatch, while
preserving this result unchanged. Owner practice is not a prerequisite for the
delegated path. Different-provider costs remain descriptive totals until paired
rate-card comparability is explicitly reviewed.

## Single-session execution — 26 September 2026

The owner approved the prepared OpenAI comparison of eight cases across two
profiles, at most 16 requests and $86 total ($43 per profile). The approved
single-session launcher retains one hidden-entry key only in process memory and
invokes the existing controller in frozen order. It stops on controller failure,
incomplete assessment or state, and a changed plan. This approval does not
expand the corpus, enable retries or qualify production use. The active
assistant performs the delegated assessment; no further owner practice is
required. Actual dispatch still requires the private readiness records and
matching key. The private packet retains the exact approval and execution
window; this document does not substitute for those records.

## Recorded outcome — 26 September 2026

The
[bounded outcome record](./identification-openai-concise-screen-2026-09-26.md)
closes this screen as inconclusive: one saguaro control result agreed with the
provisional reference, took 7.067 seconds at the provider boundary and has a
rate-aware estimated cost of USD 0.024711. The assistant could not assess
lookalike-species claims from the frozen reference card; grounding is
`not_assessable / insufficient_reference`, while decision reason and uncertainty
pass. The controller's broader `explanation_quality_failed` stop code must be
interpreted with those ratings. The other 15 assignments remain unattempted;
there was no retry or concise-candidate call.

Retain the existing OpenAI profile and defer the brevity optimization. Review
and package the modular provider implementation on its own evidence. Any later
production assignment still requires its existing qualification and release
controls. No claim about a prompt winner, a provider winner or independently
validated explanation quality follows from this screen.
