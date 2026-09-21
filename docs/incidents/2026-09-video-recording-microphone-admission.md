# Incident: Video recording microphone admission regression

- **Date detected:** 2026-09-21
- **Status:** Recording works after an active call ends; call-contention
  mitigation is implemented in source and awaits device verification. Earlier
  downstream deployment/verification remains separate.
- **Affected versions/environments:** Initially reported on iOS app 1.0.3 (275),
  without source revision or device/OS details. The later active-call report
  follows a local archive of `7bcb680e0`; see the dated evidence below.
- **Affected surfaces:** iOS camera recording and Capture Scan feedback
- **Current contract:**
  [Camera and hardware](../features-and-hardware/01-camera-and-hardware.md)

## Summary

A user reported an apparent freeze followed by a video staging error toast. The
supplied log establishes that AVFoundation rejected recording before the
recording-start callback. Source inspection found an audio-input admission bug
introduced by the September 20 audio ownership refactor. The bug is corrected in
source; its contribution to this device failure still requires a hardware
retest.

## Impact and scope

One supplied recording attempt fails with AVFoundation error -11803 and
underlying OSStatus -16409. No successful recording or staging is evidenced for
that attempt. Counts beyond this report, freeze duration, microphone permission,
and a known-good device comparison are unknown. The adapter defect affects empty
microphone input lists, including requests that select silent recording.

## Detection and timeline

| Date       | Event                                                                                                                    | Evidence status                                    |
| ---------- | ------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------- |
| 2026-09-20 | Commit `16a47e2d22cb5173023769cb44301328558aa5cf` introduces the audio owner and faulty empty-detach branch              | Confirmed in repository history                    |
| 2026-09-21 | User reports freeze and staging toast on build 275                                                                       | Confirmed report; duration unmeasured              |
| 2026-09-21 | Log shows running, uninterrupted session with active video/audio connections, followed by recording failure before start | Confirmed supplied event order                     |
| 2026-09-21 | Source guard and live-adapter regression tests added                                                                     | Repository mitigation; device confirmation pending |

## Reproduction

`CameraVideoAudioSessionTests` uses the actual input-configuration adapter with
an empty `AVCaptureSession` and an injected microphone factory returning nil.
Before the guard, even `configureInput(false)` invokes that factory. A silent
recording invokes it during both preparation and cleanup; an audio-enabled
request invokes it before activation, during attachment, and during cleanup. The
corrected branch invokes it only for an explicit attachment request. This
reproduces the admission defect without real microphone permission or hardware.
It does not reproduce the device-specific OSStatus failure.

## Root cause and failed invariant

`CameraVideoAudioSession.withAudio` requires detach, lease activation, then
microphone attachment. The live adapter's `else if inputs.isEmpty` branch
omitted `includeAudio`. Consequently, an empty detach attached a microphone
before the shared audio session was configured and activated. Silent requests
could also attach one without acquiring a recording lease. Cleanup could
discover or attach a new input when it should only remove one.

Existing lifecycle tests mocked the input adapter, so they proved the intended
call order without exercising this branch. New tests cover the actual adapter.
The reported failure is temporally consistent with this regression, but the
numeric OSStatus has not been assigned an undocumented meaning. Active
connections do not establish that microphone/session setup was valid.

The log does not establish an upload, database, or media-preparation failure:
recording itself failed first. Automatic stabilization and the longstanding
recording filename/container choice remain unchanged; the report does not
isolate either as a cause. Main-thread blocking has not been measured.

## Regression coverage

- `CameraVideoAudioSessionTests.liveInputAdapterNeverDiscoversMicrophoneForSilentVideo`
- `CameraVideoAudioSessionTests.liveInputAdapterDiscoversMicrophoneOnlyAfterLeaseAndNeverDuringCleanup`
- Existing audio ownership tests for cancellation, overlap, replacement
  playback, delayed teardown, and failure/retry.
- `CaptureScanDependenciesTests.recordingFailureResetsCaptureAndAllowsRetry`
- `CaptureScanDependenciesTests.preparationFailureKeepsStagingMessageAndRemovesRecording`

## Repository mitigation

Require `includeAudio` before microphone discovery/attachment. Keep lease,
queue, and cancellation ownership intact. Add a narrow microphone-factory seam
to test the real adapter without accessing hardware. Distinguish recording
failures from preparation/staging failures in the user-visible toast and prove
UI reset, retry admission, and temporary-file cleanup.

