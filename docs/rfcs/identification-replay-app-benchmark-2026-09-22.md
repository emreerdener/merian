# Describe timing verification and first controlled video benchmark

Date: 22 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: Describe repeat and first video result measured; standalone audio awaits
listening review

The repaired Describe path recorded its first live tap-to-render measurement. A
five-second public-domain video then completed the normal Gemini workflow
through the new Debug simulator replay tool. Both first outcomes agreed with
their provisional genus references. The
[sanitized results](./identification-evaluation-evidence/2026-09-22-media-replay/app-results.json)
retain the measurements, source identities, input digests and evidence hashes.

| Case    | Input                                                    | Visible result                               | Tap to first frame | App pipeline | Provider await | Total Edge | Primary estimate |
| ------- | -------------------------------------------------------- | -------------------------------------------- | -----------------: | -----------: | -------------: | ---------: | ---------------: |
| `c0009` | Exact repeat of frozen mushroom description              | Fly Agaric; _Amanita muscaria_; Strong match |           23.136 s |     20.573 s |       18.287 s |   19.509 s |     USD 0.032315 |
| `c0012` | Five ordered video snapshots with silent companion audio | American Bison; _Bison bison_; Strong match  |           24.108 s |     23.565 s |       16.751 s |   21.022 s |     USD 0.031895 |

The description is a repeat of the
[earlier case](./identification-description-app-benchmark-2026-09-22.md), not a
new observation group. Its reference supports _Amanita_; the video reference
supports _Bison_. Both results named a species beyond that reference rank, so
species accuracy remains unassessed. Neither result was manually confirmed or
corrected. Formal progress remains **0/60 development and 0/240 held-out
groups**, with zero independent biological reviewers. Two successful outcomes do
not establish confidence calibration, repeatability or a latency distribution.

## Input preparation and admission

The bounded plan allowed at most three ordinary-app submissions, with no manual
retries or provider overrides. Two were performed: Describe, then video. The
third, standalone audio, was not admitted or submitted. Describe's unchanged
text and plan were frozen before its repeat; the video packet was separately
reviewed, preflighted and frozen before its first submission.

The video comes from the NPS
[Bison Outside Yellowstone library](https://www.nps.gov/yell/learn/photosmultimedia/vl_bisonoutsidepark.htm),
specifically **Bison leaving north entrance**, media ID
`F997403B-155D-451F-673AEB08BAA08E7A`. The source page marks this individual
asset public domain. The first candidate on that page was rejected during
curation because its wide view was dominated by the arch and distant animals; it
was never submitted. The selected clip's first five seconds provide a clearer
view of bison walking through the entrance.

Preparation used AVFoundation through macOS `avconvert`, with metadata filtering
enabled. The selected movie has one video track, one audio track, exactly five
seconds of duration and no asset-level metadata items. Ten decoded half-second
views were inspected for personal information and answer-bearing overlays. Five
ordered frames at the nominal 0.5, 1.5, 2.5, 3.5 and 4.5 second positions were
also decoded and reviewed for the offline packet. Frame extraction resolves to
actual source presentation timestamps near those positions; source hashes do not
attest the app's final inference bytes.

The companion audio was retained. Its canonical mono 44.1 kHz PCM16 decode
contained **220,500 samples, all zero**. This case exercises snapshots with an
included audio track, but supplies no evidence about useful audio/video fusion
or acoustic identification. The app sends prepared snapshots and companion WAV
to identification; the playback movie stays outside inference.

Offline preflight passed for one exploratory group, one provisional reference
and two prepared requests across the existing Gemini profiles.
`dispatchAuthorized` remained false; those requests were only a dry schedule.
Preflight initially rejected incorrect local asset identifiers and then a PNG
aggregate over the existing 5 MiB budget. Before freezing, identifiers were
corrected and the same reviewed frames were re-encoded as metadata-free RGB JPEG
at quality 90, totaling 1,091,597 bytes. No gate or runtime limit changed. These
offline review assets are separate from the app's own preparation of the frozen
replay movie.

## Measurement integrity

Both passive windows were ready before their single submit tap, did not overlap
and closed normally with collector exit code zero. Describe retained **six
events**, including `tap_to_first_rendered_frame_seconds`; video retained
**seven**. Describe still has no visual preflight marker, so that field remains
null. The earlier description report's missing measurements remain unchanged.

The installed iPhone 18 Pro / iOS 27.0 Debug app was version 1.0.3, build 275,
source revision `807b9af9964e3eba0b9d4212d7dc91d8945d4118`, dirty state and
fingerprint `82da4dc3da24a4de9ace2c2be1f2746144c7191cc9c26309fddfe9655db03cd5`.
Both fresh HTTP 200 responses reported requested/returned `gemini-2.5-pro`,
valid provider/Edge spans and unchanged backend fingerprint
`05aedfe76acc8d8bcee71f5ebf0f9de22590e79715e6cc80f1f4ab6032576558`.

Describe's initial clipboard paste failed without entering text. Native typing
then completed, the full text was visually checked, and switching mode and back
exposed the submit button. No category chip was selected. Video was staged
through **Debug replay → Stage video sample**, followed by the normal manual
**Identify** action. Preparation/import preceded that tap and is excluded from
its latency, as is physical camera capture. These runs retain neither app
context nor complete request payloads; prepared media hashes are not full
request attestations.

The two known primary-attempt upper estimates sum to **USD 0.064210** using the
reviewed 22 September pricing snapshot, including thinking at the highest
reviewed rates and without a cache discount. Optional enrichment, unobserved
attempts, transport, storage and total billed cost remain unknown. The observer
is not a complete provider-call or billing ledger.

## Pending audio and next work

The NPS
[Northern Cardinal call](https://www.nps.gov/tont/learn/nature/birds.htm) was
prepared as a ten-second mono 44.1 kHz PCM16 WAV, with a compact listening copy.
The source transcript identifies a bird call, but the assistant's tool reported
that audio input is unsupported. No listening review is claimed. The owner was
asked to confirm that the selected segment contains no human speech, spoken
species label or personal information. Until that check is completed, `c0011`
remains unadmitted with zero submissions and no audio result. This follows the
corpus eligibility rule, rather than an additional spend or deployment approval
requirement.

After audio eligibility is established, freeze a new input/run packet and record
its first ordinary-app outcome. Then expand ambiguous examples and paired
evidence, including video with meaningful companion audio. Keep Gemini unchanged
and preserve the previous ambiguous non-biological description mismatch.
Physical-device capture and independently reviewed accuracy remain separate
work.

Private evidence is frozen outside Git with directory mode 0700, file mode 0600
and retention through 22 October 2026. Verification checked all input-freeze
hashes, observer completion and separation, event counts, app/backend/model
identities, timing arithmetic and primary-cost calculations. A fresh Debug
simulator build passed; its result bundle is
`.artifacts/local-ios/73d47a65473f4cd0b475c7e291c1a815.xcresult`. No runtime
code changed during this run, so the earlier 4,293-test native result remains
the implementation check; native/backend suites were not rerun. Documentation,
JSON formatting, recursive functions/scripts formatting and diff checks passed.
No backend deployment, direct-evaluator live run or external publication
occurred.
