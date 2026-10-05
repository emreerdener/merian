# Identification history

Prepared, injection-only history presentation. Normal Shell access is nil;
`IdentificationHistoryAccess.prepared` has no ordinary call site. Only the
explicit Debug UI-test fixture currently opens this screen.

- `Models` maps each result's own display and authority to bounded rows/details.
- `Services` owns the account-session adapter to Core listing, preview,
  selection/Undo and private image resolution. It never writes projections.
- `ViewModels` owns one page, one preview, pending/retry state, receipt-bound
  Undo and cancellation. Acknowledged state changes alone refresh the parent
  Insight and invalidate authority-bearing rows/details. Delayed pages/previews
  must still match current context before presentation; selection acknowledgment
  refreshes the newest bounded page without making its success depend on that
  read.
- `Views` renders a native list/preview in Shell's existing modal slot. Opening
  a row never chooses it; Use this identification is explicit.

Back cannot abandon an active selection dispatch. Optional alternatives from an
incompatible legacy candidate schema are omitted without blocking a valid saved
identification preview.

Core owns persisted fences and selection transactions. Shell owns
scan-generation admission and teardown; Toolbars receives only an optional
action. There is no ordinary enrollment, sync scheduling, public update or
reanalysis activation in this feature.

A prepared access assembler may explicitly inject `AppRouteRequesting` through
`prepared(routes:)`. Its callback constructs only the exact
`historicalReanalysis` route with `internalUserAction` origin. Only then does a
validated preview expose **Reanalyze from this identification**. The session
derives capability from the exact immutable local source and current
owner/context, independently of current selection and inference consent. Missing
source, pending selection or invalid context hides the action without removing
read-only preview. The action never calls ordinary refinement, funding,
selection or inference.

Shell stages one handoff with the originating scan and presentation generation,
then dismisses the nested sheet. Its exact dismissal callback consumes the
handoff once, revalidates account generation, observation context and immutable
source, and invokes the injected historical route callback. Root routing then
owns dismissal of Insight before opening Capture. Changed parent presentation,
account, revision, deletion or source suppresses dispatch; no delay timer is
used. The handoff retains immutable values and no account-work lease. Dismissed
history closes its session and private presentation; an explicitly staged action
has its own bounded validation closure for the dismissal boundary. Ordinary
history and Capture access remain nil. UI fixtures contain synthetic values and
call no live provider.

The canonical
[product and lifecycle contract](../../../../../../docs/features-and-hardware/05-insight-sheet.md#prepared-identification-history-sheet)
owns paging, offline limitations, preview content, memory limits and user copy.
The
[Core boundary](../../../Core/Data/AnalysisHistory/README.md#prepared-bounded-listing-and-presentation)
owns persistence and authority. Verification lives in
`IdentificationHistoryViewModelTests`, `IdentificationHistoryReanalysisTests`,
`ObservationHistoryListingTests` and `IdentificationHistoryUITests`; the runtime
audit manifest registers the UI flow.
