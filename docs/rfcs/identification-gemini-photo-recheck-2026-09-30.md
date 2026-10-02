# Focused Gemini photo recheck

Status: all six calls completed on September 30 local time (October 1 UTC). The
follow-up is closed without additional calls or production changes. The owner
approved this follow-up after the completed
[Sol reasoning pilot](identification-sol-reasoning-pilot-2026-09-30.md) and
concern that OpenAI was less accurate than Gemini. No production routing,
prompt, badge threshold, or iOS release changes follow automatically.

## Completed comparison

All six predeclared Gemini attempts completed and normalized, with six durable
claims, six result records, no technical failures and no outstanding
reservations. The original OpenAI report remains byte-for-byte unchanged.
Gemini's conservative accounted cost was $0.21786; including the earlier twelve
OpenAI calls, total accounted cost was $0.686069501 against the shared $10 cap.
These amounts are conservative accounting estimates, not invoices.

| Measurement                                         | Recorded Sol-low | Recorded Sol-medium | New Gemini Pro |
| --------------------------------------------------- | ---------------: | ------------------: | -------------: |
| Completed calls                                     |                6 |                   6 |              6 |
| Accepted canonical matches on three reference cases |              1/3 |                 2/3 |            2/3 |
| Demonstrated wrong species on reference cases       |                1 |                   1 |              0 |
| Unmapped named answers on reference cases           |                1 |                   0 |              1 |
| Mean provider time                                  |          6.805 s |            11.092 s |       15.771 s |
| Median provider time                                |          6.491 s |            11.202 s |       15.305 s |
| Conservative accounted cost for six calls           |         $0.21667 |            $0.25154 |       $0.21786 |

Zero demonstrated Gemini errors does not mean zero biological errors: its
unmapped butterfly answer remains unverified and receives no correctness credit.
The three reference cases are selected diagnostic examples, not a provider-wide
accuracy sample. All primary subjects were classified biological; the supplied
photo remains outside the correctness denominator.

| Gemini call | Case                         | Raw score | Outcome                                         |
| ----------: | ---------------------------- | --------: | ----------------------------------------------- |
|           1 | Supplied hanging-plant photo |      0.92 | Golden Pothos; no reference correctness score   |
|           2 | Same supplied photo          |      0.92 | Golden Pothos; no reference correctness score   |
|           3 | Same supplied photo          |      0.92 | Golden Pothos; no reference correctness score   |
|           4 | Purple Dead-nettle           |      0.95 | Accepted species match                          |
|           5 | Queen butterfly              |      0.92 | Unmapped scientific name; no correctness credit |
|           6 | Shaggy Mane                  |      0.94 | Accepted species match                          |

Gemini returned the same canonical Golden Pothos identity on all three supplied
photo calls (`gbif:2868323`, species). This agrees with the owner's
identification but does not create an independent reference. Sol-low also
repeated one answer three times, the unmapped name A recorded in the preceding
pilot; Sol-medium returned name A twice and Golden Pothos once. Therefore Gemini
showed a different consistent answer, not greater observed repeatability than
Sol-low. The Gemini repeats used the preserved seed/settings, and the last two
reported 2,672 cached input tokens each. They do not establish independent
accuracy or general repeatability.

Both providers accepted Purple Dead-nettle. Gemini and Sol-medium accepted the
reviewed Shaggy Mane identity; Sol-low's scientific name failed mapping. On the
Queen reference, both Sol settings returned the wrong mapped species, Monarch.
Gemini returned an unmapped primary name with digest
`049c8ec96b03515602915d81b4f66333963517380ad167afabc964f43fbf3e1c`. Its
alternatives included Monarch at 0.75 and the accepted Queen identity at 0.70;
alternatives do not rescue an unverified primary answer. No retrospective
taxonomy change, name parsing or model adjudication was used. This follow-up
does not demonstrate that Gemini corrected the butterfly failure.

Gemini took about 8.97 seconds longer per call on average than Sol-low in these
runs, approximately 2.32 times its provider time. The calls were sequential and
not contemporaneously randomized; three of six calls repeated one photo and
reported caching differed. These measurements exclude upload, enrichment and app
display time. The similar conservative cost totals do not establish equal
invoiced prices. Higher raw confidence is not evidence of better calibration.

Recommendation: treat Gemini Pro as a reasonable quality-first beta fallback
candidate if the additional latency is acceptable. This small comparison
supports that consideration through its agreement on the supplied photo and
valid mushroom answer, not a claim of overall provider superiority. It leaves
the butterfly result unresolved. Do not extrapolate this Pro result to Gemini
Flash. Keep the earlier decision against promoting Sol-medium, and make no
badge-threshold or automatic-verification change from this evidence. Close the
approved experiment without another comparison; production photo routing is
still OpenAI pending any separate provider decision.

Completed evidence:

- Report file SHA-256:
  `992ae2a9bd79dafacfcaed102a93f44cc30f60484a5f3acf4f494038f4bab060`.
- Completion artifact timestamp: `2026-10-01T04:58:13Z`.
- Six claims and six results; `complete: true`, `stop: null`, zero outstanding
  reservations, `confidenceQualification: false`, `productionActivation: false`.
- Source, manifest and preserved baseline hashes are listed under preparation
  evidence below. Completed report accounting and baseline preservation were
  independently rechecked locally without network access or additional calls.

## Fixed scope

Make six new Gemini Pro calls, using the exact four prepared images, empty
description text, null region/month context, frozen taxonomy and reviewed
references from the completed pilot. Compare with its recorded OpenAI-low
results; retain OpenAI-medium as secondary descriptive evidence. Make no new
OpenAI calls.

