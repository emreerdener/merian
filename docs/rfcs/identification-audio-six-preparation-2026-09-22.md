# Six-audio identification packet preparation

Date: 22 September 2026 (America/Chicago; retained timestamps are UTC)\
Status at preparation: Six candidates prepared and technically checked; owner
listening review pending; no app submissions

Follow-up on 22 September: the owner completed the listening check. The
[six-audio app benchmark](./identification-audio-six-app-benchmark-2026-09-22.md)
records admission into a new packet and subsequent first submissions. The
preparation record below and its private freeze preserve the earlier checkpoint.

This expands the exploratory audio set after the
[unresolved source/model disagreement](./identification-audio-reference-review-2026-09-22.md).
Three source-labelled animal recordings and three proposed non-biological
controls are prepared. The existing input/asset validators and request builders
passed for all six candidates and both current Gemini profiles with network and
environment access denied. No provider was called. The
[sanitized preparation record](./identification-evaluation-evidence/2026-09-22-audio-six-preparation/preparation.json)
binds the files, references, technical checks, pending plan and private freeze.

**Zero cases are admitted at this checkpoint.** Source captions and technical
checks cannot complete the actual listening review. The earlier owner
confirmation concerned only `c0011`; it does not cover these new clips. The
[evaluation tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#automated-exploratory-runs)
requires review of decoded media before eligibility assertions. The assistant
cannot hear the audio in this environment, so the owner has a single listening
reel to review. Formal progress remains 0/60 development groups and 0/240
held-out groups, with zero independent biological reviewers.

## Source selection and intended coverage

The [NPS Sound Gallery](https://www.nps.gov/subjects/sound/gallery.htm)
explicitly identifies its listed clips as public domain and downloadable, with
appropriate credit requested. Each linked recording page provides a specific
source label and sound transcript. Credit: National Park Service; individual
recording credits remain on the source pages.

| Case / group      | Source recording                                                                         | Prepared duration | Proposed reference                                                   |
| ----------------- | ---------------------------------------------------------------------------------------- | ----------------: | -------------------------------------------------------------------- |
| `c0013` / `g0013` | [Common raven](https://www.nps.gov/subjects/sound/sounds-common-raven.htm)               |           5.747 s | _Corvus corax_, provisional species                                  |
| `c0014` / `g0014` | [Elk bugle](https://www.nps.gov/subjects/sound/sounds-elk.htm)                           |          10.000 s | _Cervus canadensis_, provisional species                             |
| `c0015` / `g0015` | [American green tree frog](https://www.nps.gov/subjects/sound/sounds-green-treefrog.htm) |           9.979 s | _Dryophytes cinereus_, provisional species                           |
| `c0016` / `g0016` | [Stream](https://www.nps.gov/subjects/sound/sounds-stream.htm)                           |           5.068 s | Proposed water control; check for incidental animals                 |
| `c0017` / `g0017` | [Thunder](https://www.nps.gov/subjects/sound/sounds-thunder.htm)                         |          10.000 s | Proposed weather control; check for incidental animals               |
| `c0018` / `g0018` | [Car alarm](https://www.nps.gov/subjects/sound/sounds-car-alarm.htm)                     |           9.979 s | Proposed mechanical control; check for speech and incidental animals |

The animal name mapping uses NPS authorities for
[raven](https://www.nps.gov/zion/learn/nature/raven.htm) and
[elk](https://www.nps.gov/grca/learn/nature/elk.htm), and the American Museum of
Natural History's
[tree frog account](https://amphibiansoftheworld.amnh.org/Amphibia/Anura/Hylidae/Dryophytes/Dryophytes-cinereus).
The frozen frog mapping recognizes both _Dryophytes cinereus_ and _Hyla
cinerea_. These name authorities do not verify the species audible in the chosen
segment. Source labels stay provisional, and a non-biological source description
does not establish that no animals are audible in the recording.

The six URLs, downloaded-byte hashes and prepared PCM hashes are distinct, with
no exact match to the earlier cardinal source/input. Listening review still
needs to check repeated content. Each full recording, selected segment and later
derivative retains its one group ID. The unresolved `g0011` case remains
separate and unchanged. Public-source training exposure is unknown.

## Preparation and listening review

Before fetching the recordings, the selection plan fixed the source pages and
the first-ten-seconds rule. Shorter sources use their full duration. No
classifier, result-guided segment selection, denoising, volume normalization or
time stretching was used.

Apple `afconvert` decoded each MP3 directly to mono 44.1 kHz PCM16. Python's WAV
writer retained the prescribed leading samples and created a container with only
`fmt` and `data` chunks. Input files have opaque asset names, empty observation
text, null context and no embedded source labels. Source/reference records
remain outside the model-input projection. Raw downloads and temporary decoded
files were removed after preparation; their source hashes and URLs are retained.
The elk and stream clips contain 43 and one full-scale PCM samples,
respectively; the remaining clips contain none. This was recorded without
repairing the sound or inferring its audible quality.

The **55.772-second listening reel** contains the exact prepared PCM samples,
with one second of digital silence between clips. No speech, tones or labels
were added. Byte comparison verified every segment against its standalone input.
The reel is for owner review only and is never submitted for identification.

| Reel interval   | Clip      |
| --------------- | --------- |
| 0.000–5.747 s   | Raven     |
| 6.747–16.747 s  | Elk       |
| 17.747–27.726 s | Tree frog |
| 28.726–33.793 s | Stream    |
| 34.793–44.793 s | Thunder   |
| 45.793–55.772 s | Car alarm |

The owner needs to flag human speech, spoken labels, personal information,
inaudible targets, repeated content and animal sounds in the three proposed
controls. This is an eligibility and suitability check, not a request to
independently identify each species. An uncertain or mixed control must remain
unknown, receive a supported reference in a new reviewed version, or be omitted
with its reason before prediction. A later biological answer on such a mixed
recording cannot automatically count as a false biological identification.

## Technical checks and bounded app plan

`parseEvaluationInput`, `validateInputSeparation`, `validateReference`,
`parseTaxonomy`, `prepareEvidence` and `assignmentFor` checked the candidate
input structure, source-independent references, actual metadata-free WAVs and
the existing Gemini request preparation. The private report retains only digests
and check results. Twelve requests were prepared in memory across Flash/free and
Pro/Pro; none were dispatched or saved as request bodies.

This was an input/asset check, **not the canonical corpus preflight**. No
`corpus.json` with completed eligibility assertions was created. After owner
review, create a new admitted packet referencing this immutable preparation
freeze, record the review scope and unchanged input hashes, and run the ordinary
offline `preflight` before any app submission. Keep the direct evaluator's
separate project/key, processor, pricing and spend controls intact.

The pending ordinary-app plan sets:

- At most six sequential first submissions, one per admitted case in the order
  above, using existing app access and ordinary charges. The earlier completed
  three-submission plan is not reused.
- Normal server selection of Gemini, no provider override, no expected names
  entered as evidence, no manual retries, and preservation of every first
  outcome, failure and unknown field.
- A separate 120-second passive observer window plus 30-second shutdown grace
  per case, readiness before Identify, and no overlapping windows.
- Stop on an uncertain submission or unexpected app/provider identity. Verify
  the installed app and backend identity for the actual run; the preparation
  commit does not attest them.
- Use a fresh reviewed pricing snapshot for optional primary-call estimates, or
  keep cost unknown. Six app submissions do not establish a provider-call count,
  total bill or guaranteed spending cap.

The source identity at preparation was commit
`bb6df5401ea855be33aa101623e9afdf1b76c1b0`, dirty with pre-existing unrelated
changes, and evaluator graph
`423b50d77257f287e853a8a90b141dc7e1d14cac4d33dce0c37e0b2e116f2598`.
Prepared-request hashes do not attest later app request bytes or contextual
fields. No runtime code, production routing or confidence policy changed.

The private packet has 24 frozen files, directory mode 0700, file mode 0600 and
retention through 22 October 2026. Its freeze hash is
`a9f33d2c482036c2b8d73a69269e0528d4f038697a7a497624626fa406602daf`. The reel's
hash is `c7f4ffce85abdc3020cbd648d6e627d4573da62e66be52a8f4bf4cd5aa250731`.
Preparation made zero app submissions and zero model calls. Technical and
documentation checks do not stand in for listening review or runtime results;
native/backend suites were not rerun for this evidence-only change.
