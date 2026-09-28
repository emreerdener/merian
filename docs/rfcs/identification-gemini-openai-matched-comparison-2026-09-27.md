# Matched Gemini/OpenAI identification comparison

Date: 27 September 2026 (UTC)\
Status: completed on 27 September; all 16 first attempts normalized. The
[outcome record](./identification-gemini-openai-matched-results-2026-09-27.md)
owns measurements and limitations. The preparation and execution plan below is
preserved as history, not authorization to repeat the run. Existing benchmarks
remain valid for their recorded inputs and configurations. Production
qualification remains pending.

## Decision and scope

Compare the two existing photo/text profiles using the same six photos and two
descriptions. Run each case once per provider: **16 requests total**. This is a
development comparison of complete configurations. It answers whether OpenAI
merits held-out qualification and identifies concrete quality, timing or cost
differences worth investigating.

Prioritize photos without optional notes. The expectation that most users will
omit notes is a product assumption, not measured adoption. Keep the existing
benchmarks and their limitations; adding a note option does not require
rerunning them. The proposed matched pair addresses a separate
provider-comparison gap and is not a repeat required by capture UI changes. Do
not expand the corpus or rerun completed evaluations solely to cover that UI
change.

| Arm                  | Existing reusable profile | Model            | Calls |
| -------------------- | ------------------------- | ---------------- | ----: |
| Current Pro baseline | `gemini_photo_text_v1`    | `gemini-2.5-pro` |     8 |
| Alternative baseline | `openai_photo_text_v1`    | `gpt-6-sol`      |     8 |

The Gemini arm is the existing Pro configuration, not the free-tier Flash
configuration. OpenAI keeps low reasoning effort and high image detail. Both
retain their code-defined prompts, schemas, normalization and 90-second timeout.
The private profile descriptors record every configuration difference. This is
not a claim that only the vendor changes.

Production assignments remain Gemini. Audio, sampled video frames, combined
media, enrichment and Field Chat are outside this comparison. The closed concise
prompt screen stays closed; none of its claimed requests is resumed or erased.

## Inputs and references

Reuse the prepared eight-case corpus and reviewed taxonomy from the September 26
development packet. Copy the six sanitized image files byte-for-byte into a new
private directory; preserve both descriptions, evidence order, capture context,
source lineage and provisional labels. Do not add crops, inferred location,
reference answers or reviewer notes to either provider's input.

The preparation record binds the source packet hashes, all assets, each input,
taxonomy, exact profile descriptors, prepared native requests and the current
evaluator source. Source-specific references stay provisional. An unmapped or
ambiguous taxon stays unassessable; do not turn a model prediction into its own
reference. These previously used development cases do not increase the formal
held-out count or establish general identification accuracy.

Real inputs and detailed curation stay outside Git in private storage through
the inherited retention date, 22 October 2026. Repository documentation contains
only the plan and bounded verification facts. This describes the original local
packet; the subsequent public test-export decision below permits selected copies
without publishing that packet wholesale.

### 27 September update: reuse the existing public bucket

The owner accepts public access to these test materials and selected the
existing Cloudflare R2 `merian` bucket. Prepare an explicit test export under
`benchmarks/identification/`. A separate bucket, a private prefix and changes to
the app's public-media access rules are not prerequisites for this comparison.

The export may contain the approved test images and descriptions, necessary
source attribution, public-safe case/profile metadata and comparison results.
Preserve the frozen provider inputs and existing benchmark records. All eight
prepared cases already record rights approval and personal-data exclusion;
include applicable attribution when preparing the public copies. Retain the
existing 22 October expiry for exported case material.

Do not upload the private working directory wholesale. Exclude credentials,
account configuration, credential-review records, operator filesystem paths,
personal data and raw diagnostic responses. Public access to test objects does
not authorize public writes or paid execution. The hosted design still needs
authenticated writes and durable run claims to prevent duplicate paid requests;
those claims should contain only public-safe run identifiers and accounting
facts.

Use the existing `Production` environment's `GEMINI_PAID_API_KEY` and
`NATUREBOOK_OPENAI_API_KEY` directly in the proposed GitHub Actions job. This
supersedes the local key-entry direction below for the hosted comparison. The
workflow and explicit export are implemented in the subsequent
[hosted comparison slice](../development-guides/23-hosted-identification-comparison.md).
Source implementation uploads no files, changes no bucket settings and makes no
provider requests. Freeze the actual candidate, reviews and run window before
exporting and dispatching.

## Measurements and interpretation

Use the existing boundary: prepared evidence through provider execution and
normalized identification. Exclude phone capture/upload, admission, dictionary
hydration, persistence and rendering. Earlier app timings and interrupted pilot
results remain historical context; they are not either arm of this new pair.

Report all eight assigned cases per provider, including refusal, failure,
unattempted and uncertain execution. Show photos and descriptions separately:

- Normalized completion and provisional agreement at the supported reference
  rank, with evaluable denominators and every unresolved mapping retained.
- Non-biological controls, unsupported specificity and disagreements requiring
  reference review. OpenAI's unqualified confidence cannot inherit Gemini's
  Strong/Diagnostic labels.
