# Six-audio app benchmark

Date: 22 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: Six first results and six complete measurement windows recorded;
exploratory evidence only

All three animal clips produced Strong matches that disagreed with their
provisional source labels. All three reviewed non-biological controls returned
**No wildlife detected**. Each case completed through the ordinary app using
Gemini 2.5 Pro, with no manual retries. The
[sanitized benchmark record](./identification-evaluation-evidence/2026-09-22-audio-six-app/app-results.json)
retains outcomes, measurements, usage, estimates and evidence hashes.

This run uses the six unchanged clips from the
[preparation packet](./identification-audio-six-preparation-2026-09-22.md). The
owner listened to its exact-sample reel and confirmed no speech, spoken species
labels or personal information, and no audible animals in the stream, thunder
and car-alarm controls. That completed eligibility for a new exploratory corpus;
it did not independently verify the three animal species references.

## Method and evidence boundaries

The new packet passed canonical offline preflight: six audio groups and twelve
prepared requests across the existing Flash and Pro profiles, with network and
environment access denied. None of those requests was dispatched. The inputs,
references, app plan, pricing and preflight were frozen before the first app
submission. The preparation packet remains unchanged, including its historical
pending-review state.

The ordinary-app plan permits six sequential submissions, one per clip, with
normal Gemini selection and no manual retries. Each case uses Debug simulator
replay staging and the normal **Identify** button, after a separate passive
observer reports ready. Each observation window lasts 120 seconds, with a
30-second collector shutdown grace; windows do not overlap. The reviewed WAV is
the only staged evidence: no images, descriptions, source labels or expected
names were entered.

The observed app is version 1.0.3, build 275, on iPhone 18 Pro / iOS 27.0. Its
embedded source revision is `807b9af9964e3eba0b9d4212d7dc91d8945d4118`, with
dirty source state and fingerprint
`82da4dc3da24a4de9ace2c2be1f2746144c7191cc9c26309fddfe9655db03cd5`. The expected
and observed backend bundle fingerprint is
`05aedfe76acc8d8bcee71f5ebf0f9de22590e79715e6cc80f1f4ab6032576558`. The
checked-out evaluator source is recorded separately in preflight; it does not
attest the installed app or independently prove deployment state.

Closing completed species results left Debug replay disabled. Reopening the same
app restored the empty capture workspace; subsequent cases use that recovery
before staging. There was no data reset or runtime code change. This
pre-submission interaction is outside tap-to-result timing. The reason for the
disabled replay control has not been established.

## First visible outcomes

| Case    | Source reference                                | First visible result                   | Displayed match | Tap to first frame |
| ------- | ----------------------------------------------- | -------------------------------------- | --------------- | -----------------: |
| `c0013` | Common Raven, _Corvus corax_                    | American Crow, _Corvus brachyrhynchos_ | Strong          |           17.410 s |
| `c0014` | Elk, _Cervus canadensis_                        | Red Fox, _Vulpes vulpes_               | Strong          |           16.552 s |
| `c0015` | American Green Tree Frog, _Dryophytes cinereus_ | Snow Goose, _Anser caerulescens_       | Strong          |           21.476 s |
| `c0016` | Stream; source/owner-reviewed non-biological    | No wildlife detected                   | Non-biological  |           14.810 s |
| `c0017` | Thunder; source/owner-reviewed non-biological   | No wildlife detected                   | Non-biological  |           15.896 s |
| `c0018` | Car alarm; source/owner-reviewed non-biological | No wildlife detected                   | Non-biological  |           13.507 s |

The three animal answers disagree with the frozen source labels. These are
provisional species disagreements, not independently verified species errors. No
result was manually confirmed, corrected, substituted or retried. The Strong
label is retained as displayed; it is not converted into an invented numerical
confidence score.

The controls produced fresh HTTP 200 responses and visible non-biological
results, not transport failures. Their result agrees with the pre-recorded
subject class and owner listening check. They do not validate species-level
identification or establish a general false-positive rate.

## Timing and cost

All six windows completed normally with six projected events each: HTTP timing,
native diagnostics, response-to-first-result state, postflight, total pipeline
and tap-to-first-rendered-frame. All responses reported fresh delivery, valid
provider/Edge timings, and the same requested/returned `gemini-2.5-pro`, app
identity and backend bundle fingerprint. No observation windows overlapped.

