# Shared Map Navigation

Core Maps owns place-search service adapters, cancellable search presentation
state, and one-shot locate request admission shared by Explore Map and private
Scan Map. Product camera/data ownership remains in those features. The current
contract is
[Shared map navigation](../../../../../docs/features-and-hardware/24-explore-bottom-menu.md#shared-map-navigation).

`MapPlaceSearchDependencies` injects autocomplete, completion resolution,
full-text search, and debounce. The live adapter uses MapKit without receiving
scan points, current location, or viewport hints. Every autocomplete request
owns its own delegate; cancellation detaches it and resumes its continuation
once. Search models reject superseded and dismissed requests, account changes,
and account-purge generations. `MapNavigationModel` separately retires delayed
one-shot location requests when a newer navigation or user gesture occurs.

`MapNavigationPresentation` in `Core/UI/Components/Maps` coordinates sheet
dismissal, owner changes, and location feedback alongside the reusable views;
account-keyed recent labels and the device style preference live in
`Core/Preferences`. `AppDIContainer` injects the live configuration. The
existing Debug-only private map fixture injects synthetic search results and
isolated history defaults.

No map query, result text, coordinate, scan identifier, or MapKit response is
logged or sent to Merian services by this domain. Selected place labels alone
may be stored by the recent-place preference owner. The tests are
`MapNavigationTests`, `MapPreferencesTests`, and both feature map suites.