- Provider and normalization durations, arithmetic medians and matched-case
  comparisons. Different completion sets cannot establish a speed advantage.
- Input, visible-output, reasoning and cache usage where present, missing usage,
  and usage-based estimates under each reviewed price card. Thinking tokens are
  counted once. Conservative context-tier rates are upper estimates, not an
  invoice or proof of a percentage saving.

The v1 controller runs one provider block followed by the other using the same
frozen case order and a short common window. It cannot interleave credentials in
one process. Automatic caching and block order remain uncontrolled; do not claim
isolated uncached performance or statistical significance. The existing
`experiment-report` owns completion/accounting evidence; `compare-exploratory`
provides descriptive comparisons. Distinct price-card digests and uncontrolled
caching keep its savings and qualification verdicts unavailable.

Complete the planned pair or report it incomplete. A completed, promising result
can justify a separate held-out qualification proposal. A disagreement, missing
quality assessment or small/uncertain benefit does not justify production
activation. Explanation quality is not qualified by this baseline measurement;
the abandoned brevity hypothesis and its reference gap are not silently cleared.

## Preparation and execution boundary

The owner clarified on 27 September that the existing benchmarks should be
retained and should not be repeated because of optional description/note
support. This supersedes the earlier proposal to wait for **Explore scan
submission note prompt** before freezing or running the provider comparison. The
comparison may use its own reviewed source revision; the concurrent capture work
is not a prerequisite.

When the capture work integrates, perform a targeted regression check that a
photo submitted without a note preserves the same identification evidence.
Description-only and photo-plus-note serialization, recipient/provenance and
admission/replay checks belong to that feature's integration checks. These
checks need not make paid provider requests or repeat the benchmark suite.

If the model, prompt, preprocessing, evidence delivered to the provider or
normalization actually changes, assess the affected cases for remeasurement. A
UI or eligibility-only change does not invalidate the provider-only results.
Record the source used for every new run without rewriting old evidence. The
eight-case comparison does not establish the benefit of adding a note; evaluate
that separately if it becomes material to the product or a quality claim.

Preparation produces a non-executable `comparison-draft.json`, corpus/taxonomy,
fresh per-provider pricing cards, and input/profile verification. It has no
`experiment.json`, live readiness records, credentials or dispatch claims.
Ordinary corpus `preflight` runs with environment and network access denied;
separate calls to the existing pure profile/request builders verify both arms.
Synthetic mechanics are never written as results for these real cases.

Before any paid execution, finish the concrete live packet:

1. Bind the reviewed paid Gemini and Naturebook OpenAI projects/credentials. Use
   `evaluation_gemini_processor_v1` and `evaluation_openai_processor_v1`,
   respectively, with truthful `dedicatedEvaluationProject: false` for shared
   projects. Each needs its own approved exact corpus/case permission, actual
   credential fingerprint and valid processor/retention review. Legacy Gemini
   readiness remains dedicated only. No project or key is created by
   preparation.
2. Recheck pricing and the private draft's full-context conservative
   reservations. Review the proposed per-run and total budget for exactly 16
   first attempts. A budget proposal is not authorization and covers only this
   evaluator's requests, not other application traffic on shared projects.
3. Select the actual short execution window, freeze a clean source revision, and
   create the v1 controller plan with fresh run IDs and readiness digests. Run
   `experiment-preflight` after those records exist. Never fill missing review
   or key hashes with placeholders to obtain a passing preflight.
4. Execute each provider with its own scoped key/environment/network grants.
   Stop on the existing unknown-execution, model-drift, operational, usage,
   expiry, source or budget controls. Retain claimed uncertain calls; do not
   retry, fail over, expand the corpus or start another sweep automatically.
5. Regenerate reports offline and record the result and one next decision.

The owner supplies any required key directly to hidden local input. A GitHub
secret already stored for the app cannot be read back into this runner, and app
access does not expose the backend's Gemini key.

## Separate iOS release work

The owner reported successful development-build use on a physical iPhone. That
is not an archive, TestFlight installation or released-store migration record.
Provider comparison preparation can proceed independently. Before wider native
distribution, follow the existing exact-build archive/upload procedure and
genuine released-store install-over plus relaunch checks, retaining saved
observations. This plan does not perform or authorize those release operations.

## Owners and sources

- [Evaluator contracts and commands](../../services/supabase/scripts/identification_evaluation/README.md)
- [Alternative-provider guide](../development-guides/22-alternative-identification-provider.md)
- [Formal reference, scoring and qualification](./identification-evaluation-srd.md)
- [Closed concise screen](./identification-openai-concise-screen-2026-09-26.md)
- [iOS release procedure](../development-guides/14-ios-release-versioning.md)

Price and model references checked during preparation on 27 September 2026 UTC:
[OpenAI GPT-6 Sol](https://developers.openai.com/api/docs/models/gpt-6-sol),
[OpenAI pricing](https://developers.openai.com/api/docs/pricing),
[Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing),
[Gemini 2.5 Pro limits](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-pro).
The private pricing review retains the applicable rates and conservative limits;
revalidate them if the run is delayed.
