# Insight Toolbars

The `Toolbars` directory manages the persistent navigational and action controls within an Insight.

## Purpose
This area contains the floating or pinned action bars that allow users to dismiss the sheet, trigger a share, open the field chat, or save field notes. It separates the persistent interaction chrome from the scrollable biological content.

## Leading-control accessibility contract

`TopToolbar.LeadingControl` keeps its user-facing VoiceOver labels (`Close` and
`Back`) separate from stable automation identifiers. The modal close control is
`InsightSheetCloseButton`; the embedded-navigation control is
`InsightSheetBackButton`.

UI tests must resolve those identifiers through the current `InsightSheetView`
instead of using a global label query. SwiftUI can keep an underlying
presentation in the accessibility tree, so `app.buttons["Close"]` may resolve
more than one control and dismiss the wrong layer. The identifiers belong on
the native toolbar buttons so the same contract covers analyzing, queued, and
completed Insight presentations.
