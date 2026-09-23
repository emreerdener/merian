# Two-description identification app benchmark

Date: 22 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: Two first results observed; two complete measurement windows; audio and
sampled-video coverage pending

Two source-derived descriptions completed the ordinary app workflow using Gemini
2.5 Pro. The mushroom answer agreed at the provisional reference's genus level,
but named a species beyond that reference. The non-biological control returned a
Strong match for a fungus. Preserve this mismatch when expanding the benchmark:
the control's text may not distinguish a pitted rock from a fungus, so it does
not establish an independently verified model error or an accuracy percentage.

The
[sanitized results](./identification-evaluation-evidence/2026-09-22-description-pilot/app-results.json)
retain both first outcomes, numeric observations, frozen input identities,
pricing and private-record hashes. This extends the
[six-photo benchmark](./identification-source-photo-app-benchmark-2026-09-22.md)
with a separate exploratory packet. Formal progress remains **0/60 development
and 0/240 held-out groups**; independent biological review count is zero.

## First results

| Case    | Reference             | Visible result                                            | Assessment                                                                   | App pipeline | Provider await | Total Edge | Primary estimate |
| ------- | --------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------------- | -----------: | -------------: | ---------: | ---------------: |
| `c0009` | Amanita genus         | Fly Agaric; _Amanita muscaria_; Strong match              | Genus agreement; species unassessed                                          |     17.848 s |       14.171 s |   16.553 s |    USD 0.0283225 |
| `c0010` | Non-biological source | King Alfred's Cakes; _Daldinia concentrica_; Strong match | Biological assertion contradicts the source reference; description ambiguous |     22.677 s |       19.586 s |   21.698 s |    USD 0.0354550 |

