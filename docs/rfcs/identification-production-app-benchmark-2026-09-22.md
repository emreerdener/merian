# First live identification benchmark

Date: 22 September 2026\
Status: Two normal app submissions completed; exploratory evidence\
Route: Existing production identification workflow with normal server selection

Both prepared photographs reached a finished identification screen. This records
their first outcomes and client timings through the real app, following the
[preparation record](./identification-exploratory-benchmark-2026-09-22.md). It
is an operational baseline, not a biological accuracy or provider comparison
score.

## Results

| Case            | Visible result                      | Match label    | App request | Total app pipeline | Reference assessment                      |
| --------------- | ----------------------------------- | -------------- | ----------: | -----------------: | ----------------------------------------- |
| `c0001`, flower | Rough Hawkbit, _Leontodon hispidus_ | Possible match |    27.450 s |           28.421 s | Unverified; not scored                    |
| `c0002`, cat    | Tuxedo Longhair, _Felis catus_      | Strong match   |    22.083 s |           22.387 s | Matches the provisional species reference |

Both identification HTTP requests returned 200, and both result screens were
observed. The cat comparison concerns _Felis catus_, without establishing a
breed or pedigree from the displayed name. Neither identification was manually
confirmed or corrected. The flower's source filename does not establish a
verified reference label.

The retained
[machine-readable results](./identification-evaluation-evidence/2026-09-22-exploratory/production-app-results.json)
contain the two outcomes, fourteen associated numeric events, input hashes,
observation-window identities and installed code-file hashes. They contain no
raw response bodies, account information, coordinates, sessions or image files.

## Execution

The owner approved the prepared photos, a four-call maximum and USD 10 budget,
then selected ordinary production app charges. Execution used two sequential app
submissions, one per photo, with no manual retry or profile override. Actual
provider invocation and internal retry counts are not exposed by this observer;
two app submissions are not an attested provider-call count. The ordinary
app/backend controls handled consent, admission, allowance reservation and
profile selection.

The app was version 1.0.3, build 275, on an iPhone 18 Pro simulator with iOS
27.0. Native tests had finished, and the app had been relaunched normally. UI
capture worked after the owner completed the Computer Use permission setup. The
app received limited library access to the two approved photos. Each was
selected through the normal picker and accepted with its default crop, which
automatically submitted it. No extra Identify action was sent. An optional
notification prompt between cases was dismissed.

The originals were metadata-stripped RGB PNGs, 1,024 by 768 pixels, from the
public-domain sources in the preparation record. Their hashes were rechecked
before execution. The app's normal crop and encode steps produce the submitted
payload; an original-file hash is not a hash of the exact provider input. No
label hint or description was added.

Two bounded observation windows used the previously checked numeric projection.
The first supplied events 0–6 for the flower. Its last event also observed the
cat's preflight during a short overlap; that duplicate observation is excluded
from the flower and aggregate counts. The second supplied events 0–6 for the
cat. Association follows the observed sequential UI actions, with one request
and one completed pipeline per selected event group. The observer submitted no
requests, and both windows ended normally.

## Measurement boundaries

- **App request** includes client transport and backend work. It is not
  provider-only inference time.
- **Total app pipeline** is the app's logged pipeline duration, including work
  around the request. It is not an independent measurement of when a person
  first saw the result.
- **Response to first-result state** was 0.035 s for the flower and 0.019 s for
  the cat. The separate rendered-frame metric remains a rendering diagnostic,
  not an interchangeable identification-completion clock.
- **Postflight** was 0.970 s and 0.304 s respectively. Preflight rounded to
  0.000 s in both logs; this does not establish zero work.
- No valid provider or Edge server-timing span was captured. Provider-only
  latency, exact model, token usage, billed cost, cache state and internal
  retries remain unmeasured. The configured route is Gemini, without a separate
  provider/model attestation in the captured telemetry.

The installed app's source revision, fingerprint and state fields all reported
`unavailable`. The result retains hashes of its `Info.plist`, executable and
Debug code library instead. Those identify inspected files; they do not recover
a source revision or establish a complete bundle or hosted-backend identity. The
earlier preparation receipt describes a different installation checkpoint and
must not supply missing provenance for this run.

## Interpretation and next use

The production photo path worked for both cases, with measured pipelines of
22.387–28.421 seconds. The cat agrees with its provisional species reference;
the flower remains an outcome for review. Two public images with one provisional
reference establish no formal accuracy rate, confidence calibration, stable p95,
provider ranking or training-data suitability. Prior model exposure to these
public examples is unknown.

Use this record to compare future observations of the app workflow while keeping
input, crop, build, model and measurement differences explicit. Expand with
reviewed examples before drawing quality conclusions. Audio, descriptions and
ordered snapshots from a five-second video remain untested here; that video
input is a sequence of image snapshots, not a raw video upload. Comparable
provider experiments also need observable model/deployment identity and provider
timing or usage evidence.

Subsequent implementation adds the
[app measurement instrumentation](../development-guides/21-identification-app-measurement.md)
for future runs, including a fix for plist processing overwriting build
provenance. This historical run retains its original unknown model, provider
timing, cost and source values; no results were rerun to populate them.

Original media and private numeric observation files remain in the controlled
temporary directory documented in the preparation record, with retention set to
22 October 2026. The sanitized repository result preserves this checkpoint
without retaining the media or raw application output.