## Candidate validation

`make xcodegen`, `make validate-ios-project`, generated-project
source-membership tests, Markdown formatting, and `git diff --check` passed.
Generator-only project churn was reviewed and discarded; this change adds no
source files or manifest entries. After another local build released the shared
cache, the nine focused camera/audio/Capture Scan suites passed: 63 tests, zero
failures. Evidence:
`.artifacts/local-ios/61784370d9e44562b702f60a10c5d842.xcresult`.

The complete `merianTests` target also passed against those build products:
4,221 tests / 6,236 total test runs, zero failures and zero skips. Evidence:
`.artifacts/local-ios/2ed76d58582248eebdba44dc46bdb687.xcresult`. Both runs used
the repository's shared-cache wrapper and the iOS 27 simulator. No immutable
release candidate has been produced. Simulator coverage cannot establish
physical camera behavior.

## Production deployment

**Not performed.**

## Runtime verification

At the initial source handoff, device verification had not been performed.
Follow-up user logs now verify a full-duration recording, cancellation, and an
early-stop recording; both completed clips reached staging and Camera Roll. See
the dated follow-up below. Remaining checks include repeated five-second
recordings, playback-to-recording transition, and silent recording with
microphone access denied. Confirm preview responsiveness, exactly one
completion, correct staging, and no audio connection for silent capture. Capture
a timing trace if the freeze persists.

## Data recovery

**Not required for the evidenced attempt:** no recording completion or staged
capture is shown. No recoverable video file is established by the supplied log.
No hosted data was inspected or changed.

## Privacy and security review

This record includes only sanitized error codes, state flags, and repository
evidence. It contains no raw log payloads, credentials, personal data,
coordinates, or session state. Silent capture must not discover a microphone.

## Exit criteria

- [ ] Confirm the device failure's root cause with a before/after comparison.
- [x] Complete focused and full local iOS unit-test gates.
- [ ] Deploy only after an explicitly authorized operation and target.
- [ ] Verify the affected physical-device workflow and responsiveness.
- [x] Document the evidenced attempt's data-recovery boundary.
- [x] Synchronize current contracts and owner documentation.

## Follow-ups

| Owner       | Action                                                       | Due/status |
| ----------- | ------------------------------------------------------------ | ---------- |
| iOS capture | Run physical-device recording matrix and confirm causal link | Open       |

## Dated corrections

### 2026-09-21 — Follow-up device recording evidence

The user reported that recording appears to work and supplied another log from
app 1.0.3 (275). Source provenance remains unavailable, so this verifies the
observed device workflow without identifying an immutable installed revision or
proving the audio guard was the sole causal change.

- A full-duration recording starts after approximately 1.20 seconds, finishes at
  the configured five-second limit, saves to Camera Roll, samples all five
  frames, and stages a compressed playback file. AVFoundation's -11810 event
  explicitly reports the duration limit and successful completion; it is not a
  recurrence of the original pre-start -11803 failure.
- A second recording starts after approximately 0.83 seconds and is explicitly
  cancelled. The late finish callback is ignored after request ownership ends.
- A third recording starts after approximately 0.92 seconds, stops manually
  after approximately 3.72 seconds, saves to Camera Roll, and stages all five
  frames plus the playback file.
- Preparation takes approximately 6.94 seconds for the first completed clip and
  0.43 seconds for the early-stop clip. The log does not measure main-thread
  responsiveness during either interval.

The first staged clip subsequently reaches a durable queue commit, but local
upload preparation reports `payloadTooLarge` and the foreground
`identify-multimodal` request returns HTTP 400 / `invalid_audio_content`. Their
precise causes and relationship are not established by this log. Thus
recording/staging recovery is evidenced, while successful end-to-end
identification is not. No backend mutation or additional implementation was
performed during this follow-up review.

### 2026-09-21 — Downstream remediation

Source tracing confirms that five sampled frames, a companion WAV, and playback
video produce seven upload items against the old six-file cap. The local, Edge,
and database caps now align at eight, allowing the existing independent maxima
of five images, two audio clips, and one video. Queue batch selection also
respects those per-kind limits across scans. The forward migration is
`20260921160739_align_video_staging_media_budget.sql`; historical migrations
remain unchanged.

A synthetic five-second PCM WAV with an 80 ms sound reproduces the backend's
post-trim duration rejection. This is a plausible cause of the observed audio
400, not proof of the device payload's exact failure. For a timeline-validated
video companion only, the fix preserves source context when trimming alone makes
the clip too short. Malformed or genuinely short sources still fail, and
standalone audio remains strict.

