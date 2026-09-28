# Luna/Sol photo comparison preparation

Date: 2026-09-28

Status: Real input packet prepared and offline-validated. Zero new provider
requests. The durable local controller and launcher are implemented. The owner
approved a $40 maximum for the same 18-call Naturebook comparison on 28
September. The private plan is v2/$40; execution uses a credential-bound clean
revision and the existing key. No production assignment changes.

## Frozen scope

The [Free/Pro model plan](identification-openai-free-pro-models-2026-09-28.md)
compares `openai_photo_luna_low_v1` with `openai_photo_sol_low_v1`. Both use the
production photo prompt, explanation format, low reasoning, high image detail,
8,192-token output limit and native input/output moderation.

The packet retains the exact six photo inputs from the
[matched benchmark](identification-gemini-openai-matched-results-2026-09-27.md),
including their original bytes, empty descriptions and context. Their existing
reference facts are reused. The six new cases below were selected and reviewed
before any Luna or Sol response to them existed in this experiment.

| Case    | Challenge                                | Frozen reference limit                                                       | Image/source                                                                                   |
| ------- | ---------------------------------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `c0101` | Monarch lookalike in a busy background   | Viceroy, `Limenitis archippus`; extra hindwing band is visible               | [USFWS viceroy](https://www.fws.gov/media/viceroy-0)                                           |
| `c0102` | Small bee/wasp-like insect               | Hoverfly family, `Syrphidae`; fine species characters are not resolved       | [USFWS hoverfly](https://www.fws.gov/media/american-hover-fly-sitting-leaf)                    |
| `c0103` | Similar grey treefrog species            | Genus `Dryophytes`, with legacy `Hyla` accepted; no call or genetic evidence | [USGS treefrog](https://www.usgs.gov/media/images/copes-gray-treefrog)                         |
| `c0104` | Lichen among moss and debris             | Genus `Peltigera`; publisher reference is genus-only                         | [USFWS lichen](https://www.fws.gov/media/freckle-pelt-lichen)                                  |
| `c0105` | Bark without diagnostic needles or cones | Provisional genus `Pinus`; finer specificity is unsupported                  | [USFWS pine bark](https://www.fws.gov/media/healthy-loblolly-pine-bark)                        |
| `c0106` | Mineral pattern resembling a plant       | Non-biological manganese-oxide dendrites; no plant identification            | [Creator-released mineral photograph](https://commons.wikimedia.org/wiki/File:Dendrites01.jpg) |

The sources mark these photographs public domain. The assistant inspected the
prepared images: no people, personal information or species labels are visible;
the mineral photo includes a measurement scale. New images use neutral asset
names, metadata removal and ordinary resizing to at most 1,024 pixels on the
long edge. Both profiles receive identical bytes for each paired case. Original
benchmark images retain their existing preparation unchanged.

Reference reasoning additionally consults the
[NPS viceroy/monarch comparison](https://www.nps.gov/articles/000/monarchs-in-cuyahoga-valley.htm),
[University of Maine grey treefrog facts](https://extension.umaine.edu/signs-of-the-seasons/indicator-species/gray-treefrog-fact-sheet/)
and
[NC State loblolly pine identification](https://plants.ces.ncsu.edu/plants/pinus-taeda/common-name/loblolly-pine/).
These are provisional source-backed pilot references, not independent expert
adjudication. A publisher's species label does not establish that all diagnostic
features are visible. Disputed reference limits must remain explicitly
unassessable; they cannot decide a model winner or be silently changed after
responses. A cautious abstention should be distinguished from a confidently
wrong name in the qualitative report.

## Private preparation

Private packet name: `2026-09-28-luna-sol-photo-preparation-v1` under the
existing local evaluation parent. It contains 12 contained assets, the
exploratory corpus, a frozen taxonomy with plausible alternatives, 12
explanation fact cards, source/eligibility records, reviewed prices, and the
comparison plan. Retention remains 22 October 2026. These media, facts and
references stay outside Git and outside model prompts except for the intended
image evidence.

`preflight-free-pro-photo` validates the packet with network and environment
access denied. Its content-free output records digests, source identity and:

- 12 Luna calls and six Sol calls, one attempt per assignment.
- Six Luna screening cases first; a review stop is required before challenges.
- Six paired challenge cases, alternating which model runs first.
- `dispatchAuthorized: false` and `liveControllerAvailable: true`.
- `evidenceStatus: provisional_reference_pilot`.

The initial preflight fingerprinted the dirty preparation revision. Preflight
must be regenerated against the reviewed clean execution revision before a live
approval is issued, and again after any approved plan change. A preflight is
neither release nor live-run approval. Input scope records the owner's
preparation request; that record does not increase the spending ceiling or
authorize production.

## Budget finding and approved execution

At the reviewed global Standard token ceilings, full-context reservations are
$0.268644 per Luna call and $5.37288 per Sol call: **$35.461008** for the
complete schedule. A 10% regional premium, if applicable to the account, would
bring that to $39.0071088. These are deliberately conservative reservations, not
predicted or measured spend. The original $5 proposal could not proceed under
that method.

On 28 September, the owner explicitly approved a **$40 maximum** for the same
18 generation calls in the Naturebook project. The private plan was revised to
`photo_model_plan_v2`, retaining the exact inputs, references, pricing, model
profiles and assignment order. The original v1/$5 plan and preflight are
preserved privately. There are still no automatic retries or additional
requests. The assistant is responsible for the explanation reviews.

No input-token-count requests are needed for this approved comparison. Their
compatibility and billing remain unvalidated; this run uses the existing
full-context reservation.

The durable controller now provides per-attempt immutable claims, no automatic
reruns, refusal/error handling, conservative handling of missing usage,
transient assistant review and a content-free journal/state summary. It reuses
the existing hidden-key launcher through `--photo-model-live` and requires an
explicit v2 plan, approved budget and credential-bound clean source before
dispatch. It reserves the 10% premium even if the account does not incur it. The
current real packet is v2/$40. Its private approval binds the exact clean source
and the existing Naturebook credential fingerprint; GitHub secrets cannot be
read back into this local launcher. A completed run must report quality at the
justified rank, unsupported certainty, explanation support, moderation, latency
and priced usage; this preparation establishes none of those model outcomes.

## Local verification

- The complete backend Function suite passed: 2,168 tests, 343 steps. Nine
  database-dependent tests were ignored; no disposable-database validation or
  hosted deployment is claimed for this evaluation-only change.
- The complete Supabase tooling gate passed, including 455 standard tests, 79
  isolated evaluator tests, both DTO test groups and the shell suites.
- The 13 focused photo-model tests cover the frozen packet, complete synthetic
  run, budget rejection, wrong matches, missing reviews/usage, interruption,
  concurrency, durable configuration stops, native model/safety failures and
  explicit source/key/approval binding.
- All 102 deployable entrypoints were type-checked; dependency/config checks,
  executable DTO validation, recursive Deno formatting/lint and diff whitespace
  checks passed. Markdown was formatted with Deno.
- Independent read-only review found two durability/audit-classification gaps.
  Both were corrected and their regressions passed; the follow-up review found
  no remaining issue in those changes.

These checks use invented outcomes or local validation. They do not measure Luna
identification quality, real API compatibility, account access, cost or latency.
The real packet has made zero new model requests.
