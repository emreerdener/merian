# Identification measurement checkpoint

Date: 22 September 2026\
Status: Two finished app results; partial telemetry\
Route: Ordinary production identification with normal server selection

The same two photos used in the
[first live benchmark](./identification-production-app-benchmark-2026-09-22.md)
were submitted once each after the measurement infrastructure reached
production. Both reached finished result screens. One valid live record confirms
the Gemini model, token usage, app source and backend source fingerprint.
Recording failures and missing server timings prevent calling this a complete
measurement baseline.

The
[sanitized results](./identification-evaluation-evidence/2026-09-22-exploratory/production-app-measured-results.json)
retain the observed data and unknowns. The original benchmark remains unchanged.

## Results

| Case            | Visible result                   | Match label    | Observed model | Total app pipeline |
| --------------- | -------------------------------- | -------------- | -------------- | -----------------: |
| `c0001`, flower | Blowball, _Taraxacum officinale_ | Possible match | Unknown        |            Unknown |
| `c0002`, cat    | Tuxedo, _Felis catus_            | Strong match   | Gemini 2.5 Pro |           27.115 s |

The flower previously returned Rough Hawkbit, _Leontodon hispidus_. Neither
outcome has an independently verified reference. The difference is a consistency
observation, not evidence that either answer is correct. The cat again agrees
with its provisional _Felis catus_ species reference; the display name does not
establish a breed or pedigree. Neither result was manually confirmed or
corrected.

The cat's HTTP response was 200 and reported fresh delivery. Its record
contains:

- Requested and returned model: `gemini-2.5-pro`.
- Prompt tokens: 2,711; candidate tokens: 609; thinking tokens: 2,326; total:
  5,646. Cached and tool token counts were unavailable.
- Client transfer plus server interval: 26.497 s. This is not provider-only
  inference time.
- Response to first-result state: 0.029 s; postflight: 0.298 s; total app
  pipeline: 27.115 s. The separate rendered-frame diagnostic was 27.205 s.
- Conservative observed-primary-attempt estimate: **USD 0.0508025**, about **5.1
  cents**, using the reviewed same-day pricing snapshot. This includes
  thinking/output and uses the highest reviewed input rate without a cache
  discount. It excludes other attempts, optional enrichment, storage and other
  charges; total scan spend and billed cost remain unknown.

The cat pipeline was 4.728 s longer than its earlier 22.387 s observation. There
is only one observation per case in each run, the original model was unknown,
and the exact encoded provider payload was not hashed. This difference does not
establish a latency regression or a model comparison.

## App and deployment identity

The
[production deployment](https://github.com/emreerdener/merian/actions/runs/35793015142)
and its
[deploy job](https://github.com/emreerdener/merian/actions/runs/35793015142/job/106967866564)
succeeded for `bcc7ef8de53cefaa04bed81cb32adf7de877bf9a` before either scan. The
merged source had passed 4,277 local native unit tests and four critical UI
tests; the UI tests required a clean disposable simulator. The hosted backend
candidate gate also passed for the merged SHA.

An incremental Debug build from that clean commit was installed over the
existing app on the iPhone 18 Pro simulator running iOS 27.0. It remained
version 1.0.3, build 275. Its installed plist reported the correct source
revision, `clean` state and source fingerprint
`b2a209c666d63c9d6411cb6f9f7dbc4fb8253545c41c0b534cf430e157d70c1a`. The cat's
native response record independently retained those same app fields. The local
build result is
`.artifacts/local-ios/75ecce56ca8e4ed9abaf417a684673e1.xcresult`.

The cat response reported backend bundle fingerprint
`05aedfe76acc8d8bcee71f5ebf0f9de22590e79715e6cc80f1f4ab6032576558`, matching the
generated identification runtime fingerprint in the deployed source. This
fingerprint does not attest database or environment state. Missing live metadata
for the flower is not filled from the cat's response.

## Execution and recording limits

Execution used two sequential app submissions with no manual retries, provider
override or overlapping live observation windows. The owner completed the
required consent screen after the local test run. Both original asset hashes
were verified; each photo used the normal picker and default crop. Crop
confirmation submitted each request automatically. An original image hash is not
a hash of the resulting encoded provider payload.

Both 120-second live observers ended with `observer_stopped_or_unavailable`,
rather than `window_completed`:

- The flower window retained only its preflight event. Its visible result is
  recorded, but HTTP status, exact model, usage, latency and cost are unknown. A
  bounded attempt to recover already-emitted measurements from the saved OS log
  returned no valid records. The flower was not resubmitted.
- The cat window retained seven valid events, including its structured
  diagnostic record and completed pipeline timing, before failing to close
  normally. These events are usable observations, but the window does not prove
  complete coverage of requests or billing.

Between cases, a temporary native logging utility emitted seven invented
measurements without networking or account operations. A separate 30-second
observer captured all seven and ended normally. Those synthetic values are
excluded from every live count, result and estimate. This check did not
reproduce or repair the live-window failure.

The cat record's `serverTimingMs` was empty, leaving provider, total Edge and
other Edge durations unknown. The projection does not distinguish an absent
header from rejected timing syntax. A separate unauthenticated GET returned 401
with an accepted-format `auth` timing header and no response body was read; it
does not establish the header contents of the successful identification. The
causes of the missing timing spans and failed live observation windows remain
unconfirmed.

## Next checkpoint

This verifies normal identification plus one live model/usage/source record. It
does not establish reliable automated capture, biological accuracy, confidence
calibration, p95 latency or provider superiority.

Before expanding paid experiments, reproduce and correct recorder completion and
dropped-event behavior using synthetic log traffic, and trace why the successful
identification's timing spans were unavailable. Then validate a bounded repeat.
Do not silently retry these cases or replace their unknowns.

Detailed private evidence remains outside Git with retention through 22 October
2026. Repository evidence contains the allowlisted measurements and small
visible outcome projection, without media, raw response bodies, raw logs,
account data, coordinates or credentials. The
[app measurement guide](../development-guides/21-identification-app-measurement.md)
owns the recording procedure.
