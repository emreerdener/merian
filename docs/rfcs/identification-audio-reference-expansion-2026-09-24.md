# Audio source verification and next dataset preparation

Date: 24 September 2026 (America/Chicago; retained timestamps are UTC)\
Status at preparation: three original inputs reproduced exactly; six new
candidates prepared; owner listening review pending

Follow-up on 24 September: the owner completed the exact reel review, all six
cases were admitted to a separate exploratory packet, and canonical offline
preflight passed. The
[new six-audio benchmark](./identification-audio-expansion-app-benchmark-2026-09-24.md)
records the first ordinary-app results. The preparation checkpoint below and its
frozen record retain their earlier pending-review state.

The raven, elk and tree-frog source audit found no source-file or preparation
mix-up. Fresh downloads match the original source hashes, and decoding them
again reproduces the original input WAVs and PCM samples exactly. **Their
biological identity remains unresolved.** This verifies which recordings the
[completed processing benchmark](./identification-audio-processing-comparison-completed-2026-09-23.md)
used; it does not establish that the source species labels are correct.

Six additional exploratory candidates are prepared for review. The
[sanitized record](./identification-evaluation-evidence/2026-09-24-audio-reference-expansion/review-and-preparation.json)
binds their source records, proposed references, technical checks, listening
reel and private freeze. This checkpoint made zero identification requests and
admits zero new cases. Production routing and the completed benchmark are
unchanged.

## What the source audit establishes

