# Identification evaluation: solo checks and the reviewed pilot

Date: 22 September 2026\
Status: Six source-backed exploratory photos prepared; formal corpus at 0/60
reviewed groups; no paid direct-evaluator run

This is the collection workflow for Slice 4 of the
[evaluation PRD](../product/04-identification-evaluation-prd.md) and
[SRD](../rfcs/identification-evaluation-srd.md). Those documents own the scope
and measurement rules. The
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md)
owns the executable format and runner controls. This packet supplies blank
working forms; it does not supply observations or approved reference answers.
The separate
[six-photo preparation record](../rfcs/identification-source-photo-pilot-2026-09-22.md)
documents the first expanded source-backed exploratory packet.

## Start here when you are working alone

The project currently has one owner and no independent reference reviewers.
Start with a **self-reviewed development check of six observations**, then add
six more if the workflow is useful. The two-reviewer requirement below belongs
to the formal accuracy benchmark. It is not a prerequisite for collecting your
own examples or manually testing the app.

1. **On your computer:** create a local `Naturebook-tests` folder outside Git
   and cloud-synchronized folders. Keep a short table in a local document or
   spreadsheet. Assign IDs such as `test-01`; make one folder per observation
   when you have source files to retain.
2. **Before identifying anything:** write what you expect and why. Use a subject
   you recognize, a documented plant identity, or a known non-biological object
   for the easier examples. Record `unknown` when you cannot establish identity.
   A label or your own knowledge is a provisional reference, not independent
   verification. Do not copy expected names into the identification description.
3. **On your phone:** use the installed Naturebook build to try one photo,
   description, audio recording, short video, and available combinations from
   the table below. Use your normal account and its existing entitlements;
   record an unavailable combination as untested. App submissions use the
   ordinary live identification path and its normal allowances. Keep the first
   result, including failures; record retries separately.
4. **On your computer:** record whether each submission finished, its displayed
   identity/confidence, approximate submit-to-result seconds, and your
   assessment. Use `matches my reference`, `contradicts my reference`, `unsure`,
   or `failed`. Keep unsure cases visible and separate from judged matches; do
   not turn lack of your own knowledge into proof that Gemini is wrong. Store
   brief summaries, not raw server responses or diagnostic dumps.