Release order is database migration, affected Edge Functions, then the iOS
build. The source changes are not a deployment. Physical-device verification
must exercise full-duration and early-stop videos with sparse and sustained
audio through completed identification, including offline replay.

Downstream validation:

- Complete iOS unit target: 4,222 tests, 6,239 total runs, zero failures or
  skips. Evidence:
  `.artifacts/local-ios/ce96689439754645acf84bf6a40eb549.xcresult`.
- Focused iOS staging/queue checks: 14 tests, 16 runs, zero failures or skips.
  Evidence: `.artifacts/local-ios/d228a03c0cf94ed7ae8ac72a0d6507df.xcresult`.
- Complete Edge suite with disposable database access: 2,040 tests passed,
  including the database-backed cases; no failures or ignored tests.
- Fresh isolated migration replay and all 52 database catalogs: 388 assertions
  passed. The shared local database had unrelated historical drift, so it was
  not reset; validation used a separate disposable project, removed afterward.
- Strict database lint passed. Advisor gates passed with zero errors and
  existing warnings (105 security, 80 performance); this is not a claim that the
  repository's entire database is warning-free.
- Migration contracts, generated DTO parity, complete Supabase tooling, isolated
  function dependency checks, type checks, lint, and formatting passed.
- Independent read-only review found no remaining actionable defects in scope.

Device acceptance after deployment and installing the matching iOS build:

1. Record a five-second video with a brief sound followed by quiet; require a
   completed identification response, playable saved video, and no staging or
   `invalid_audio_content` error.
2. Repeat with sustained sound and with an early stop; confirm the preview stays
   responsive and each recording completes once.
3. Capture offline, reconnect, and retry queued work; require the complete
   frame/audio/playback bundle to reach identification without a size rejection.
4. Retest denied-microphone silent capture and playback-to-record transitions.

Retain only redacted status codes and timings, together with the installed
build's source provenance. A successful simulator suite does not replace these
hardware and deployed-path checks.

### 2026-09-21 — Active-call recording failure

The user reported an immediate "Video couldn't be recorded" toast after merging
and archiving. The latest local archive identifies source revision
`7bcb680e05e48635ccb2667186d07df01d6852cc`, which includes the prior fixes. Its
version remains 1.0.3 (275); version/build alone therefore cannot distinguish it
from earlier archives. The installed binary was not independently inspected.

The screenshot shows an active-call context. The user then confirmed that the
same app records successfully after the call ends. This comparison identifies
the call as the observed trigger. No fresh AVFoundation/OSStatus log was
supplied, so the exact error code remains inferred from the native admission
path and Apple's SDK contract.

`AVAudioSession.setActive` documentation in the installed SDK states that
another app's call prevents activation of recording categories with
`insufficientPriority`. The current movie path activates `.playAndRecord` before
configuring or starting its writer and previously propagated this optional-audio
failure as failure of the whole video request.

The source now handles only `NSOSStatusErrorDomain` / `insufficientPriority`
during audio-lease admission. After coordinator rollback, video proceeds without
a microphone input or lease. Other activation failures, cancellation, and movie
configuration/writer errors retain their existing failure behavior. No movie is
retried, no active-call audio is captured, and a subsequent capture tries audio
admission again. Regression tests cover fallback, a later audible attempt,
restored playback ownership, cancellation during failed admission, unrelated
errors, and non-retry of a movie-operation error.

Physical-device acceptance remains open: verify silent video during a call, then
video with audio after the call, with exactly one completion and responsive
preview. Ending the call verifies ordinary recording on the current archive; it
does not verify the new fallback, which has not been archived or deployed.

Call-contention source validation:

- Complete iOS unit target: 4,227 tests, 6,244 total runs, zero failures or
  skips. Evidence:
  `.artifacts/local-ios/894d9c0ee7f7436eb77d362b7ec86f70.xcresult`.
- Focused camera/audio suites: 60 tests, 61 runs, zero failures or skips.
  Evidence: `.artifacts/local-ios/90e9b3836d614c878a337f2a85d8ff0b.xcresult`.
- Generated-project validation, source-membership checks, Markdown formatting,
  and diff whitespace checks passed. Incidental XcodeGen serialization changes
  were discarded; this change adds no project sources or build settings.
- Independent read-only review found no cancellation or lease-ownership blocker.