The current NPS pages still link the same recordings and retain the labels
[Common Raven](https://www.nps.gov/subjects/sound/sounds-common-raven.htm),
[Elk](https://www.nps.gov/subjects/sound/sounds-elk.htm) and
[American Green Tree Frog](https://www.nps.gov/subjects/sound/sounds-green-treefrog.htm).
For `c0013`–`c0015`, verification checked the exact page-to-media URL,
downloaded bytes, prescribed leading segment, complete prepared WAV and decoded
PCM. Each input hash also matches its pair in the original comparison
preparation.

The canonical preparation digest matches the completed benchmark's binding. All
24 files in the original six-audio preparation freeze passed verification before
and after this audit. No frozen input, result or earlier review was rewritten.
The temporary source downloads and recreated WAVs were removed after comparison.

This rules out those specific provenance and preparation errors. It does not
verify an audible species, prove the absence of other animals, establish general
processor correctness or independently audit the later provider response. The
source names remain provisional. Neither the source captions nor a model's
confidence resolves the disagreements, and no new classifier was used as a
reference reviewer. The earlier cardinal case also remains unresolved.

## Six additional candidates

The [NPS Sound Gallery](https://www.nps.gov/subjects/sound/gallery.htm)
identifies its listed audio files as public domain and downloadable, with
appropriate credit requested. Credit: National Park Service; individual
recording credits remain on the linked source pages. Photos and other page
assets were not used.

The selection broadens the exploratory set with two bird recordings, one mammal,
one amphibian and two proposed non-animal controls. Species names below are
source-based candidates, not reviewed truth.

| Case / group      | Source recording                                                               | Proposed reference          | Input duration | Review reel interval |
| ----------------- | ------------------------------------------------------------------------------ | --------------------------- | -------------: | -------------------- |
| `c0019` / `g0019` | [American Robin](https://www.nps.gov/subjects/sound/sounds-american-robin.htm) | _Turdus migratorius_        |        3.527 s | 0.000–3.527 s        |
| `c0020` / `g0020` | [Canada Geese](https://www.nps.gov/subjects/sound/sounds-canada-geese.htm)     | _Branta canadensis_         |        3.239 s | 4.527–7.766 s        |
| `c0021` / `g0021` | [Coyotes](https://www.nps.gov/subjects/sound/sounds-coyotes.htm)               | _Canis latrans_             |        9.927 s | 8.766–18.692 s       |
| `c0022` / `g0022` | [Pig Frog](https://www.nps.gov/subjects/sound/sounds-pigfrog.htm)              | _Lithobates grylio_         |        2.090 s | 19.692–21.782 s      |
| `c0023` / `g0023` | [Rain](https://www.nps.gov/subjects/sound/sounds-rain.htm)                     | Proposed weather control    |        4.963 s | 22.782–27.745 s      |
| `c0024` / `g0024` | [Chainsaw](https://www.nps.gov/subjects/sound/sounds-chainsaw.htm)             | Proposed mechanical control |        5.407 s | 28.745–34.153 s      |

The name mapping uses NPS accounts for
[robin](https://www.nps.gov/mora/learn/nature/bluebirds-robins-thrushes.htm),
[Canada goose](https://www.nps.gov/hafe/learn/nature/ducks-geese-and-waterfowl.htm)
and [coyote](https://www.nps.gov/grca/learn/nature/coyote.htm), plus the
American Museum of Natural History's
[pig-frog account](https://amphibiansoftheworld.amnh.org/Amphibia/Anura/Ranidae/Lithobates/Lithobates-grylio).
The frozen frog mapping recognizes _Lithobates grylio_ and _Rana grylio_. Name
authorities do not verify what is audible in these particular recordings.

The source pages, media URLs and first-ten-seconds rule were frozen before
downloading audio or obtaining any prediction. All six sources are shorter than
ten seconds, so their complete decoded audio is retained. Direct `afconvert`
decoding produced mono 44.1 kHz PCM16; Python rewrote the selected samples into
WAVs containing only `fmt` and `data` chunks. No volume normalization,
denoising, time stretching or result-guided selection was applied. The geese
input contains 20 full-scale PCM samples; this is recorded without repairing the
sound or claiming audible quality.

The six source URLs, downloaded-byte hashes and prepared PCM hashes are
distinct, with no exact source/PCM/input match to `g0011` or `g0013`–`g0018`.
Acoustic near-duplicate review remains pending. Recordings and their derivatives
retain one group each. Public training exposure is unknown; these candidates are
development-only exploratory evidence.

## Checks, review and next execution

Input structure, reference structure, taxonomy mappings, cross-packet
separation, actual WAV containers, media budgets and request preparation passed
the existing evaluation helpers. Twelve requests were prepared in memory across
the existing Gemini Flash/free and Pro profiles with network and environment
access denied. No request body was retained and no provider was called. This is
a technical asset/request check, **not a corpus preflight or a runtime
benchmark**.

The tooling source was commit `6b961a4e702fc06ec91cad624790cd36b52f2f2c`, with
pre-existing unrelated checkout changes, and evaluator graph
`04580a471394fd0777906c2318c502857499de5ccf4535f524a51cb78f679d01`. Prepared
requests contain opaque input assets, empty observation text and null
region/month context. Source names and proposed references stay outside the
model-input projection. These local request digests do not attest a future app
request or deployed backend.

The **34.153-second reel** preserves every input's PCM samples exactly,
separated by one second of digital silence. It is for review only. No speech,
tones or labels were added. Following the
[exploratory eligibility procedure](../../services/supabase/scripts/identification_evaluation/README.md#automated-exploratory-runs),
the owner must listen for speech, spoken labels, personal information, inaudible
targets, repeated content and animals in the rain/chainsaw controls. The
assistant cannot hear the clips in this environment. Earlier owner confirmations
do not cover these new inputs, and no completed eligibility assertions or
`corpus.json` have been created.

After that review, create a new admitted packet bound to this immutable freeze
and run the canonical offline preflight. An uncertain control must remain
unknown or be excluded with its reason before prediction. This listening review
does not require the owner to identify every species and does not qualify the
references for formal accuracy scoring. Formal progress remains **0/60
development and 0/240 held-out groups**, with zero independent biological
reviewers.

The pending ordinary-app plan allows at most six sequential first submissions,
one per admitted case, using normal Gemini routing and current processing. It
preserves all first outcomes, prohibits manual retries, requires actual app and
backend identity checks, and uses separate 120-second passive observation
windows with 30-second shutdown grace. Stop on an uncertain submission or
unexpected identity. The consumed processing-comparison assignments are not
reused; this dataset preparation does not require reopening the hosted
comparison setting. Fresh pricing evidence is required for any new estimate;
otherwise cost remains unknown. No new run has started.

## Evidence retention

The new private packet contains 29 frozen files, with directory mode 0700, file
mode 0600 and retention through 24 October 2026. Its freeze hash is
`f22d71d787ea593e6daab38f735311b40084dfa0c8e6b4a0e6a341c85bc65532`. The
listening reel hash is
`b524918a5e55dc641462854c94c85a8c347d43ef888156852cce269bedf37460`. Original
packets retain their earlier retention dates. Source downloads and temporary
decodes were removed; reproducible preparation/check helpers and public-source
digests are retained privately. The repository record contains no media, account
or scan identifiers, credentials, raw coordinates or provider response bodies.

All frozen-file hashes, reel segments, source/input reproduction and preparation
bindings passed. No native or backend runtime suite was rerun for this
evidence-only change.