5. **Keep useful source evidence:** when collecting outside Naturebook, use
   Camera for photos/five-second videos and Voice Memos for short audio, without
   people or speech. AirDrop source files to your Mac from
   [Photos](https://support.apple.com/guide/iphone/share-photos-and-videos-iphf28f17237/ios)
   or
   [Voice Memos](https://support.apple.com/guide/iphone/share-a-recording-iph3d6dc359/ios).
   Keep video/audio from the same observation together. Source files still need
   metadata removal and the documented image/WAV preparation before entering the
   evaluator; AirDrop does not perform that preparation. Do not copy private
   metadata into notes or share unprepared files as evaluation artifacts.

| Input             | First example                                                    | Optional second example                                         |
| ----------------- | ---------------------------------------------------------------- | --------------------------------------------------------------- |
| Photo             | A familiar plant or animal with visible distinguishing features. | A rock, leaf damage, or another ambiguous subject.              |
| Description       | Describe visible features without naming the species.            | A sparse description where uncertainty may be appropriate.      |
| Audio             | An audible animal whose source you can observe or document.      | Weather/mechanical sound or a faint unidentified call.          |
| Frames            | A steady five-second capture of a clear subject.                 | Partial or moving evidence.                                     |
| Frames with audio | A five-second capture with its associated sound.                 | An incidental animal audible behind a different visual subject. |
| Photo with audio  | A photo and sound from the same observation.                     | A case where the sound and visible subject differ.              |

Naturebook's short-video capture prepares ordered snapshots and companion audio;
it does not send the playback video for identification. Do not manually
screenshot five frames for the phone check. Some evidence combinations require
the available app controls/plan; if a frames-only case is not available, keep
the source clip for later preparation and mark that phone check untested.
Camera/Voice Memos collection alone does not establish that those files can be
imported into every Naturebook input mode.

The local results table can be as small as this:

| ID / input | Expected answer and basis, written first | App result / confidence | Seconds | Assessment / issue |
| ---------- | ---------------------------------------- | ----------------------- | ------: | ------------------ |
| Pending    | Pending                                  | Pending                 |         | Pending            |

Record the app build and active plan once per session. Keep expected-answer
notes separate from model input. A second pass over the same case is a repeat,
not an independent observation. Another AI agreeing with Gemini is not a second
reviewer. If you later find better reference evidence, record the correction and
reassess all retained results consistently.

This check can find capture failures, missing evidence, obvious contradictions,
confusing confidence, and slow app behavior. Phone stopwatch times include app,
upload and backend work; they are not provider-only timings or usage-cost
measurements. Self-reviewed examples do not establish an independently verified
species-accuracy percentage or qualify a provider switch.

## Automating the solo check

The evaluator now has a separate **exploratory mode** for one to twelve real
observation groups. One owner or explicitly identified automated reviewer can
check source rights, prepared media, privacy and duplicates. Expected identities
remain provisional; use a null reference when the identity is unknown. There is
no need to invent a second reviewer or label real observations synthetic.

1. Prepare the eligible media outside Git with opaque asset names and no
   identifying metadata. Keep actual paired audio and ordered video snapshots
   together. Record source/permission evidence and any provisional reference in
   separate curation records.
2. Assemble `identification_exploratory_corpus_v1` and a frozen taxonomy map.
   Run `preflight DIRECTORY` using the denied-network/environment flags in the
   [tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#automated-exploratory-runs).
   It checks actual assets and reports coverage and planned calls without a key
   or inference. `demo-exploratory DIRECTORY` supplies invented examples for
   verifying the automation itself.
3. Review the exact corpus, dedicated evaluation project/key, processor
   readiness, current pricing and run specification. Authorize the concrete USD
   budget before `--live DIRECTORY`. The exploratory specification schedules
   each existing Gemini profile once per group: at most twenty-four calls.
4. Keep `manifest.json`, claims/results, `summary.json` and `report.md`
   together. The report records reference agreement, failed/unknown/unattempted
   cases, successful-call timing and estimated usage cost.
   `report DIRECTORY RUN_ID` regenerates it without inference. An interrupted
   uncertain call is retained, not silently repeated.

The first recorded experiments are in the
[exploratory experiment record](../rfcs/identification-exploratory-benchmark-2026-09-22.md).
A synthetic run verifies mechanics; only a live run can establish an exploratory
Gemini timing/cost reference. Provisional agreement does not establish verified
species accuracy. The formal baseline below remains deferred until its reference
requirements can be met.

The first
[live app checkpoint](../rfcs/identification-production-app-benchmark-2026-09-22.md)
completed two approved photo submissions through the ordinary production
workflow. It records client request and pipeline timing, with one provisional
species agreement and one unverified outcome. It provides no exact-model,
provider-only timing or billed-cost measurement. This app path uses normal
admission and charges; it does not grant the direct evaluator access to app
sessions or remove that runner's separate readiness and spending controls.

For subsequent app checks, the
[passive measurement guide](./21-identification-app-measurement.md) records
provider/model, built-app and Function identity, provider/Edge intervals and
nullable usage. It can estimate the observed primary call from a reviewed
pricing snapshot. The instrumentation requires an updated app/backend before
live use and does not fill the first checkpoint's missing data. Its observer
submits no requests and does not replace result-screen observation or reference
review.

The
[six-photo source packet](../rfcs/identification-source-photo-pilot-2026-09-22.md)
subsequently passed offline preflight with five source-backed provisional
species references and one non-biological control. Its private media, source
records, taxonomy and app plan are frozen; preparation made no model calls. The
next ordinary-app pass is limited to six sequential first submissions with no
manual retries. That plan is separate from the direct evaluator's twelve-call
dry schedule. These automated eligibility reviews do not advance the formal
reviewed counts below.

## Formal pilot: start here when reference review is available

1. Identify a controlled folder outside Git for purpose-collected or
   individually approved licensed evidence. Confirm its owner and retention
   date. Keep the execution directory private and local, outside
   shared/cloud-synchronized folders, as required by the tooling guide.
2. Assign a collection coordinator and two independent reference reviewers with
   relevant biological expertise. Record opaque role codes, not personal names,
   in evaluation records. Both reviews cover eligibility and the reference
   answer; an AI assistant does not count as either independent reviewer.
3. Collect one eligible observation for each of the six input groups first.
   Prepare and review these six to find collection or format problems, then fill
   the remaining slots. This is a local intake checkpoint with no Gemini calls;
   the paid development run requires all 60 reviewed groups.
4. Copy a [case record](./identification-evaluation/case-record-template.md)
   into the controlled folder for each observation. Give each reviewer a
   separate [review form](./identification-evaluation/review-template.md). Keep
   completed forms and real evidence outside this repository.

Use fresh evaluation captures or a supplied eligible collection. Do not export
production observations, reuse production identification responses as labels, or
search personal media libraries without a supplied source. A public URL or
ownership of a photograph alone does not establish permission to send it to
Gemini for this evaluation. Record the applicable permission evidence before
admission; evaluation permission grants no training rights.

## Proposed collection coverage

These are collection targets for Product to review before freezing the pilot.
They describe evidence to seek, not answers to assign. The reviewers determine
what each observation actually supports. Reassign or replace an unsuitable
pending slot instead of forcing its label to match a target.

| Input group    | Slots   | What to collect                                                                                       | Reviewed |
| -------------- | ------- | ----------------------------------------------------------------------------------------------------- | -------: |
| `photos`       | P01–P10 | Still photos of ten independent observations; one or more views per observation.                      |     0/10 |
| `description`  | D01–D10 | Observable descriptions of ten separate observations, without species names or copied reference text. |     0/10 |
| `audio`        | A01–A10 | Animal/environment recordings with no human speech or identifiable human content, prepared as WAV.    |     0/10 |
| `frames`       | F01–F10 | Ordered snapshots, normally one per second from each of ten five-second captures.                     |     0/10 |
| `frames_audio` | V01–V10 | Ordered snapshots and their actual companion WAV from ten other captures.                             |     0/10 |
| `photos_audio` | M01–M10 | Still photos and the associated acoustic evidence from ten other observations.                        |     0/10 |

Slot labels are planning references, not corpus case IDs. Once an observation
enters intake, give it unique `c0001`/`g0001`-style IDs. All of its crops,
frames, sounds, and derived descriptions keep that group identity. A photograph
and a description derived from it cannot fill two slots. Keep withdrawn IDs in
the controlled intake history; give a replacement observation a new group ID.

For each row, use this initial ten-slot pattern:

| Slot suffix | Evidence to seek                                                                                                     | Count per input group |
| ----------- | -------------------------------------------------------------------------------------------------------------------- | --------------------: |
| 01–03       | Clear biological evidence, using different subjects rather than repeated easy examples.                              |                     3 |
| 04–05       | Lookalikes or otherwise ambiguous identity; seek at least one example best answered at a broader rank.               |                     2 |
| 06–07       | Degraded evidence: one still useful example and one where biology is apparent but identity should remain unresolved. |                     2 |
| 08          | Evidence too weak to determine whether the subject is biological.                                                    |                     1 |
| 09          | An independently verified non-biological source, such as a rock surface or mechanical sound.                         |                     1 |
| 10          | Multiple/incidental organisms; for combined media, a real disagreement between visual and acoustic subjects.         |                     1 |

For each combined-media group, also include an incidental organism in one of
slots 01–07. Use evidence from the same observation; do not assemble unrelated
images and recordings to manufacture disagreement. Document the intended subject
and acceptable alternatives before evaluating either Gemini profile. The
reference must respect the existing task's subject-selection rules; this packet
does not introduce a new visual-versus-audio policy.

Across the visual and description groups, seek plants, fungi, invertebrates, and
vertebrates. Audio coverage should use biologically meaningful sources. Record
the actual biological group and difficulty tags in the controlled case record.
Report gaps rather than filling them with unverified labels. These tags are
curation metadata and do not belong in the strict provider-input JSON.

## Prepare evidence before reference review

Keep input evidence separate from source verification and answers. Use opaque
asset filenames, remove revealing metadata, and exclude personal information,
precise coordinates, human faces/speech, credentials, and account identifiers.
Observation text describes only what a user could observe. Use the permitted
coarse region/month only when known and useful; otherwise preserve null context.
Do not add source names, taxon names, reviewer notes, or URLs to the prompt.

Backend prepares the assets using the
[existing media checks](../../services/supabase/scripts/identification_evaluation/README.md#owners-and-use),
records the preparation recipe/version, and hashes the final files. Reviewers
must decode/view every final image and listen to the final audio; image
container checks alone do not prove valid pixels or exclude personal content.
Record any production audio trimming/resampling that affects the supplied
evidence and review that resulting evidence too.

Before review, freeze a controlled input record that passes the existing
`parseEvaluationInput` validator. It contains the ordered observation texts,
coarse/null context, clip declarations (`clipIndex`, `declaredFrameCount`,
`includesAudio`), and ordered assets with `kind`, opaque `path`, hash, MIME,
byte length and the applicable `sourceIndex` or `clipIndex`/`frameIndex`. Record
both its canonical `fingerprintJson` digest and the `fingerprintEvidence` digest
of the provider-eligible projection. These existing helpers run locally without
provider calls. Both reviewers assess this same frozen record; corpus assembly
must preserve it exactly.

Video contributes ordered image snapshots and, for `frames_audio`, its included
companion WAV. The playback video never goes to the evaluator. Preserve frame
indexes and clip/audio relationships, including an honest partial frame set
where applicable. All visuals in one case use one supported MIME type. Never
silently remove included audio to make an observation pass preparation.

For each derived asset, keep a controlled lineage record linking its final hash
to the opaque source-capture reference or fingerprint, extraction/preparation
version, retained frame index/time within the clip, and audio extraction range
where applicable. Record the common observation association for still photos
with audio too. Both reviewers inspect this record and the final derived assets.
The validator checks declared relationships; it cannot establish that an
unrelated WAV actually came from the same capture. Lineage records stay outside
Git and the strict provider input, without personal data or coordinates.

An evidence edit after review invalidates that review. Re-prepare, hash and
review the changed case before it can be admitted.

## Obtain and reconcile the two reviews

Give each reviewer the same frozen input digest and evidence fingerprint. They
first record their own evidence-based subject, supported rank, and possible
answers without seeing the other review or any Gemini result. They then verify
the reference and eligibility against the controlled source/permission records
and independent reference evidence, retaining their initial assessment.

A source identity can verify what was recorded; it cannot make missing visual or
acoustic features identifiable. A taxonomy lookup establishes a name/ID mapping,
not the observation's identity. Record unresolved identity when that is what the
supplied evidence supports. Known non-biological evidence and indeterminate
evidence are separate labels. Human-only policy cases remain synthetic and do
not enter this real corpus.

Reconcile completed reviews only after both are recorded. Record `agreed` when
they independently agree, or the rationale and both reviewers' acceptance of a
`resolved` adjudication. An open disagreement, missing permission, or missing
reference evidence keeps the case pending. Collect a replacement when needed;
never convert a pending record into `curation.kind: reviewed` merely to fill the
quota.

## Assemble the pilot and prepare the spending decision

Backend converts only admitted cases to `corpus.json` and freezes the taxonomy
map, preserving each reviewed input record and digest. Use the existing strict
schema; do not add the forms' workflow fields or coverage tags to it. Named
references list explicit acceptable taxon/rank pairs; unresolved references use
a null supported rank and an empty acceptable-taxa list. Record only approved
aliases in the frozen taxonomy, before seeing model answers. Unknown returned
names stay unresolved mappings.

Before proposing paid execution, complete this handoff:

- Sixty independent development groups, ten per input group, with both reviews
  resolved, permission and lineage evidence, and decoded/prepared media checked.
  Every assembled input must pass `parseEvaluationInput` and match the canonical
  input digest accepted by both reviewers, including ordering and context.
- Exact/near-duplicate review across every observation and derivative, including
  any already reserved held-out material. Freeze split membership, preparation
  and taxonomy versions, corpus approval and digest. Freeze the detailed
  held-out coverage rules after the pilot and before selecting its 240 cases.
- A reviewed evaluation project/credential record and current exact-model
  pricing/token ceilings, bound by their digests. The key itself never enters
  these documents. The runner's assertions do not verify vendor account settings
  or provide the human reviews above.
- A concrete run proposal: the approved corpus digest; `development` stage and
  split; both `gemini_flash_free` and `gemini_pro`; one attempt each; shuffled,
  interleaved order; concurrency one; at most 120 calls; and a reviewed USD
  budget sufficient for the runner's conservative reservation policy.
- A user request authorizing that specific paid evaluation. A call ceiling is
  not a dollar budget or spending approval. Preserve the runner's stops for
  operational failure, uncertain execution, missing usage and call/spend limits.

The 240 held-out cases and 30-group repeatability check follow the pilot under
their own frozen specifications and spending decisions. Slice 4 remains open
until its measured reports exist. Completing this collection packet or passing
synthetic tests does not establish a Gemini quality baseline.