| Case    | Provider call | Edge total | App pipeline | Primary estimate, USD |
| ------- | ------------: | ---------: | -----------: | --------------------: |
| `c0013` |     12.9367 s |  14.6037 s |     16.336 s |            $0.0247450 |
| `c0014` |     13.0781 s |  14.3102 s |     15.777 s |            $0.0232850 |
| `c0015` |     16.8579 s |  19.4008 s |     20.690 s |            $0.0282925 |
| `c0016` |     11.7795 s |  12.8813 s |     14.244 s |            $0.0242125 |
| `c0017` |     12.6375 s |  13.9053 s |     14.710 s |            $0.0259850 |
| `c0018` |     10.4092 s |  11.5932 s |     12.873 s |            $0.0215725 |

Tap-to-first-frame ranged from **13.507 to 21.476 seconds**, with a median of
**16.224 seconds** across these six different clips. These intervals overlap and
must not be summed as separate pipeline stages. This small set is not a
production latency distribution or repeatability test.

The sum of the six observed primary-attempt estimates is **$0.1480925**. The
pricing snapshot is the unchanged reviewed 22 September snapshot, still within
the observer's seven-day freshness limit. This sum is not the total bill; the
cost limitations below remain in force.

## Recommended next slice

Prioritize audio-path verification before tuning prompts, thresholds or model
assignment. Trace the frozen WAV through replay preparation, queue handling, the
backend's audio normalization and Gemini request construction. Check sample
rate, channel count, duration, MIME/container consistency and preservation of
the intended samples with local deterministic fixtures. Establish what can be
verified without retaining production payloads or personal context. These
benchmarks currently prove staged source identity and reported execution
identity, not end-to-end payload equivalence.

If that path is sound, use the preserved disagreements and controls to design
one bounded audio-model or prompt comparison, keeping inputs fixed and treating
species labels as provisional until reviewed. The modular provider foundation
supports that later experiment, but these results alone neither select a new
provider nor justify a production confidence threshold. Meaningful paired
audio/visual tests remain open; the earlier video's companion audio was silent.

## Limits

This is a small development challenge set, not a production accuracy estimate,
provider comparison or confidence-calibration study. Independent biological
reviewers remain unavailable; formal progress stays at 0/60 development and
0/240 held-out groups. Public-source training exposure is unknown. The earlier
cardinal/Wood Thrush/Pyrrhuloxia disagreement remains unresolved and separate.

Input hashes verify the source files staged for replay. They do not attest the
app's eventual inference bytes or full contextual fields, which were not
retained. Import, physical microphone capture and replay preparation happen
before the measured Identify tap. The nonvisual path emits no visual-preflight
marker; missing values remain null.

Primary-attempt estimates use the reviewed 22 September pricing snapshot, with
the highest input rate and candidate plus thinking tokens. They exclude other
attempts, enrichment, storage and transport; neither app submissions nor
observer records establish the complete provider-call count or invoice.

No runtime code, model assignment, prompts, confidence policy or production
deployment changes are part of this evidence update. Native and backend suites
were not rerun for these documentation and benchmark artifacts.

## Retention and verification

The private admitted/run packet has **44 frozen files**, directory mode 0700,
file mode 0600 and retention through 22 October 2026. Its final freeze hash is
`415a055676d36ae0bf93aa8856a2b86d67188c97ea51f5c42e20400909489c8c`. The
pre-submission input freeze hash is
`e6e3f7d9371fc0912150143710c3b766a942338e479915e9a019ce8d1e3b0e09`. The original
24-file preparation freeze remains
`a9f33d2c482036c2b8d73a69269e0528d4f038697a7a497624626fa406602daf`.

Validation checked offline admission/preflight, immutable input and previous
packet hashes, one observed first result per case, readiness before each
submission, nonoverlapping windows, consistent execution identities, token
totals and primary-cost arithmetic. Raw OS logs, response prose, account/scan
identifiers and actual app context were not retained. The earlier media,
single-audio and reference-review packets remain unchanged.