The source images were an
[FWS Amanita photograph](https://www.fws.gov/media/amanita-mushroom-toadstool)
and a
[USGS vesicular-basalt specimen](https://www.usgs.gov/media/images/vesicular-basalt-top-view).
Both individual pages mark their media public domain. Each image was decoded,
oriented and re-encoded as pixel-only RGB PNG for private visual review.
Descriptions were then authored from visible features and frozen before any
submission. They contain no expected genus/species name or copied caption. Only
the descriptions were entered into Describe; the images stayed in curation.

These are automatically authored descriptions of public images, not spontaneous
field notes. The small USGS image supports the source's subject classification,
but the derived text omits evidence that uniquely establishes a rock. Do not
silently rewrite that description, rerun it and replace the first result.
Neither displayed answer was manually confirmed or corrected. A future paired
image/text experiment must retain the source observation's group identity.

The two primary-attempt estimates sum to **USD 0.0637775**. They use the
reviewed 22 September pricing snapshot at the highest reviewed rates, including
thinking and without a cache discount. Optional enrichment, other attempts,
transport, storage and total billed cost remain unknown. Two cases do not
support a latency distribution or confidence calibration.

## Preparation and measurement integrity

Offline preflight passed with network and environment denied: two independent
description groups, two provisional references and four prepared requests across
the existing Gemini profiles. `dispatchAuthorized` remained false. Those four
requests were a dry schedule; the separate ordinary-app plan allowed two first
submissions with normal server selection and no manual retries.

| Frozen identity            | Value                                                              |
| -------------------------- | ------------------------------------------------------------------ |
| Corpus                     | `5c1d1bf18849bc7a5574aaba9a3dcf4c225ac12a391d23da71cc0afb54e24ea5` |
| Taxonomy                   | `8c4c86027e050c30c65146965dec0ae8c98f2bd91d7b7b4af7c709a8d22ea6be` |
| Preparation tooling commit | `a21a3a2d51d6ff5bc847506c1c3efe23e783aa09`                         |
| Preparation source graph   | `423b50d77257f287e853a8a90b141dc7e1d14cac4d33dce0c37e0b2e116f2598` |

The installed iPhone 18 Pro / iOS 27.0 Debug app retained version 1.0.3, build
275, source revision `6c7ba02ede0fa0884189f55b726bb4babf5966a5`, dirty state and
fingerprint `3ad8e9f3c0e73234a78e743652cd9ac88fb93414f6e348c85148abddf213d812`.
Both responses reported requested/returned `gemini-2.5-pro` and backend
fingerprint `05aedfe76acc8d8bcee71f5ebf0f9de22590e79715e6cc80f1f4ab6032576558`,
matching the preceding photo run. No runtime change or deployment was made.
These fingerprints do not independently attest database or environment state.

Each passive window was ready before submission, requested 120 seconds plus 30
seconds of shutdown grace, and closed normally with **five events**, fresh HTTP
200 and valid provider/Edge spans. Windows did not overlap. The first input
initially hid the submit control while text was focused; switching capture mode
and back restored it without changing the description. The visible submit
control was then pressed once. Full text was visually verified for both cases;
no category chip was selected. App contextual fields and final provider payloads
were not retained or attested by the description hashes.

The two absent markers are explained by the current implementation:

- `preflight_seconds` logs visual encode/auth work in
  `InferenceLiveRequestService.dispatchVisual`; the nonvisual path does not emit
  it.
- `tap_to_first_rendered_frame_seconds` needs a start clock.
  [submitDescribeSolo](../../apps/ios/Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+DescribeSubmission.swift)
  does not supply `userPerceivedStart` to the nonvisual submission path. The
  shared first-render probe therefore has no clock to consume.

Both fields remain null. The five emitted events are HTTP timing, native
diagnostics, response-to-first-result state, postflight and total pipeline time.
Do not compare a reconstructed Describe tap-to-render value with the photo
metric. Collector completion does not prove exhaustive logs or provider-call
counts. The
[measurement guide](../development-guides/21-identification-app-measurement.md)
owns the procedure and metric definitions.

## Remaining audio and video work

The current app's photo pickers and external-file route accept images only.
[Audio capture](../../apps/ios/Merian/Features/Capture/Record/README.md) records
the live microphone;
[video capture](../../apps/ios/Merian/Features/Capture/Scan/README.md) records
the live camera. There is no existing normal-app local audio/video import route.
The passive observer currently supports simulators. Consequently this run made
**zero audio or video submissions and prepared zero audio/video assets**.

Two source candidates are recorded for follow-up: the
[NPS Northern Cardinal call](https://www.nps.gov/tont/learn/nature/birds.htm)
and the
[NPS bison video library](https://www.nps.gov/yell/learn/photosmultimedia/vl_bisonoutsidepark.htm).
Their actual sound and selected five-second clip still need decoded-media
privacy/answer-leakage review, reference/permission records and freezing before
admission. Source-page discovery is not a passed media preflight.

The recommended next slice is to supply Describe's missing start clock and
establish a controlled audio/video replay path before more automated paid runs.
That path should reuse existing preparation, submission, consent and admission
logic; keep CI offline and require deliberate ordinary-app submissions. Preserve
five ordered snapshots and actual companion audio. Playback video itself stays
outside inference. Keep source observations grouped when deriving multiple input
forms, and compare provisional references only at their supported rank.

For an immediate manual smoke check, the owner can instead use a physical
iPhone's normal microphone and five-second camera capture. That checks actual
capture behavior, but it does not inherit this simulator observer's numeric
evidence or reproduce prepared files exactly. Record its first visible result
and any manually measured duration separately; missing diagnostic values stay
unknown. Independent reviewers are not required for this exploratory check.

Private input and run evidence is frozen outside Git with directory mode 0700,
file mode 0600 and retention through 22 October 2026. Verification checked the
source freeze, five-event sets, window separation, source identities, input/UI
joins, timing arithmetic, pricing and cost calculations. Documentation and the
required recursive functions/scripts formatting gate were checked. No runtime
code changed, so native/backend suites were not rerun.
