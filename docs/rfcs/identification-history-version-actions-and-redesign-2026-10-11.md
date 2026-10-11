<!-- Approved user plan transcribed from planning thread 01a12460-a2c6-7b21-abcf-d3be41331b45, October 11, 2026. -->

# Identification and History: version actions and UX redesign

## Summary and sequencing

Use the supplied mockup as the target experience, delivered in this order:

1. Finish the current identification-history and analysis-engine scope.
2. Add individual-version deletion and source-media download to the existing
   history experience.
3. Refactor the Confidence sheet into the Identification sheet and deliver the
   redesigned History page.

Document the new behavioral requirements now so ongoing work can account for
them. They do not automatically expand the current implementation milestone.

The history implementation chat remains the implementation owner. After
approval, hand this plan to that chat for impact review and scheduling at a
checkpoint.

## Milestone 1: deletion and media download

### Delete one identification

- Permanently delete one identification after an explicit confirmation. Preserve
  other versions, scan notes, collections, and observation identity.
- Require users to select another version before deleting the current one.
  Consequently, the last remaining version cannot be individually deleted;
  whole-scan deletion remains separate.
- Allow deletion of earlier versions, including the initial saved version, even
  when surviving versions were derived from them.
- Remove the deleted version’s private history content. Preserve minimal
  internal deletion/provenance records and media still required by surviving
  owners. Never cascade-delete later identifications.
- Use an authenticated, revision-checked, idempotent deletion operation.
  Synchronization, completion, recovery, and retries must not resurrect the
  version.
- Temporarily block deletion while conflicting operations remain unresolved,
  with an actionable explanation. Require connectivity to commit deletion;
  reconcile uncertain outcomes before retrying.
- If the version backs a community post, preserve the discussion and mark its
  identification unresolved under existing publication rules. Explain this
  consequence in the confirmation. Existing chat messages retain their
  established retention behavior; deletion must not silently rewrite
  conversations.

### Download source media

- Include photo, audio, and video support in this milestone. Text-only versions
  have no download action unless they have associated retained source media.
- Export the retained source assets associated with the chosen version—not
  generated frames, thumbnails, or processing artifacts presented as originals.
- Support multiple source assets through a selection step. Use the system share
  sheet for export, including Save to Files and supported Photos destinations.
- Resolve media through owner-authorized delivery. Validate access and asset
  identity; never infer availability from a thumbnail.
- Preserve source assets required by live history under the existing observation
  retention contract. For older entries whose originals are missing, explain
  that they are unavailable; do not reconstruct substitutes.
- Provide progress, cancellation, retry, and temporary-file cleanup.

### Interfaces and storage

Add version-deletion operations and per-version action/export capabilities to
the existing history contracts, with corresponding native models. Capabilities
must express availability and refusal reasons.

Introduce the necessary deletion records and media-retention relationships
without weakening immutable result history. Update backend schemas, generated
DTOs, native persistence where required, and canonical documentation together.

## Milestone 2: Identification sheet and History redesign

### Identification sheet

- Rename the Confidence sheet to **Identification**.
- Replace the large confidence heading with the sheet header, close control, and
  overflow menu shown in the design.
- Introduce a shared identification card containing confidence, current status,
  timestamp, thumbnail, and species names.
- Preserve the existing alternatives card layout and confidence-calculation
  policy.
- Show confirmation/incorrect states with revision-safe Undo.
- Use slide gestures for all four colored primary actions: **Confirm**, **Mark
  as incorrect**, **Reanalyze**, and **Ask the community**. Provide accessible
  activation alternatives.
- Sliding confirm/incorrect submits that review action. Sliding
  reanalyze/community opens the existing preparation flow; it does not bypass
  consent, editing, or publication steps.
- Show actions according to the viewed version’s supported capabilities.
  Including video deletion/download does not introduce video confirmation or
  reanalysis.

### History page

- Open a separate History page from the Identification toolbar menu.
- Pin the current identification first; order remaining versions newest first.
- Reuse the identification card and provide per-version action menus.
- Tapping a card opens the same Identification layout scoped to that historical
  version, including its saved alternatives and explanations where available.
- Opening or confirming a historical version never makes it current. Provide a
  separate **Use this identification** action.
- Bind every action and asynchronous result to the exact observation, version,
  and account. Missing historical details must not be borrowed from the current
  result.
- Include loading, empty, unavailable-media, pending, conflict, and failure
  states.

## Validation and acceptance

- Delete an earlier version while preserving descendants, their media, and the
  current identification.
- Reject current/last-version deletion; verify deletion after an acknowledged
  selection change.
- Exercise duplicate requests, interrupted responses, stale revisions,
  concurrent selection/reanalysis, account switching, and late recovery after
  deletion.
- Verify community authority invalidation preserves discussion and cannot be
  reversed by stale jobs.
- Export retained photo, audio, and video sources; test multiple assets, missing
  originals, unauthorized access, cancellation, and cleanup.
- Verify historical details and review actions target the opened version;
  confirmation remains separate from selection.
- Test sliders, accessible alternatives, Undo conflicts, Dynamic Type,
  VoiceOver, and navigation against the supplied mockup.
- Run required migration, backend contract, native, and affected public-consumer
  gates. Keep installation and release controls unchanged until separately
  authorized.

## Boundaries and defaults

The mockup guides the visual redesign; unrelated field notes, collections, main
scan layout, and whole-scan deletion are outside this change. Permanent deletion
has no Undo; review and selection retain their existing conditional Undo
behavior.

The first milestone is complete only when deletion and source export are
qualified across photo, audio, and video. The visual redesign follows those
capabilities.

## Recorded handoff and scope boundary

Status: approved future work, recorded October 11, 2026. History primary remains
the sole implementation writer. The current IC-1/S0 and alpha-readiness scope
takes precedence; external-only blockers remain explicitly open and do not
silently reorder these milestones. Broader initial-engine hardening remains
separately owned under IC-1. No push, deployment, activation, installation or
distribution is authorized.

The source is the human-approved plan in planning thread
`01a12460-a2c6-7b21-abcf-d3be41331b45`, handed to history thread
`01a0fe55-d9d3-77e0-90a5-b7eeeaaa74e1`. Requirements above are transcribed
without changing their scope. The visual reference is retained locally at
`.artifacts/identification-history-version-actions/reference.png`; it guides
presentation, not permissions or lifecycle semantics. A capability and evidence
matrix with concrete owners/pass conditions must precede implementation of each
milestone. Impact review belongs at the next safe checkpoint and must identify
required changes to descendant-safe provenance, shared-media retention,
publication authority, closed capabilities and exact historical native action
routing. No such implementation or qualification is claimed by recording this
plan.
