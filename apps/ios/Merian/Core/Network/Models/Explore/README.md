# Explore Network Models

This directory owns Explore-related Codable responses and endpoint request
values that are shared by Core networking and more than one product area.
Endpoint construction remains under `Core/Network/Endpoints/`; feature loading,
mutation, presentation, and lifecycle state remain with their feature ViewModels
and Services.

Ownership is split by contract family:

- `ExploreBrowsingAPIModels.swift` and `ExploreBrowsingQueryModels.swift` own
  public-post media, browsing envelopes, filters, and pagination values.
- `CommunityIdentificationAPIModels.swift`,
  `ExploreAuthorProfileAPIModels.swift`, and `ExploreMapAPIModels.swift` own
  their corresponding decoded contract families.
- `ExplorePostDetailAPIModels.swift`, `ExploreCommentAPIModels.swift`, and
  `ExploreSharingAPIModels.swift` own detail, interaction, and publication state
  responses.
- `ExploreLocationSharingAPIModels.swift` owns the shared Codable post-location
  mode. Its labels, symbols, and explanatory copy live in Explore Shared
  presentation rather than in the wire contract.
- `ExploreMediaIncidentAPIModels.swift`, `ExploreNotificationAPIModels.swift`,
  `PublicProfileAPIModels.swift`, and `CommunityFeedbackAPIModels.swift` own the
  remaining narrow endpoint contracts.

These files contain no network client, persistence, singleton, task, or
observable-state ownership. Every production Swift file in this directory stays
at or below 600 lines. The retired `Core/Network/ExploreAPIModels.swift`
aggregate must not return.

`ExploreLocationSharingAPIModelsTests` locks the post-location raw values and
compatibility decoding. `ExploreNetworkModelArchitectureTests` locks the model
inventory and layered wire/presentation placement.

Cross-feature semantic-location redaction belongs to
`Core/Models/ExploreLocationPrivacy.swift`, not to a wire DTO. The canonical
payload and response contract remains
[`docs/backend-and-data/05-api-contracts.md`](../../../../../../../docs/backend-and-data/05-api-contracts.md).
