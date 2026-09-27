# Disputed audio reference review

Date: 24 September 2026\
Status: source provenance verified; audible species remain unresolved

The two disputed animal clips in the
[V2 app benchmark](./identification-audio-confidence-v2-app-benchmark-2026-09-24.md)
are the same files covered by the earlier source reproduction audit. There is no
detected source-to-staged-input mix-up. The source and returned taxon names are
distinct species, so synonym handling does not resolve either disagreement. This
review made **zero new app submissions and zero provider calls**.

## Findings

| Case    | Source reference                     | Earlier ordinary-context result                  | Fixed-context V2 result                         | Prepared duration |
| ------- | ------------------------------------ | ------------------------------------------------ | ----------------------------------------------- | ----------------: |
| `c0019` | American Robin, _Turdus migratorius_ | Northern House Wren, _Troglodytes aedon_; Strong | Belted Kingfisher, _Megaceryle alcyon_; Strong  |           3.527 s |
| `c0022` | Pig Frog, _Lithobates grylio_        | Green Frog, _Lithobates clamitans_; Strong       | Pacific Tree Frog, _Pseudacris regilla_; Strong |           2.090 s |

The current NPS pages still label the recordings
[American Robin](https://www.nps.gov/subjects/sound/sounds-american-robin.htm)
and [Pig Frog](https://www.nps.gov/subjects/sound/sounds-pigfrog.htm), and still
link the exact media URLs retained in the preparation. The
[earlier diagnostic](./identification-audio-rain-diagnostic-2026-09-24.md)
already downloaded those MP3s and reproduced their complete prepared WAV and PCM
samples exactly at approximately 05:56 UTC. This review reused that frozen
evidence, rechecked the public page links, and verified its exact file bindings
through the later V2 assets, simulator-staging records and completed results. It
did not download or decode the recordings again.

NPS maps
[American Robin](https://www.nps.gov/mora/learn/nature/bluebirds-robins-thrushes.htm)
to _Turdus migratorius_ and
[Belted Kingfisher](https://www.nps.gov/grca/learn/nature/belted-kingfisher.htm)
to _Megaceryle alcyon_. The American Museum of Natural History separately lists
[Pig Frog](https://amphibiansoftheworld.amnh.org/Amphibia/Anura/Ranidae/Lithobates/Lithobates-grylio)
as _Lithobates grylio_ in Ranidae and
[Pacific Tree Frog](https://amphibiansoftheworld.amnh.org/Amphibia/Anura/Hylidae/Pseudacris/Pseudacris-regilla)
as _Pseudacris regilla_ in Hylidae. The frozen pig-frog reference already
accepts _Rana grylio_; that historical genus name does not make _Pseudacris
regilla_ an equivalent answer. These accounts establish name mappings, not which
animal is audible in either recording. These four nomenclature pages were read
through web retrieval during this review, separately from the scripted
file-binding audit. Their URLs and reviewed mappings are retained; exact HTML
hashes are retained only for the two sound-gallery pages.

The earlier offline processing audit produced 2.300 seconds for robin and 1.620
seconds for pig frog. The four relevant WAV, resampling and audio-processing
source files still match that audit's hashes. These are direct-helper results
from canonical WAV inputs, not measurements of the exact media sent by the app
to Gemini. Clip length and trimming therefore remain context for investigation;
this review establishes neither lost identifying cues nor a processing cause.

Reviewing a source page's labels does not create a biological listening review.
The assistant has not listened to or independently identified these sounds.
Different context and confidence contracts also prevent treating the two app
runs as a controlled repeatability or improvement experiment.

## Decision and next step

Retain both source labels as **provisional** and preserve every historical
prediction. Keep these cases available for diagnosing behavior, but exclude them
from a future species-quality decision set until their references are
independently adjudicated. Do not relabel a case to whichever model answer was
returned, or tune confidence bands against these two disputed labels.

The audit's `futureUse` and denominator fields document this case-selection
decision. They do not implement a new evaluator gate: a future frozen corpus and
run plan must apply it explicitly. Existing benchmark records, corpus schemas,
production assignment and thresholds remain unchanged.

For the next useful quality experiment, first prepare a small additional audio
set with documented, independently supportable species references and sufficient
recording context for review. Keep the reviewed non-animal controls and these
disputed examples in a separate diagnostic report. The existing solo-owner
[exploratory procedure](../../services/supabase/scripts/identification_evaluation/README.md#automated-exploratory-runs)
can continue with provisional or absent labels; it does not require pretending
that formal accuracy has been established. Formal progress remains **0/60
development and 0/240 held-out groups**, with zero independent biological
reviewers recorded for these cases. A second classifier alone would add another
prediction, not independently verify a reference.

## Evidence and checks

The
[sanitized audit](./identification-evaluation-evidence/2026-09-24-audio-disputed-references/audit.json)
binds the earlier source/processing records, both app reports, the current NPS
page hashes, source and input hashes, V2 staging records, name authorities and
future-use decision. All **179 files** across the preparation, first app run,
diagnostic and completed V2 freezes passed hash checks before and after this
audit. The new private freeze covers two files, with hash
`f6abee77a6473e55d93602a2600d99d1467a889cafa75c69a21430d200fa0a67`, private
directory/file modes 0700/0600 and retention through 24 October 2026.

Exact provider request bytes and biological identity are not attested. No
historical result, reference, frozen input or runtime implementation was
changed. Raw HTML, media downloads, credentials, account identifiers and
provider response bodies were not retained by this audit. Documentation
formatting and local links were checked; no runtime suite or paid experiment was
needed for this evidence update.
