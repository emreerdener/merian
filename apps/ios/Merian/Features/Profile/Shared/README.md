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

## Avatar upload contract

`ProfileViewModel` prepares one bounded square WebP/JPEG data item and requests
`/generate-upload-urls` with its exact positive `sizeBytes`. It accepts only a
matching signed response whose `requiredHeaders` map contains exactly the
declared `Content-Type` and decimal `Content-Length`, applies both to the data
PUT, then passes the returned owner-scoped staging key to
`/update-public-avatar`. The client never reconstructs a staging key or uses the
removed legacy no-size request. A malformed header map, wrong owner/key, upload
failure, or promotion failure does not update the visible avatar.
