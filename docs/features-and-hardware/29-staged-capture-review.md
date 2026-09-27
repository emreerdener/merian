# Staged capture review and shared Describe

This is the current product and lifecycle contract for the Scan, Record, and
Describe workspace. It describes repository behavior, not deployment status. The
[implementation record](../rfcs/staged-review-shared-describe-2026-09-26.md)
retains the pinned provider/provenance checkpoint, exact implementation commits,
validation results, and outstanding distribution evidence.

## Capacity and settings

| Composition      | Physical media                            | Shared text                                         |
| ---------------- | ----------------------------------------- | --------------------------------------------------- |
| Free             | One photo or standalone audio recording   | One optional note                                   |
| Pro              | Two media items, including Pro-only video | One optional note                                   |
| Description only | None required                             | One description                                     |
| Reanalysis       | Two physical items                        | Historical descriptions plus one current supplement |

Text never consumes a physical slot. Multiple historical descriptions remain
separate evidence; they are not merged into the current note. Video retains its
video-derived classification even though inference uses sampled frames and
companion audio. This table defines composition capacity, not available funding.
The [scan allowance contract](../backend-and-data/18-complimentary-pro-scans.md)
owns Free eligibility, Pro-first funding, quotas, and
exhausted-Pro/remaining-Free fallback. Placeholders never enter payloads.

Staged review is the default on new and existing installations. Workspace's
**Auto-submit scans** uses the new `autoSubmitScans` key, registered as `false`;
legacy confirmation and multi-capture values do not initialize it. Later
explicit choices persist. Its description is: “Submit each capture immediately,
skipping review and the chance to add a note or another media item.” There is no
multi-capture preference: the media budget follows entitlement and capture
context.