| Evidence                           | New Gemini calls | Purpose                                                       |
| ---------------------------------- | ---------------: | ------------------------------------------------------------- |
| Owner-supplied hanging-plant image |                3 | Repeatability; no independently established species reference |
| Purple Dead-nettle                 |                1 | Supported species match                                       |
| Queen butterfly                    |                1 | Lookalike discrimination                                      |
| Shaggy Mane                        |                1 | Supported species match and scientific-name mapping           |

The three repeatability slots run first, followed by the reference cases in the
table's order. Every slot is declared before execution. Failed or uncertain
attempts consume their slots; no retries, replacement cases or extra calls are
authorized. The existing OpenAI results and references remain immutable.

Use the preserved `gemini_pro` request: `gemini-2.5-pro`, `identify_vision_v1`,
`merian_identify_v1`, temperature 0.1, seed 42, 8,192 output tokens, 5,000
thinking tokens and the existing 90-second deadline. The runner uses the
production request builder, adapter, registry snapshot and normalization. Its
synthetic evaluation authority is not a production account, quota grant or
end-to-end mobile test. Both providers receive the same prepared pixels; their
complete provider-specific prompts and settings differ.

## Accounting and privacy

Keep the cumulative ceiling at $10 **including the $0.468209501 already
accounted for in the OpenAI pilot**. Freeze the completed baseline report,
original plan, manifest, taxonomy, actual Gemini requests, settings, source
graph and current Gemini pricing before dispatch. Copy approved prepared assets
into a new private 0700 packet; do not modify the previous packet or publish the
supplied image.

The [Google pricing page](https://ai.google.dev/gemini-api/docs/pricing) lists
Gemini 2.5 Pro's higher standard rates as $2.50 per million input tokens and $15
per million output tokens, including thinking. Reserve the full documented
[model ceilings](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-pro) of
1,048,576 input and 65,536 output tokens: $3.60448 before each sequential
attempt. This intentionally exceeds the configured output ceiling. Reconcile
complete, consistent numeric usage at those maximum rates without a cache
discount. These are conservative accounting amounts, not invoices.

Durably flush an exclusive claim before invoking the provider. Missing or
contradictory usage, model mismatch, interrupted execution or other technical
failure stops collection; uncertain accounting retains the full reservation.
Resume never repeats a claimed slot. The frozen packet path and sibling
authorization receipt prevent accidental copied-packet replays. As in the
original pilot, this is a trusted local operator tool, not an authorization
service against an owner deliberately rewriting approved inputs.

Use the existing paid Naturebook Gemini key through a hidden terminal prompt.
The key stays in process memory and is neither printed nor saved. The launcher
permits only Google's API endpoint, required SDK environment names with
overrides unset, Git source inspection and the private packet. Supabase, R2,
OpenAI and application-default credentials are unavailable.

Retain only bounded numeric usage, timing, normalized taxon IDs/ranks, outcome
codes, confidence scores and normalized-name hashes. Provider prose and raw
responses are not saved. Source facts, reference labels and filenames do not
enter provider inputs. Preserve the 22 October retention deadline for prepared
media. This follow-up makes no explanation-quality claim and adds no
explanation-rating steps.

## Interpretation

Score the three reference cases with the same predeclared accepted canonical IDs
and ranks. Report mapping failures separately from demonstrated biological
errors, preserving them as unverified outcomes. The supplied photo contributes
only repeatability and cross-provider agreement; repeated agreement alone does
not prove the species. Compare raw scores descriptively without treating a
higher score as evidence of greater accuracy.

Report all six slots, reference matches, mapping failures, inconsistencies,
provider latency, cost and technical stops. These cases were selected after
observing OpenAI results. Gemini runs later; no contemporaneous randomization or
cache equivalence is established. This is a focused diagnostic comparison, not
held-out evidence or an estimate of provider-wide accuracy.

A useful outcome is whether Gemini resolves the known failure and whether the
supplied photo is more consistent. If evidence remains mixed, report that
directly and close this comparison. Do not expand it automatically. Any proposal
to change the default provider must name the behavior and target; this run does
not activate or roll back production.

The
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#focused-gemini-photo-recheck)
owns commands and files. The existing hosted comparison remains a separate
eight-case, two-provider workflow and is not repurposed for this run.

## Preparation evidence

The private packet passed offline preparation with network and environment
access denied. At preparation, zero of six Gemini attempts had been claimed or
dispatched; collection awaited the paid Gemini key at the hidden terminal
prompt.

- Source graph SHA-256:
  `5419e16ee2e11f60321fd7ab47c59bb351e16a9043c2e1ce0826d4999b4b1751`.
- Frozen Gemini manifest fingerprint:
  `2be48228a975f642e759b14dde179867b23440891cf0c013b85d3fb9875174d7`.
- Preserved OpenAI baseline report file SHA-256:
  `2bcf93d582fa761ca49ddfa455b859e677aa81962b1d6b0ca10ca7c04fb9166a`.

The four focused runner tests passed, covering request parity, parent-evidence
integrity, failed or uncertain accounting, interrupted resume and duplicate-call
prevention. Five synthetic hidden-key launcher scenarios passed without network
calls. The complete `make test-supabase-tooling` gate passed, including 479
standard tests, 136 filesystem evaluation tests, both isolated DTO suites and
shell regressions. Backend formatting and lint, changed Markdown formatting and
`git diff --check` also passed. An independent read-only contract audit found no
blocking issues. These checks establish implementation readiness, not live
Gemini results or identification accuracy.
