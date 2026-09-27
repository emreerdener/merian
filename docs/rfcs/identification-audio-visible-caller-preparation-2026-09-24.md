# Audio candidates with visible source animals

Date: 24 September 2026\
Status: two exploratory candidates prepared; exact-media owner review pending

Later on 24 September, the owner completed the review and both cases ran in the
[separate app benchmark](./identification-audio-visible-caller-app-benchmark-2026-09-24.md).
The preparation checkpoint and its pending-state evidence below are preserved.

Two new audio candidates have separately retained video context for checking the
source labels: a pika and a rooster. This follows the
[disputed-reference review](./identification-audio-disputed-reference-review-2026-09-24.md).
The improvement is **more reviewable reference evidence**. Neither audible
species is independently verified, and no identification experiment has run.

The
[sanitized preparation record](./identification-evaluation-evidence/2026-09-24-audio-visible-caller-preparation/preparation.json)
binds the source selection, audio files, visual review, technical checks and
private freeze. It records two candidates, zero admitted cases, zero app
submissions and zero provider calls. The existing
[exploratory procedure](../../services/supabase/scripts/identification_evaluation/README.md#automated-exploratory-runs)
owns admission; this record does not change that procedure or runtime code.

## Selected recordings

| Case / group      | Source and provisional reference                                                                                                        | Fixed selection                       | Exact-audio review reel |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- | ----------------------- |
| `c0025` / `g0025` | [NPS: Call of the Pika](https://www.nps.gov/media/video/view.htm?id=5833D73D-CDF3-4B07-A008-D668ADCD51D5), _Ochotona princeps_          | Source 16–26 s; 10.000 s input        | 0.000–10.000 s          |
| `c0026` / `g0026` | [Benchill: Rooster crowing](https://commons.wikimedia.org/wiki/File:Rooster_crowing_small.ogv), domestic chicken within _Gallus gallus_ | Complete decoded audio; 5.424 s input | 11.000–16.424 s         |

The NPS source identifies the pika and supplies timed call captions at 18–19 and
23–24 seconds. Its page credits NPS and identifies qualifying NPS media as
public domain. The rooster recording is marked as the creator's own work and
released worldwide into the public domain, with an unrestricted-use fallback.
Credit: National Park Service, Mount Rainier National Park; Benchill, Wikimedia
Commons. These rights checks cover the listed recordings for evaluation; model
training is outside this preparation's scope.

The source pages, listed downloadable renditions, crop rules and case order were
recorded before media downloads or predictions. The pika uses the source's 720p
MP4; the rooster uses Wikimedia's listed 360p QuickTime rendition. Their
downloaded-byte hashes identify those public renditions, not original camera
files. Raw downloads and temporary decodes were removed after preparation.

Four sampled stills show a round-eared mammal on rocks and a rooster, consistent
with the source descriptions. One rooster still shows an open beak. These
observations provide visual context; sampled images cannot verify which animal
produces a particular sound, continuous synchronization, source editing or
absence of other callers. The assistant has not listened to the audio.

[Smithsonian's chicken account](https://nationalzoo.si.edu/animals/chicken)
identifies domestic chicken as _Gallus gallus domesticus_, a subspecies of
_Gallus gallus_. The candidate taxonomy normalizes that label at species rank;
agreement would not establish a breed or distinguish domestic from wild status.
The NPS source supplies the pika name mapping. These name accounts were read
through web retrieval; the scripted source-page checks retain hashes for the two
recording pages and the pika captions. Name mappings and visual resemblance do
not establish an independently adjudicated acoustic reference.

## Preparation and verification

Direct `afconvert` decoding produced mono 44.1 kHz PCM16. The selected samples
were written into WAV containers with only `fmt` and `data` chunks. No gain
adjustment, denoising, time stretching or result-guided segment search was
applied. Neither prepared WAV is digital silence or contains full-scale PCM
samples. This technical check does not prove audibility or species information.

The 16.424-second listening reel contains the exact input PCM, separated by one
second of digital silence; no speech or tones were added. Separate cropped MP4s
and sampled PNGs support reference review. Those MP4s are re-encoded, so use the
WAV reel for exact input listening. In particular, the rooster review video is
5.400 seconds while the complete decoded input is 5.424 seconds. Both artifacts
retain their actual durations; the review video is not byte-identical audio.

Existing evaluator helpers passed input/reference structure, taxonomy mapping,
actual WAV containers, media budgets and request preparation for both cases.
Four profile requests were prepared in memory with network and environment
access denied. This was **not corpus preflight or inference**. No request body
was retained. Prepared requests contain one audio asset each, no visual assets,
empty observation text and null region/month context. Labels, captions and
review imagery remain outside model input.

Tooling source was `8c831e90fafe582a2cce7bc22ab63a17d0c507ac`, with pending
documentation changes; its evaluator graph digest was
`21bee0b93dc9004ed5e6697f2790eaa2c45c7810f70a64eef0d115719f5c79d0`. Local
request digests do not attest a future app request or deployed backend. Exact
source, WAV and PCM checks found no matches against the retained audio
references for `g0011` and `g0013`–`g0024`, or between the new cases. Acoustic
near-duplicate review is still pending. All derivatives of each recording stay
in its single development group. Public-model training exposure is unknown.

## Review and next execution

The owner should listen to the exact reel and inspect the two cropped reference
videos. Confirm whether the calls are audible, whether any speech, spoken labels
or personal information is present, and whether the visible animals appear to
produce the calls. Flag repeated content or any uncertainty by clip and
timestamp. Source-page licensing review is complete; actual decoded-media
eligibility is not. Earlier listening confirmations covered different files.

This review does not require the owner to certify species. If identity or the
caller relationship remains uncertain, retain a provisional or null reference
and keep the uncertainty in the report. Known source identity must not force
species-level certainty from insufficient audio. Independent biological review
is needed for formal accuracy qualification, not for solo exploratory admission.
Formal progress remains **0/60 development and 0/240 held-out groups**.

After content review, create a separate admitted packet and run canonical
offline preflight. The pending app plan permits at most two sequential first
submissions through ordinary Gemini routing with `audio-minimal-v1` context. It
sends only audio, retains every first outcome, allows no manual retries and uses
separate 120-second measurement windows with 30-second shutdown grace. Check the
actual app/backend identity before execution. No comparison-secret activation or
reuse of consumed assignments is needed. Keep the existing controls and disputed
cases in their diagnostic reports; this small set cannot establish model
accuracy, confidence calibration or provider-switch readiness.

## Retained evidence

The private packet contains 29 frozen files with directory/file modes 0700/0600
and retention through 24 October 2026. Its freeze SHA-256 is
`3ab97dbbbcac2f3ce43330ba1c15a6472bae598c8e87c4fd64eb2198c87ba84e`. The
listening reel hash is
`9233f305759d609b0092a63978e00a09c7f7522457ffd408732454bd4268785c`. All 55 files
in the two earlier preparation packets and disputed-reference audit passed
unchanged-hash checks. New assets, reel segments, reference video hashes,
selection order and pending admission state were verified. A read-only contract
review found no material admission or label-separation blocker.

Documentation formatting and local links are checked at handoff. No runtime
suite was required for this evidence-only addition. Media and detailed curation
remain outside Git; no credentials, account identifiers, precise coordinates or
provider response bodies are included in repository evidence.
