# Insight Field Notes

The `FieldNotes` directory owns private observation notes presented from Insight
and the optional visibility editor used by an owned Explore publication.

The canonical product and lifecycle contract remains
[Insight Sheet](../../../../../../docs/features-and-hardware/05-insight-sheet.md).
This README defines the Field Notes submodule's source, effect, and test
boundaries.

## Ownership

- `Models/` owns platform-neutral prompt, edit-diff, visibility-request, and
  feedback values. Models must not import SwiftUI, SwiftData, or live services.
- `Services/` is the only Field Notes owner that resolves live persistence,
  speech, or haptic effects. `InsightFieldNotesDependencies` adapts the
  Core-owned `FieldNotesRepository`; `FieldNotesEditorDependencies` adapts the
  environment-provided `SpeechManager`; and `FieldNotesVisibilityConfiguration`
  carries the caller's existing Explore visibility save action.
- `ViewModels/` owns the observable editor draft, save state, validation,
  dictation session, and the Field Notes extension on the Shell-owned
  `InsightSheetViewModel`. The extension preserves scan-ID and presentation-
  generation checks for queued and completed observations.
- `Views/` owns composition, focus, actual dismissal, interactive-dismissal
  autosave scheduling, and confirmation-overlay presentation. The stable
  `FieldNotesSheet` initializer remains the feature entry point.
- `Components/Card/` owns the Insight card and its Published/Private badge.
  `Components/Editor/` owns render-only text-editor, visibility, dictation, and
  clear-confirmation pieces.

Views and components perform no networking and resolve no persistence or haptic
singleton. Every production Swift file in this directory must remain at or below
the 600-line review guard. Wire DTOs and Explore endpoint calls remain in their
existing owners; this organization pass does not change payload,
persistence-schema, navigation, copy, accessibility, or feature-flag contracts.

## Persistence And Visibility

`FieldNotesRepository` remains Core-owned because it reconciles three storage
surfaces shared by Insight and Explore: `LocalScanRecord.fieldNotes`,
`OfflineQueuedScan.fieldNotes`, and the legacy `FieldNotesStore` bridge. Field
Notes Services expose only the narrow closures needed by the feature.

The editor snapshots its initial text and effective visibility. An unchanged
draft is a no-op. A changed draft commits once to the caller's binding, and an
optional visibility action receives the exact text plus effective public state.
Clearing text also clears effective visibility. A failed explicit visibility
save leaves the editor mounted with its existing inline error; a changed draft
dismissed interactively commits locally and schedules the same visibility
action. Disappearance does not duplicate an active explicit save.

Queued and completed Insight presentations retain the existing scan-ID plus
generation fence. A stale callback cannot save notes, dismiss the card, or
promote public Explore notes into a replacement observation. Public notes may
repair an empty local copy, but never overwrite existing private/local text.

## Dictation Lifecycle

`FieldNotesEditorViewModel` owns one generation-fenced dictation session. Each
result is composed against the stable text present when that session began.
Explicit stop and automatic speech termination invalidate pending and active
callbacks. Automatic termination clears editor ownership without redundantly
stopping the already-ended shared session. A replacement start waits for
canceled startup teardown before entering the shared `SpeechManager`, so a late
predecessor cannot stop or publish into the replacement session. The editor
stops only a session it owns and retains the established retryable permission/
unavailable error presentation.

Focus, keyboard dismissal, confirmation animation, and the final SwiftUI
`dismiss()` call deliberately stay in `FieldNotesEditorView` so extracting state
does not alter UI timing.

## Verification

Tests mirror the final owners:

- `MerianTests/Features/Insights/FieldNotes/FieldNotesEditPolicyTests.swift`
  locks normalized content/visibility diff and feedback policy;
- `FieldNotesEditorViewModelTests.swift` locks commits, autosave, failure,
  clearing, stable-baseline composition, automatic-termination late-result
  rejection, ownership-safe stop, and overlapping dictation lifecycles;
- `InsightFieldNotesStateTests.swift` locks queued/completed identity and
  injected persistence/feedback forwarding;
- `FieldNotesArchitectureTests.swift` enforces folder ownership, Services-only
  live effects, the view networking ban, aggregate removal, and the 600-line
  ceiling;
- `MerianTests/Core/Utilities/FieldNotesRepositoryTests.swift` owns storage
  reconciliation; and
- `MerianTests/Features/Insights/Sharing/InsightSharingCacheRefreshTests.swift`
  owns Share-cache refresh behavior formerly mixed into Field Notes tests.

After changing this folder, regenerate the project and run the iOS project,
source-membership, event-routing, focused Field Notes, Core repository, and
Sharing cache suites. Manual regression must cover private/public notes,
unchanged dismissal, explicit and swipe autosave, failed visibility save,
queued-scan replacement, dictation stop/restart and automatic termination,
VoiceOver labels, and large Dynamic Type.
