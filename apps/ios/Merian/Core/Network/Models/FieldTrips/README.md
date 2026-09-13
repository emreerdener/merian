# Field Trips network models

This directory owns the Codable, request-value, and typed endpoint-result models
shared by the Field Trips endpoint and its Explore, Capture, Insights, Profile,
Offline Sync, and milestone-feedback consumers.

## Owners

- `FieldTripCatalogAPIModels.swift` owns template, level, checklist, guide, and
  catalog/detail/start response contracts.
- `FieldTripCaptureAPIModels.swift` owns capture context, preferred-goal, and
  saved-scan contribution contracts.
- `FieldTripProgressAPIModels.swift` owns progress responses, endpoint result
  projection, standard/Event updates, and completed-item contracts.
- `FieldTripAchievementAPIModels.swift` owns the first-Field-trip achievement
  wire response and persisted Codable value.
- `FieldTripProfileAPIModels.swift` owns active, pinned, published, and Event
  badge profile-summary contracts.
- `FieldTripPublicationAPIModels.swift` owns outing publication, detail,
  comment, and like contracts.
- `FieldTripChallengeAPIModels.swift` owns Event catalog, participation, entry,
  detail, hashtag, and like contracts. Backend `Challenge` names remain intact.
- `FieldTripCommunityQueryModels.swift` owns the request mode shared by the
  Field Trips community feed and Explore feed integration.

These files contain no live networking, persistence, task, observable-state, or
presentation ownership. Every production Swift owner remains below 600 lines.
The retired `Core/Network/FieldTripAPIModels.swift` aggregate must not return.

## Related ownership

- `Features/Explore/FieldTrips/Models` owns lifecycle, guide, publication,
  community-mode, catalog, media, date, profile, and other UI presentation.
- `Features/Insights/Shell/Models/FieldTripScanContributionPresentation.swift`
  maps contribution DTOs to the Insights-owned overview route.
- `Core/UI/Feedback/Policies` owns credited progress display and
  first-Field-trip achievement projection into milestone/award values.
- `Core/Preferences/Stores/FirstFieldTripAchievementProgressStore.swift` owns
  the account-qualified `UserDefaults` compatibility cache.
- `Core/Network/Endpoints/MerianNetworkClient+FieldTrips.swift` owns request
  construction and typed response mapping over the shared transport.

`FieldTripNetworkModelArchitectureTests` freezes this eight-file inventory,
production-wide single declaration ownership, effect exclusions, relocated
responsibilities, retired aggregate, and 600-line ceiling.
`FieldTripAPIModelsTests` retains JSON decoding and compatibility coverage.
`FirstFieldTripProgressStoreTests` owns normalized account isolation,
persistence round trips, and invalid cached-value rejection for the separately
owned compatibility store. The canonical product and verification contract is
[`docs/features-and-hardware/25-field-trips.md`](../../../../../../../docs/features-and-hardware/25-field-trips.md).
