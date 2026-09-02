# Profile Shared

The `Shared` directory contains state used by more than one Profile product
area, such as both `UserProfile` and `Settings`.

## Structure

- **ViewModels** contains shared state owners such as `ProfileViewModel.swift`.

## Purpose

Code belongs in `<Feature>/Shared` only when multiple Profile product areas use
it and the type does not warrant promotion to app-wide `Core`.
`ProfileViewModel` owns the active account's shared identity and cloud
preference values, including the `defaultGeoprivacy` value displayed by
Settings. It does not own the Settings interaction lifecycle: Settings-owned
observable state coordinates serialized geoprivacy writes, export, notification,
survey, plan, sign-out, and deletion presentation.

`Profile/Shell` composes environment-owned dependencies. `UserProfile` and
`Settings` consume the shared values but retain their own Services, ViewModels,
Views, and Components.

`ProfileViewModel.fetchSocialStats()` still calls `getExploreAuthorProfile` with
`previewLimit: 0` and maps the returned owner publication summary into Profile
state. That stateless request now lives in
[Core Network's Explore browsing extension](../../../Core/Network/README.md#explore-browsing-endpoints).
The transport extraction does not relocate the shared account owner, its live
client resolution, or identity/preference mutations into UserProfile Services.

Username/display-name/avatar update and username-availability wire requests live
in
[Core Network's public-profile extension](../../../Core/Network/README.md#public-profile-endpoints).
`ProfileViewModel` still orchestrates the calls and publishes shared identity
values/events. The endpoint owner forwards raw values and returns server
projections; it does not own editor validation, account state, or avatar upload.
`PublicProfileEndpointTests` and
`NotificationAndPublicProfileEndpointTransportTests` own wire/transport
coverage. `ProfileViewModelTests` retains shared-state coverage; run the
[notification/public-profile matrix](../../../Core/Network/README.md#notification-and-public-profile-verification)
when changing this boundary.

## Avatar upload contract

`ProfileViewModel` prepares one bounded square WebP/JPEG data item and requests
`/generate-upload-urls` with its exact positive `sizeBytes`. It accepts only a
matching signed response whose `requiredHeaders` map contains exactly the
declared `Content-Type` and decimal `Content-Length`, applies both to the data
PUT, then passes the returned owner-scoped staging key to
`/update-public-avatar`. The client never reconstructs a staging key or uses the
removed legacy no-size request. A malformed header map, wrong owner/key, upload
failure, or promotion failure does not update the visible avatar.