**Expedition mode** is a normal Workspace setting for everyone. It keeps its
existing `isExpeditionModeActive` key, saved value, and default-off behavior.
Settings persists it before asking `HardwareOrchestrator` to reconcile. The
orchestrator has no entitlement dependency; offline, expired, and unverified
subscription states do not disable the preference. Its existing frame-rate,
effect, haptic, and background-upload behavior remains defined by the
[hardware contract](./01-camera-and-hardware.md#hardwareorchestrator). Disabling
it restores ordinary constraint evaluation and upload eligibility, subject to
the normal permission, funding, connectivity, and recovery checks.

## One text editor

Root Describe is the only editor for ordinary text and the current reanalysis
supplement. Both **Add note** and **Edit note** navigate there and focus the
same input, including when media capacity is full. There is no second ordinary
note sheet. Mode switches and keyboard dismissal preserve edits.

| State                                     | Describe central action           | Submission behavior                                                    |
| ----------------------------------------- | --------------------------------- | ---------------------------------------------------------------------- |
| No review, empty text                     | Disabled                          | No text to stage or submit                                             |
| No review, nonempty text, Auto-submit off | Plus: **Add description to scan** | Enters staged review                                                   |
| No review, nonempty text, Auto-submit on  | Arrow: **Identify**               | Explicit user submission                                               |
| Review active                             | No central action                 | Tray **Identify** submits the latest shared text                       |
| Reanalysis                                | No central action                 | Tray **Analyze** submits the latest supplement and historical evidence |

Typing alone updates the draft without revealing the tray or submitting. Once
review exists, editing updates the same note; clearing text removes it. Removing
the last media item retains any remaining text and review state. Removing all
content returns to initial capture. Prompts and dictation remain available as
appropriate for the existing Describe flow. Keyboard-toolbar **Done** dismisses
editing and reveals an existing tray; it does not submit or stage a previously
unstaged text-only draft.

Only historical description evidence uses `StagedDescriptionSheet`. It edits a
local copy: **Done** commits, swipe-dismiss discards unsaved edits, and
**Remove** commits removal. Opening it stops and fences dictation. Historical
edits never replace or clear the current supplement. See the
[Describe and dictation contract](./11-describe-and-voice-dictation.md).

## Tray and protected discard

The media row displays physical captures and an add-media placeholder while
capacity remains. One note node follows it: message-plus when empty, filled
message bubble when populated, with **Add note** / **Edit note** accessibility
labels. Text-only scans use that same note node once. Reanalysis may also show
historical text nodes. The once-per-install tooltip says “Add a note about what
you noticed.”

Physical capture controls remain available while capacity remains; the note
remains reachable at full capacity. The media row scrolls horizontally while
Discard and Identify/Analyze stay visible. On iOS 26+, the tray capsule and
circular discard control use native Liquid Glass. Earlier iOS uses material;
Reduce Transparency or the existing Expedition/thermal effect policy selects an
opaque adaptive background. The tray follows the app's color scheme consistently
across Scan, Record, and Describe; switching capture modes does not force a
separate dark appearance. **Identify** is text-only, uses the same primary
accent blue as Share, and remains 48 points high with its existing disabled
appearance. **Analyze** retains its green styling and sparkles. Media icons
retain their meanings.

The neutral discard surface has a semibold trash icon with a deeper red in light
appearance and a brighter red in dark appearance for contrast. The empty note
icon combines the supported `text.bubble` and `plus.circle.fill` symbols; a
populated note uses `text.bubble.fill`. Tapping discard presents:

- **Discard this scan?**
- “Your staged media and description will be removed.”
- **Keep editing** / **Discard scan**

Reanalysis uses **Discard reanalysis?** and preserves the original scan,
restoring its insight after confirmed discard. Opening or dismissing the
confirmation preserves content. While presented, submission and composition
actions are blocked. Confirmation is bound to the originating draft generation.

Confirmed discard clears draft media, shared text, editor, and refinement state;
it stops dictation, invalidates pending callbacks, and deletes only draft-owned
files. Individual media removal keeps its existing behavior. Enqueue-pending
work cannot be discarded.

## Readiness and automatic capture attempts

`CaptureDraftSession` owns the generation and unresolved-operation tokens.
Register photo, audio, video, and import work before asynchronous execution.
`isDraftReadyForSubmission` is shared by UI and submission entry points and is
rechecked after admission and before enqueue. Recording, capture, import,
preparation, required crop, and unresolved refinement hydration block
submission. Prepared media commits and its operation resolves in the same draft;
stale completions cannot update a successor. Failure resolves the operation,
revokes automatic eligibility, and retains existing content for manual review.

Automatic eligibility is minted at capture entry only when Auto-submit is on,
the entire composition including pending text is empty, and no reanalysis is
active. It follows that attempt through recording/preparation and the initial
required crop; video may submit after preparation. Completion may consume this
eligibility but cannot create it. Turning the preference off revokes it even
across an off/on cycle. Turning it on, recropping, removing content, or adding
context never arms an existing attempt. Reanalysis is always manual.

Fresh automatic gallery selection is limited to one photo. Pending text makes
the composition manual and retains its normal physical-media budget. Picker
entry admits a minimum one-photo addition; selection-time admission checks the
actual chosen count before file loading. Final submission still rechecks the
complete evidence. Late admission responses from discarded generations produce
neither a paywall nor an error on the next draft. The
[Photos import guide](./26-photos-share-import.md#gallery-admission-and-free-fallback)
explains that boundary.

## Durable ownership and provider checks

Before durable acceptance, the draft and original files remain owned by Capture.
Admission/enqueue locks block duplicate submission and conflicting edits;
enqueue locks also block discard. Queue preparation copies media into unique
queue-owned files. A definitive pre-acceptance failure removes only provisional
copies, releases locks and automatic eligibility, and leaves a manual retry.
Ambiguous acceptance must be resolved before another enqueue or deletion.

After acceptance, Capture clears draft references and may remove draft-owned
sources; live inference uses the accepted queue-owned timeline. Recovery retains
the same scan ID and durable owner, never a recreated submittable draft. See the
[offline pipeline](../backend-and-data/01-offline-sync-pipeline.md) and
[ingestion/recovery contract](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md).

Final serialized evidence drives recipient preflight for manual, automatic, and
replay paths. Permission/version rejection or recipient reassignment uses the
integrated pause/recovery path for that same observation. Auto-submit does not
bypass account, permission, app-version, or dispatch-attempt checks. Evidence
order, routing classification, historical text, and immutable provenance remain
intact. This feature adds no schema migration or capture-specific wire field.
Server eligibility changes must be released through the existing gates before
client distribution; implementation and local tests do not authorize deployment.

## Owners and verification

Shell's `CaptureWorkspaceViewModel+Draft` owns shared text, readiness, discard,
and operation coordination. `CaptureDraftSession` and `StagedCapturePolicy` own
pure attempt/capacity state; `ActiveScanToolbar` projects the tray. Submission's
admission and visual/nonvisual entry points connect to the Core durable queue.
Settings owns preference/paywall presentation, while `HardwareOrchestrator` owns
effect constraints and `IdentificationEvidenceAllowance` owns the shared native
Free evidence rule.

The
[verification matrix](../development-guides/08-testing-strategy.md#staged-review-and-shared-describe-validation)
contains exact suite and UI selectors. The dated implementation record preserves
completed local checks and remaining device, database, and release evidence.
