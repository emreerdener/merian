# First controlled audio identification benchmark

Date: 22 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: First audio result and complete measurement window retained; Strong
match disagrees with provisional source label

The owner completed the listening review for the previously prepared ten-second
bird sample. One ordinary-app submission then returned **Wood Thrush
(_Hylocichla mustelina_) — Strong match**, while the NPS source labels the
recording **Northern Cardinal (_Cardinalis cardinalis_)**. Preserve this first
mismatch: the workflow completed, but its answer disagreed with the provisional
reference. The
[sanitized results](./identification-evaluation-evidence/2026-09-22-audio-replay/app-results.json)
retain the result, measurements, identities and frozen-evidence hashes.

| Case                | Tap to first frame | App pipeline | Provider await | Total Edge | Primary estimate |
| ------------------- | -----------------: | -----------: | -------------: | ---------: | ---------------: |
| `c0011`, audio only |           19.022 s |     18.174 s |       15.529 s |   16.739 s |    USD 0.0291825 |

This completes the third and final submission in the bounded plan that began
with the
[Describe repeat and first video](./identification-replay-app-benchmark-2026-09-22.md).
All three submissions produced visible results and complete observation windows,
with no manual retries. Their known primary-attempt estimates sum to **USD
0.0933925**. This is not total billed cost: optional enrichment, unobserved
attempts, transport and storage remain unknown.

## Eligibility and first outcome

The source is the NPS
[Northern Cardinal call](https://www.nps.gov/tont/learn/nature/birds.htm),
credited there to NPS/S. Sanders. The earlier preparation used the first ten
seconds, converted to metadata-free mono 44.1 kHz PCM16 WAV. The 882,044-byte
file's SHA-256 remained
`6854410b4ec668ea78a02d728cd06d235088162794f7f6da425dcc6cbc06688f`. The owner
confirmed that the displayed listening copy contains only animal/environment
sounds, without human speech, spoken labels or personal information. That
confirmation completes listening eligibility; it is not an independent
species-identification review.

A new private packet records that confirmation and the unchanged input hash. It
leaves the earlier pending-state packet and benchmark JSON immutable. Offline
preflight passed for one exploratory audio group and one provisional species
reference, preparing two requests across the existing Gemini profiles without
dispatch. The separate ordinary-app plan allowed one submission, using the
remaining slot in the original three-case maximum. Input, taxonomy, eligibility,
pricing and plan records were frozen before submission. The original recording,
segment and any future derivatives retain observation group `g0011`.

The approved WAV was copied to the fixed simulator inbox, staged with **Debug
replay → Stage audio sample**, then submitted once with normal **Identify**. No
image, description or expected species label was entered. Normal preparation,
consent, admission, durable queueing and Gemini selection remained in effect.
The result was observed independently on screen and was not manually confirmed,
corrected or retried.

The source label is provisional. The owner reviewed privacy and answer leakage,
not the biological identity of the selected segment. A source-label or
segment/background-sound issue has not been excluded, so this is a documented
Strong-match disagreement, not an independently verified model error. Formal
accuracy, confidence calibration and provider comparisons remain unassessed;
formal progress stays **0/60 development and 0/240 held-out groups**, with zero
independent biological reviewers.

## Measurements and limits

The observer was ready before Identify and closed normally with six events and
collector exit code zero. The fresh HTTP 200 response retained
requested/returned `gemini-2.5-pro`, consistent token usage and valid
provider/Edge spans. The nonvisual path emits no visual preflight marker; that
field remains null. The cost estimate uses the same reviewed 22 September
pricing snapshot, including thinking at the highest reviewed rates without a
cache discount.

The installed iPhone 18 Pro / iOS 27.0 Debug app remained version 1.0.3, build
275, source revision `807b9af9964e3eba0b9d4212d7dc91d8945d4118`, dirty state and
fingerprint `82da4dc3da24a4de9ace2c2be1f2746144c7191cc9c26309fddfe9655db03cd5`.
The response retained backend fingerprint
`05aedfe76acc8d8bcee71f5ebf0f9de22590e79715e6cc80f1f4ab6032576558`. The offline
tooling recorded current documentation commit
`10267f2e27293fc0d30f0d0a6c34b0586b379e9f`; this does not replace the installed
app's source identity.

Before staging, the replay control was unavailable after closing the preceding
completed video result. Relaunching the same installed app restored it, with no
data reset or code change. Record this as a pre-submission UI observation with
an undiagnosed cause; it was not an identification retry. No restart occurred
during the measured identification.

Timing starts at Identify and excludes import, file preparation and physical
microphone capture. Input hashes attest the reviewed WAV, not the app's final
prepared request or contextual fields, which were not retained. A complete
observer window is not an exhaustive provider-call or billing ledger.

The new packet is frozen outside Git with directory mode 0700, file mode 0600
and retention through 22 October 2026. Verification checked input and prior
packet hashes, window readiness/completion/separation, event counts, app/model/
backend identity, timing arithmetic and cost calculations. Documentation, JSON,
links and required recursive functions/scripts formatting were checked. Runtime
code was unchanged, so no new build or native/backend test suite was run; the
previous full native result remains 4,293 tests with no failures. No deployment,
direct-evaluator live run or external publication occurred.

Next, independently review the source/segment identity for this disagreement and
preserve the earlier ambiguous description mismatch. Expand reviewed paired and
ambiguous examples, including video with meaningful companion audio, before
changing prompts or judging another provider against these observations.

Follow-up, 22 September: the
[source and local model review](./identification-audio-reference-review-2026-09-22.md)
verified the preparation chain but left species identity unresolved. BirdNET
favored another species in the complete windows. The original measurements,
answer, provisional reference and frozen JSON above remain unchanged.
