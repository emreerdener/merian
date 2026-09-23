# Six-photo identification app benchmark

Date: 22 September 2026 (America/Chicago; retained timestamps are UTC)\
Status: Six first results observed; six complete measurement windows

The
[prepared source-photo packet](./identification-source-photo-pilot-2026-09-22.md)
completed its bounded pass through the existing production app workflow. All
five biological results agreed with their provisional species references. The
mineral control was classified as non-biological. All six scans retained fresh
Gemini 2.5 Pro identity, usage, provider/Edge timing and app pipeline intervals.

The
[sanitized results](./identification-evaluation-evidence/2026-09-22-source-photo-pilot/app-results.json)
retain each first outcome and measurement, frozen source identities, pricing,
private-record hashes and sample limitations. This is an exploratory photo
benchmark. Source-backed references have zero independent biological reviews;
formal progress remains 0/60 development and 0/240 held-out groups.

## Results in the frozen execution order

| Case    | Visible result           | Reference assessment          | App pipeline | Provider await | Total Edge | Primary estimate |
| ------- | ------------------------ | ----------------------------- | -----------: | -------------: | ---------: | ---------------: |
| `c0002` | Bald Eagle               | Provisional species agreement |     16.131 s |       13.066 s |   14.859 s |     USD 0.030355 |
| `c0004` | Common Sunflower         | Provisional species agreement |     18.683 s |       15.945 s |   17.578 s |     USD 0.034435 |
| `c0007` | Saguaro                  | Provisional species agreement |     20.563 s |       16.921 s |   19.520 s |     USD 0.036385 |
| `c0001` | American Bison           | Provisional species agreement |     15.400 s |       12.915 s |   14.192 s |     USD 0.031045 |
| `c0003` | Monarch Butterfly        | Provisional species agreement |     18.249 s |       14.980 s |   17.293 s |     USD 0.033475 |
| `c0008` | Amethyst; NON-BIOLOGICAL | Non-biological agreement      |     13.882 s |       11.062 s |   12.492 s |     USD 0.026920 |

All five biological results displayed **Strong match** and the exact scientific
name in the frozen reference map: _Haliaeetus leucocephalus_, _Helianthus
annuus_, _Carnegiea gigantea_, _Bison bison_ and _Danaus plexippus_. None was
manually confirmed or corrected. These are five provisional agreements, not an
independently verified accuracy percentage or calibrated confidence evidence.
The control's displayed mineral name was not assessed; its reference tests only
whether the app avoids a biological identification.

All six app pipeline intervals ranged from **13.882 to 20.563 seconds**, with a
sample median of **17.190 seconds**. The five biological cases alone had a
median of **18.249 seconds**. Provider-await intervals ranged from 11.062 to
16.921 seconds; other Edge work ranged from 1.277 to 2.599 seconds. Provider
time includes SDK transport, and other Edge time is `edge_total - provider`.
Overlapping backend spans must not be summed. These intervals are not physical
camera-to-result measurements or a reliable latency distribution.

The six observed primary-attempt estimates sum to **USD 0.192615**, about 19.3
cents. Each estimate uses the existing reviewed 22 September pricing snapshot,
including thinking/output at the highest reviewed rate without a cache discount.
This sum covers those six observed primary attempts only. Optional enrichment,
other/unobserved attempts, storage, transport and the complete invoice remain
unmeasured; total billed cost is null.

## Execution and measurement integrity

The owner authorized the prepared ordinary-app pass using existing production
charges. Execution used six sequential submissions in the frozen order, one per
photo, with no manual retries, model override, overlapping observer windows or
new deployment. The existing account and consent were preserved. The six
prepared photos were added to the simulator's Photos library; earlier media and
app data were preserved.

Each default crop was visually checked before confirmation. The bison crop
trimmed part of its muzzle and rear while retaining the intended animal; no
manual crop adjustment was applied. Source-asset hashes identify the prepared
files, not the app's final crop, contextual fields or encoded provider payload.
Expected names and curation records were never submitted as observation text.

Each passive observer requested 120 seconds plus a bounded 30-second shutdown
grace and reported readiness before confirmation. All six windows closed
normally after approximately 128.5 seconds, retaining seven events each:
preflight, HTTP timing, native diagnostics, response-to-first-result state,
tap-to-first-rendered-frame, postflight and total pipeline time. Every native
record reported fresh HTTP 200, `timingStatus: valid` and both required spans.
No oversized rows were retained. Unprojected-row counts remain in the results;
complete windows do not prove exhaustive OS logging or provider invocation and
billing counts. Visible result screens were observed separately from the numeric
diagnostics.

All six cases used the same installed Debug app on iPhone 18 Pro / iOS 27.0:

- Version 1.0.3, build 275.
- Source revision `6c7ba02ede0fa0884189f55b726bb4babf5966a5`, dirty state.
- Source fingerprint
  `3ad8e9f3c0e73234a78e743652cd9ac88fb93414f6e348c85148abddf213d812`.
- Requested and returned model `gemini-2.5-pro`.
- Backend bundle fingerprint
  `05aedfe76acc8d8bcee71f5ebf0f9de22590e79715e6cc80f1f4ab6032576558`.

Installed product hashes were retained before execution; every measurement
reported the expected app identity and the previously observed backend bundle.
The
[earlier timing verification](./identification-timing-capture-verification-2026-09-22.md)
owns this build's implementation and native test evidence. Later documentation
commits do not change its source identity. This run did not independently attest
database, environment or hosted deployment state.

## Validation and next scope

Verification checked all six first-outcome records, non-overlapping windows,
seven-event sets, HTTP/model/source consistency, timing arithmetic and private
file hashes/permissions. The original source packet's freeze still matches. Run
evidence is frozen outside Git with directory mode 0700, file mode 0600 and
retention through 22 October 2026. Checked-in evidence contains selected UI
labels and bounded measurements, with no real media, account identifiers,
coordinates, credentials, raw logs or production response bodies.

No runtime code changed, so native/backend suites were not rerun. Documentation
formatting, the required functions/scripts formatting check and local evidence
consistency checks cover this report change. The
[measurement guide](../development-guides/21-identification-app-measurement.md)
remains the procedure owner.

Keep Gemini unchanged while expanding the next small pilot to descriptions,
audio and sampled video frames. Playback video remains outside inference. These
six public development photographs do not cover fungi, rigorous lookalikes,
expected-unknown biology, paired media or a held-out sample; prior training
exposure is unknown. A later repeat needs its own recorded pass and must
preserve these first outcomes. No repeatability assessment, Gemini Flash
comparison, second-provider comparison or formal qualification was performed.
