# Geoprivacy

Geoprivacy controls how much scan-location context can be shown in local UI,
shared UI, Explore, public map data, and public exports.

## Modes

| Mode | Owner-facing local scan UI | Public/public-share projection |
|---|---|---|
| `open` | Shows location label, elevation, weather, and exact map marker when telemetry exists. | May publish exact public coordinates and a sanitized public location label. |
| `obscured` | Shows a coarse location label, weather, and a rounded map region with a 10 km uncertainty circle. Elevation is hidden. | Publishes rounded public coordinates and a sanitized public location label with `coordinate_uncertainty_in_meters >= 10000`. |
| `private` | Hides location label, elevation, weather, and map from scan-information surfaces. | Clears public coordinates, public uncertainty, and public location labels; private scans are excluded from Explore share/public feeds. |

`users.default_geoprivacy` is the preference source of truth. New scans send the
current setting in the identify request where possible, and Edge insert helpers
fall back to `users.default_geoprivacy` for older clients or queued jobs that do
not include an explicit value.

## Backend Contract

The identify stack accepts an optional `geoprivacy` field on visual,
multimodal, describe, and audio requests. The shared insert helper resolves
that field through `resolveScanGeoprivacy(userId, supabaseAdmin, explicit)`:

1. Valid explicit values (`open`, `obscured`, `private`) are preserved.
2. Missing or invalid values read `users.default_geoprivacy`.
3. Missing or invalid user defaults fall back to `open`.
4. Lookup errors fail the insert instead of silently applying the wrong privacy.

For `private`, insert helpers also write `public_location_label = NULL` even if
an old client accidentally sends a label. The database trigger
`trg_set_scan_public_location_label` provides the durable guard on insert and
on updates to `public_location_label`, `semantic_location`, or `geoprivacy`.

Changing `users.default_geoprivacy` retroactively updates that user's scans via
`trg_sync_user_default_geoprivacy_to_scans`. The scan update re-runs the public
coordinate trigger and public-label trigger:

- moving to `private` clears public coordinates, uncertainty, and public label;
- moving to `obscured` restores rounded public coordinates and a sanitized
  public label from `semantic_location`;
- moving to `open` restores exact public coordinates when exact GPS exists and
  species-safety rules allow it.

## iOS Surfaces

Local owner-facing privacy uses `ProfileViewModel.defaultGeoprivacy` for
visibility decisions:

- `ScanInformationCard` hides private location/elevation/weather/map, rounds
  obscured coordinates, and shows exact owner-facing context only for `open`.
- `InsightBottomToolbar` passes no public location label to the Explore composer
  or hashtag suggestions when privacy is `private`.
- `AchievementContributionRow` hides private contribution locations in metadata
  and accessibility labels; `obscured` uses the sanitized public label.
- `MessageScanShareCacheWriter` writes App Group Messages share captions without
  location for `private`; `obscured` stores the sanitized public label.
- `MerianNetworkClient` sends `geoprivacy` with identify payloads and omits
  `publicLocationLabel` for private scans.

Local SwiftData still stores exact telemetry owned by the user. Do not treat
`LocalScanRecord.locationName`, `gpsLatitude`, or `gpsLongitude` as display-safe
without checking the current geoprivacy mode at the UI boundary.

## Public Boundaries

Explore read RPCs and share-state helpers exclude private scans. Public map
points read only `gps_lat_public` / `gps_long_public`, never exact coordinates.
Global Darwin Core exports include only open public records; personal exports
may include the user's own exact telemetry when they request their own archive.

When adding a new public, shared, widget, extension, notification, or export
surface, use this checklist:

- never read exact GPS for public responses;
- exclude `geoprivacy = 'private'` from public/shareable result sets;
- use `public_location_label` only after the DB trigger has scrubbed it;
- use `gps_lat_public`, `gps_long_public`, and
  `coordinate_uncertainty_in_meters` for map display;
- gate local owner-facing text/map rendering through `defaultGeoprivacy`;
- add a test for private hide and open/obscured restore behavior.

## Verification

Focused backend coverage lives in:

- `services/supabase/functions/_shared/identify/db_test.ts`
- `services/supabase/functions/_tests/geoprivacyDb.test.ts`

Use `deno test`, `deno check`, `deno lint`, `swiftlint lint`, and an Xcode
build for implementation changes. `geoprivacyDb.test.ts` requires a running
local Supabase/Postgres instance on the configured test port; otherwise it
skips with a connection-refused message.
