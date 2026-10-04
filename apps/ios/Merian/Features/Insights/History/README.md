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
reanalysis activation in this feature. UI fixtures contain synthetic values and
call no live provider.

The canonical
[product and lifecycle contract](../../../../../../docs/features-and-hardware/05-insight-sheet.md#prepared-identification-history-sheet)
owns paging, offline limitations, preview content, memory limits and user copy.
The
[Core boundary](../../../Core/Data/AnalysisHistory/README.md#prepared-bounded-listing-and-presentation)
owns persistence and authority. Verification lives in
`IdentificationHistoryViewModelTests`, `ObservationHistoryListingTests` and
`IdentificationHistoryUITests`; the runtime audit manifest registers the UI
flow.
