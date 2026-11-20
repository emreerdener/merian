# Unresolved analysis: recovery experience and explicit replacement

Status: approved planning and scheduling, October 18, 2026 (America/Chicago).
Implementation and acceptance remain open. This document records intended work,
not implemented API, funding, retention or runtime behavior.

## Ownership and sequence

[Scan ID History](codex://threads/01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1) remains
the sole implementation owner.
[Harden main analysis engine](codex://threads/01a112ae-2c97-77a1-bd53-5a4434510d4c)
reviews lifecycle, accounting, concurrency and recovery contracts. Reuse
existing owners and services; do not create a competing writer or new
workstream.

1. Continue the current build and reviewed implementation checkpoint unchanged.
   Add recovery experience RUX-1 through RUX-6 below at the relevant native
   integration checkpoint, before complete initial-analysis and reanalysis
   acceptance. This functional UX does not wait for the visual redesign.
2. Preserve the approved post-acceptance sequence: individual-version deletion
   and source-media export, then Identification/History and insight-menu
   redesign. Those views reuse the same recovery states and safe actions.
3. Track explicit replacement as a separate gated follow-up after current-flow
   acceptance. Its default queue position follows those already-approved
   milestones; it does not displace them or become a prerequisite for current
   foundation completion. Any later scheduling change must be recorded at a
   checkpoint, rather than silently interrupting active work.

The [alpha roadmap](identification-history-alpha-readiness-2026-10-11.md) owns
current integration; the
[version-actions roadmap](identification-history-version-actions-and-redesign-2026-10-11.md)
owns deletion/export and redesign. This document is the canonical planning owner
for the new recovery/replacement requirements and acceptance identifiers.
Historical qualification evidence remains unchanged. No deployment, activation,
installation, PR publication or release-control change is authorized.

## Recovery experience for initial analysis and reanalysis

| State           | User experience                                                                                                |
| --------------- | -------------------------------------------------------------------------------------------------------------- |
| Processing      | Normal analysis progress.                                                                                      |
| Checking result | “We lost confirmation of your result. We’re checking whether it finished.”                                     |
| Needs attention | “We haven’t been able to recover your result yet.” Show available next steps instead of an indefinite spinner. |
| Recovered       | Display the verified original result using existing selection rules.                                           |

After 30 seconds of visible recovery checking, show Needs attention. This is
only a presentation threshold: it cannot declare execution failed, release a
credit or authorize another AI execution. Retain sufficient operation-bound
presentation state across navigation and restart so reopening cannot repeatedly
reset the waiting experience. Exact persistence and clock handling must be
specified at native integration, without creating another execution authority.

Offline presentation explains that checking requires connectivity. Promise that
media is saved only after verifying retained originals. Provide:

- **Check status:** recover the exact original operation; never dispatch another
  AI request. An explicit check must not reset an endless automatic spinner.
- **View saved media:** available only when the source assets are accessible.
- **Close:** leave the screen without cancelling or deleting the operation.

Keep the existing identification visible during unresolved reanalysis. An
unresolved initial analysis is a pending item, never a fabricated completed
result. Bind state, actions and asynchronous delivery to the exact account,
observation and operation. Recovery preserves later user selection changes. Use
only supported background recovery mechanisms; do not promise unavailable
background completion or notifications. Provide accessible controls and clear
unavailability/refusal reasons.

## Explicit replacement: gated follow-up

Name the action **Replace pending identification**, not Retry. It remains
unavailable until lifecycle, accounting, retention, API and native contracts are
amended together and REP-1 through REP-8 pass. The future contract review must
define the server-controlled grace period, authoritative eligibility/refusal
model, funding quote validity and confirmation binding, lineage identity and
atomic transition owner. No numeric grace period or wire format is approved by
this plan.

The server may offer replacement only after reconciliation confirms all of:

- Valid original admission and no recoverable validated result.
- No consumed original credit; its eligible unconsumed hold can be released.
- Verified retained source media and no conflicting completion, deletion or
  replacement.
- Server-controlled grace period, normal admission limits, account
  authorization, consent and provider limits satisfied.
- No previous replacement anywhere in this incident lineage. Allow one
  replacement across the lineage, not one per operation or device.

Elapsed time alone cannot establish eligibility. A consumed credit with an
unavailable result is a repair case, not eligibility to release that credit.

Confirmation must explain that the original pending attempt will be permanently
closed, its late result will no longer be delivered, verified source media will
be reused, and existing completed identifications remain unchanged. Show the
replacement's exact credit treatment before proceeding. Changed funding terms
require renewed confirmation. This supersedes the earlier suggestion to accept
both results; there is one authoritative settlement path after replacement.

### Atomic, recoverable transition

If a validated original result becomes available before replacement commits,
recover it instead. Otherwise, atomically close the original against future
delivery and credit consumption, release its eligible unconsumed credit hold,
preserve source-media bindings, and admit the replacement under normal funding
rules. Failed admission leaves the original intact. Reconcile a lost
acknowledgement with the same replacement request; do not create another
attempt.

Already-incurred provider costs and quotas remain counted. This is not a free
retry promise and cannot undo a provider invocation. Late workers must be fenced
from consuming the released credit, delivering an abandoned result or changing
selection. Deletion and account-retirement protections override late results.

An initial replacement has a new initial operation/scan ID linked to the
original pending request. A reanalysis replacement has a new child operation
under the existing observation. Preserve verified photo, audio or video sources
and their associated text; never substitute thumbnails, generated frames or
another version. Preserve pending user content, completed history, notes,
collections and later selection changes. Existing retained media alone may
satisfy the media-required rule; this adds no text-only admission path.

## Acceptance and evidence

All rows are **open: planned, not qualified**. Record exact implementation and
test evidence when implemented; old component runs do not close these rows.
History owns implementation/evidence, with Engine reviewing shared invariants.

### Current native integration acceptance

- **RUX-1 — Bounded presentation:** Initial and reanalysis flows show all four
  states correctly. At 30 seconds of visible recovery checking they offer Needs
  attention without changing execution, funding or admission. Navigation,
  repeated checks, clock changes and process restart cannot create an endless
  reset loop. Recovered results remain recoverable after the threshold.
- **RUX-2 — Exact recovery only:** Check status and interrupted-response
  recovery address the same original operation and never issue another provider
  request. Exercise duplicate taps, reconnect, offline use and repeated app
  restart.
- **RUX-3 — Honest media/background behavior:** Accessible retained originals
  are verified before saved-media promises/actions. Missing or inaccessible
  media yields an explanation; thumbnails are not proof. Offline checking and
  any unavailable background/notification behavior are accurately represented.
- **RUX-4 — Preserve content and selection:** Reanalysis retains the existing
  result, initial work remains pending, Close does not cancel/delete, and
  recovery follows existing selection rules without undoing later user choices.
- **RUX-5 — Identity and accessibility:** Account switching, late callbacks,
  deletion and account retirement cannot reveal or mutate another operation.
  Verify VoiceOver, Dynamic Type, focus and accessible activation of safe
  actions.
- **RUX-6 — Integrated evidence:** Qualify the above on both initial analysis
  and reanalysis with photo/audio/video and optional text through actual native
  integration. Record local versus installed/hosted evidence separately under
  existing authorization gates. Keep replacement unavailable throughout.

### Separate replacement enablement acceptance

- **REP-1 — Eligibility:** Prove every required server condition and explicit
  refusal reason, including no valid admission, recoverable result, consumed
  credit, grace period, missing media, conflicting work, consent/provider limits
  and already-replaced lineage. Time alone never authorizes replacement.
- **REP-2 — Confirmation and funding:** Stale confirmations, changed quotes and
  changed account/revisions cannot commit under unconfirmed funding terms. Show
  exact treatment; preserve incurred provider costs/quotas. Consumed credits
  with missing results stay in repair and are never incorrectly released.
- **REP-3 — Atomic admission:** Failed replacement admission leaves the original
  and its hold intact. Successful replacement atomically closes original
  delivery and consumption, releases only the eligible hold, retains media and
  admits one funded replacement. Fault injection covers each transition
  boundary.
- **REP-4 — Both race outcomes:** If validated original completion wins, recover
  it and do not admit replacement. If replacement commits first, late original
  workers cannot consume the released credit, deliver or alter selection.
- **REP-5 — Idempotent uncertainty:** Duplicate/concurrent requests, interrupted
  responses, offline recovery and restart reconcile the same replacement
  request. Uncertain commits create no duplicate attempts; concurrent devices
  cannot exceed one replacement across the entire lineage.
- **REP-6 — Identity and retention:** Verify initial versus child identities;
  exact photo/audio/video and text bindings; preservation of pending content,
  completed history, notes, collections and later selections. No substituted
  source or retention gap is permitted across the transition.
- **REP-7 — Revocation and UX:** Account switching, deletion/account retirement,
  missing media and stale completion preserve authorization and deletion fences.
  Verify accessible confirmation, refusal, pending, recovery and failure states.
- **REP-8 — Coordinated qualification:** Amend lifecycle, funding,
  media-retention, schema/API/generated DTO and native contracts together as
  applicable. Pass required migration, backend contract/concurrency, native and
  affected-consumer gates with exact-candidate evidence. Keep enablement
  unavailable until these pass; passing tests does not grant deployment or alter
  release controls.

## Contract handoff for implementation

At the relevant checkpoint, reconcile this plan with
[IC-1](initial-completion-history-interface-2026-10-11.md),
[engine lifecycle hardening](main-analysis-lifecycle-hardening-2026-10-10.md),
[ingestion/recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md),
[funding](../backend-and-data/18-complimentary-pro-scans.md),
[API contracts](../backend-and-data/05-api-contracts.md),
[retention](../backend-and-data/17-scientific-observation-retention.md),
[offline ownership](../backend-and-data/01-offline-sync-pipeline.md) and
[native testing](../development-guides/08-testing-strategy.md). Update current
normative claims only with the implementing change. This planning approval does
not reinterpret existing permanent uncertainty/authorization fences or authorize
the proposed replacement through today's recovery APIs.
