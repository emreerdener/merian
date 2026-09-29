# Luna photo candidate: evidence limits for minerals

Date: 2026-09-28

Status: Implemented and locally verified. The real packet passed offline
preflight; separate paid-run approval is pending. No paid candidate requests
have run and no production assignment has changed.

## Problem and hypothesis

The
[completed six-case Luna screen](identification-luna-sol-photo-screen-results-2026-09-28.md)
matched all six primary references, but the mineral explanation treated a
specific mineral identity as established while reserving uncertainty mainly for
its variety. The frozen facts did not establish that identity. This was an
explanation-specificity failure, not proof of an incorrect mineral or a failed
non-biological classification.

The shared prompt asks for a maximally specific common name and geological names
"if identifiable", without explaining this evidence boundary. The candidate
makes that boundary explicit. It asks Luna to use a broad mineral name when
visible or supplied evidence cannot distinguish plausible identities, describe
any proposed identity tentatively, and keep the result name and explanation
consistent. Uncertainty about a variety cannot establish its broader mineral
identity. The model must not imply that absent tests or provenance were
supplied.

This is an application-specific hypothesis. OpenAI's
[prompting guidance](https://developers.openai.com/api/docs/guides/latest-model#prompting-best-practices)
recommends evaluating guidance with the chosen model and workload; it does not
establish that these instructions improve Luna's mineral identification.

## Isolated candidate

| Property                 | Candidate                                                                |
| ------------------------ | ------------------------------------------------------------------------ |
| Evaluation profile       | `openai_photo_luna_evidence_limits_low_v1`                               |
| Prompt                   | `openai_identify_vision_evidence_limits_v1`                              |
| Model                    | `gpt-6-luna`                                                             |
| Settings                 | Low reasoning, high image detail, 8,192 output tokens, 90-second timeout |
| Control                  | Unchanged `openai_photo_sol_low_v1` / current production Sol request     |
| Prompt UTF-8 SHA-256     | `58d79c33674e0a3467a1408080b07634ec0a97fd9aa802dbacc4d3c229b40bfd`       |
| Canonical schema SHA-256 | `bda80368f8be0ef9424e22b7f7adfa1c7ecc5098ff68c9e52bc4c8f69182e52e`       |

`openaiLunaEvidenceLimits.ts` projects only the Geological Exceptions and
Nomenclature instruction lines. Missing or duplicate anchors stop preparation.
The rest of the request remains identical to the historical Luna payload: media,
optional notes, schema, field requirements, generation, moderation, storage and
tools. The current explanation format and detail are preserved; there is no
concise-explanation or null-field experiment in this candidate. Biological
identification instructions, confidence handling and badge labels remain
unchanged. The shared prompt, Gemini and production Sol are unchanged. The
candidate cannot enter production admission or the historical evaluator.

## Next bounded comparison

Prepare a **new private packet directory**, copying only the twelve existing
photos, corpus, taxonomy, frozen fact cards and reviewed pricing. Use a new plan
ID and `photo_model_plan_v3`; retain the original packet and stopped journals.
Do not copy old approvals, results or ratings into the new run. The v3 plan
selects the candidate Luna profile and unchanged Sol control. Its pricing uses
the existing Luna tariff because the exact model and billing mode are unchanged.

The existing controller schedules at most eighteen requests: six Luna screening
cases first, followed by six challenge photos evaluated once by each profile,
with alternating model order. No descriptions are added. The whole schedule has
one attempt per assignment, no automatic retry and a proposed $40 ceiling. The
current full-context reservation including the regional premium is $39.0071088;
this is a conservative cap, not expected spend. The previous six Luna requests
had a combined usage-based upper bound of about 1.07 US cents; that is
historical evidence, not a price guarantee for this comparison.

A new `photo_model_candidate_approval_v1` must authorize
`18_call_luna_evidence_limits_sol_photo_comparison` and explicitly bind
`reference_gaps_recorded_v1`, the new plan, clean source, credential
fingerprint, budget and review delegation. Original and continuation approvals
cannot substitute for it. There is no candidate continuation that clears a
terminal stop. The
[provider guide](../development-guides/22-alternative-identification-provider.md#luna-evidence-limit-candidate-comparison)
contains the executable preparation and launch procedure. Preparation grants no
spending or production authority.

## Review and decision

The assistant reviews each explanation against the photograph and unchanged
facts, using the existing rubric. All six screen decisions must match at a
supported rank. Actual explanation errors, reviewer uncertainty/unavailability,
provider or safety failures and unknown billing stop the screen. A missing
reference may remain `not_assessable / insufficient_reference` and permit
collection, but cannot become a quality pass.

For the mineral, the uncertainty criterion must pass at both the broader mineral
identity and variety level; a correct non-biological flag alone is insufficient.
Do not demand a particular mineral name or reward a longer generic disclaimer.
Biological results must retain their useful identification and explanation. The
six challenge pairs then inform the candidate-versus-Sol comparison, with all
failures and reference gaps included in its report. Preserve the existing
criteria rather than changing labels or facts after seeing candidate output.

These six screening cases are reused development examples; they are not a
held-out accuracy estimate. A historical-versus-new Luna difference cannot
isolate prompt causality from run variability. The contemporary challenge
compares complete model/prompt profiles, not models alone. Completion may inform
a limited beta selection decision with explicit evidence limitations, but cannot
establish formal calibration, a general Pro advantage or universal speed/cost
claims. Production activation still requires its separate admission and release
work.

## Verification

Focused adapter and controller tests cover isolated prompt projection, pinned
prompt identity, unchanged Sol requests, exact model and native moderation,
versioned approval, pricing, reference-gap accounting, failure stops and
immutable historical journals. They use invented inputs and mocked outputs,
proving software behavior only.

- Network/environment-denied photo adapter suite: six tests passed.
- Complete `make test-supabase-tooling`: 455 standard tests, 90 isolated
  evaluator tests, both DTO groups (20 and 21 tests), recursive checks for 111
  tooling sources and all twelve shell suites passed. The isolated evaluator
  includes 24 photo-model tests.
- Complete Edge Function suite: 2,171 tests and 343 steps passed, zero failures;
  nine database-dependent cases retained their existing ignored status.
- All 102 function entrypoints type-checked; config synchronization and isolated
  dependency-graph guards passed. Recursive Deno formatting/lint, changed
  Markdown formatting and diff whitespace checks passed.
- The checked-in identification bundle fingerprint was regenerated and its
  deterministic generator test passed. This records the new import graph, not a
  deployment or a change to the production request settings.
- Independent read-only contract review found the requirement to use a new
  packet root. Documentation, private preparation and a no-dispatch regression
  address it; no additional admission, billing, provenance or stop-rule blocker
  was found.

The new private `2026-09-28-luna-evidence-limits-photo-v1` packet contains exact
copies of sixteen approved input/media files. Its plan digest is
`ba4d877d35dc6312d0f5fde34eb354997a14ab5ddc01fe1a618e1e75989eb522`. Offline
preflight prepared eighteen requests with the $39.0071088 full reservation
inside the proposed $40 ceiling and `dispatchAuthorized: false`. All six Sol
assignment records equal the original preflight; all twelve Luna assignments
have new profile/request/snapshot identity while retaining evidence and tariff
bindings. The original plan and all 24 earlier journal artifacts retain their
byte hashes. No candidate approval or execution journal has been created.

Database and iOS suites were not run for this prompt/evaluator change. The local
Supabase CLI precheck found 2.90.0 instead of the repository's 2.109.1 pin; no
Supabase database or deployment command was run. The Deno source/config checks
above do not substitute for a future complete release gate. No paid
model-quality result is claimed here.
