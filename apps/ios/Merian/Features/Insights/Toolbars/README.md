# Insight Toolbars

The `Toolbars` directory manages the persistent navigational and action controls
within an Insight.

## Purpose

This area contains the floating or pinned action bars that allow users to
dismiss the sheet, trigger a share, open the field chat, or save field notes. It
separates the persistent interaction chrome from the scrollable biological
content.

## Leading-control accessibility contract

`TopToolbar.LeadingControl` keeps its user-facing VoiceOver labels (`Close` and
`Back`) separate from stable automation identifiers. The modal close control is
`InsightSheetCloseButton`; the embedded-navigation control is
`InsightSheetBackButton`.

UI tests must resolve those identifiers through the current `InsightSheetView`
instead of using a global label query. SwiftUI can keep an underlying
presentation in the accessibility tree, so `app.buttons["Close"]` may resolve
more than one control and dismiss the wrong layer. The identifiers belong on the
native toolbar buttons so the same contract covers analyzing, queued, and
completed Insight presentations.

## Queued deletion continuity

`TopToolbar` owns exactly one `.topBarTrailing` item throughout analyzing and
queued presentation. A clear, non-control 44-point placeholder reserves that
item's layout while analyzing. The native queued delete `Button` is not mounted
until the shell has an exact durable queued scan ID; this prevents iOS 26 from
drawing empty toolbar glass before the handoff. Binding that ID sets
`showsQueuedDeleteAction`, inserts the button with a 0.2-second opacity
transition, and exposes `InsightQueuedDeleteButton` without inserting a second
native toolbar item or relaying out the sheet.

The fade changes presentation only. Tapping the visible button still enters the
queued deletion confirmation and its **Cancel upload & delete** action; queue
ownership, persistence, file cleanup, and retry semantics remain with the
existing deletion path. Completed Insights continue using the ordinary actions
menu in this same trailing slot.
