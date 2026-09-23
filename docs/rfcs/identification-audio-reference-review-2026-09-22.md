# Audio reference disagreement review

Date: 22 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: Source and preparation verified; species identity unresolved

The follow-up to the
[first audio benchmark](./identification-audio-app-benchmark-2026-09-22.md) did
not resolve the species in case `c0011`, observation group `g0011`. The source
says **Northern Cardinal**, the original Gemini 2.5 Pro app result was **Wood
Thrush — Strong match**, and a local BirdNET diagnostic favored **Pyrrhuloxia**
in all three complete windows. Its padded final window favored **Pacific
Antwren**. Keep the case as an unresolved disagreement for development review.
No species label is promoted and no independently verified error is counted. The
[sanitized review results](./identification-evaluation-evidence/2026-09-22-audio-reference-review/review-results.json)
preserve the evidence separately from the original app results.

## Source and preparation audit

The NPS [bird page](https://www.nps.gov/tont/learn/nature/birds.htm), its
[individual recording page](https://www.nps.gov/media/video/view.htm?id=7CB8656C-0BCE-4AF6-AAA9-970DECB4B5FB),
and the original MP3's embedded title all identify Northern Cardinal. The saved
page points to the exact downloaded MP3. These are consistent records from one
source, not independent biological reviews.

Replaying the original preparation recipe from that frozen MP3 reproduced all
441,000 PCM16 samples of the ten-second, mono 44.1 kHz input exactly. The
earlier prepared WAV and metadata-free canonical WAV also contain identical PCM
samples. The final reviewed input remains
`6854410b4ec668ea78a02d728cd06d235088162794f7f6da425dcc6cbc06688f`. All 81 files
in the earlier preparation packet and all 11 files in the audio benchmark packet
passed their frozen hash/size checks.

This establishes the source-to-staged-input preparation chain. The final app
request bytes and context were not retained, so it cannot establish precisely
what Gemini received. Neither the assistant nor an independent biological
reviewer has verified the audible species. The owner's earlier listening
confirmation establishes eligibility, including absence of speech and personal
information.

## One local diagnostic

The official
[BirdNET-Analyzer](https://github.com/birdnet-team/BirdNET-Analyzer) release
`2.4.0` and its FP32 `V2.4` model ran in an isolated temporary Python
environment. Model and label hashes, dependency versions, source-file hashes,
arguments and the input were recorded before inference. The four-window protocol
was frozen before seeing predictions. The model was downloaded first; macOS
`sandbox-exec` denied network access during inference, with an access-denied
socket check before the run. The audio was not uploaded to another service.

The run used the exact reviewed WAV, the model's 48 kHz resampling and
three-second windows, zero overlap, sensitivity 1.0, and no location, season or
species shortlist. The last second was retained and padded with two seconds of
zeros. All 6,522 class scores per window were saved: 26,088 rows in total. The
CSV reports the real end of the last window as ten seconds, while the model
input includes padding. No inference retry, parameter tuning or further app
submission occurred. The
[official CLI documentation](https://birdnet-team.github.io/BirdNET-Analyzer/stable/usage/cli.html)
describes the analysis controls; the frozen protocol records the actual
settings.

| Audio interval       | BirdNET first-ranked species | First-ranked score | Northern Cardinal score | Wood Thrush score |
| -------------------- | ---------------------------- | -----------------: | ----------------------: | ----------------: |
| 0–3 s                | Pyrrhuloxia                  |             0.1190 |                  0.0004 |            0.0000 |
| 3–6 s                | Pyrrhuloxia                  |             0.7293 |                  0.0026 |            0.0000 |
| 6–9 s                | Pyrrhuloxia                  |             0.5044 |                  0.0152 |            0.0000 |
| 9–10 s, with padding | Pacific Antwren              |             0.3606 |                  0.0004 |            0.0001 |

These are model scores rounded to four decimals, not calibrated probabilities or
values comparable with Gemini's Strong match band. A displayed `0.0000` is
rounded, not proof of exact zero. The first window's leading score is below the
tool's ordinary 0.25 cutoff; retaining all classes deliberately disables that
filter. The padded tail has less recorded evidence than the full windows. All
four remain derivatives of the same observation, not four independent examples.

BirdNET provides another model opinion. It does not confirm either disputed
species, prove the source label wrong, establish Pyrrhuloxia as ground truth, or
locate the cause of the app's answer. Possible training overlap with this public
recording is unknown. Its local execution time is not an app-latency or provider
performance comparison. The model's documented license is CC BY-NC-SA 4.0; this
local research diagnostic adds no model dependency or production integration.

## Disposition and next work

- Keep the original source label provisional and mark the species review
  unresolved. Preserve the first Gemini answer and this diagnostic without
  changing earlier frozen records or selecting a more favorable retry.
- Retain this case as a useful source/model-disagreement example. Exclude it
  from verified-accuracy and confirmed-error denominators until biological
  adjudication resolves the exact segment. Formal progress remains **0/60
  development groups, 0/240 held-out groups, and zero independent reviewers**.
- Expand the exploratory audio set with clearer source-documented calls,
  difficult sounds and non-biological controls. Freeze eligibility, references
  and the run plan before new app submissions. Keep unresolved examples visible
  alongside that coverage.
- Keep Gemini and existing confidence/prompt behavior unchanged. One unresolved
  observation does not qualify another model or support a routing decision.

The new private packet contains the input, preparation reproduction, protocol,
model/labels, dependency record, all scores and summary. Its 17 files are frozen
under hash `b20d6172b537988699a4905fb238996e35702b37cafd0811bd05bba4c7beee35`,
with directory mode 0700, file mode 0600 and retention through 22 October 2026.
Only the sanitized summary and this report enter Git. There were **zero new
Gemini calls and zero new paid provider calls**.

Verification passed for all 109 files across the three freezes, exact
preparation reproduction, protocol/model/input hashes, network denial, all
per-window score counts and retained-summary consistency. Markdown formatting,
JSON/privacy checks, 222 relative links and diff checks passed. Both original
benchmark JSON files and the three pre-existing user changes remained unchanged.
No runtime code changed; native and backend suites were not rerun, and no
deployment or publication occurred.
