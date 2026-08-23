# Geoprivacy

Geoprivacy controls how much scan-location context can be shown in local UI,
shared UI, Explore, public map data, and public exports.

## Modes

| Mode       | Owner-facing local scan UI                                                                                                                                                                              | Public/public-share projection                                                                                                                                                                                                                                           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `open`     | Insight may show location label, elevation, weather, and an exact marker. The dedicated owner-only Scan map also shows the exact saved point.                                                           | May publish exact public coordinates and a sanitized public location label.                                                                                                                                                                                              |
| `obscured` | Insight shows a coarse label, weather, and a rounded region with a 10 km uncertainty circle; elevation is hidden. The dedicated owner-only Scan map still shows the exact saved point.                  | Publishes rounded public coordinates and a sanitized public location label with `coordinate_uncertainty_in_meters >= 10000`; Explore posts default to `obscured` location sharing and stay off the Explore Map unless the author explicitly changes that post to `open`. |
| `private`  | Insight hides location label, elevation, weather, and its map. The separate owner-only Scan map still shows the exact saved point because it is a private library index rather than a share projection. | Clears scan public coordinates, public uncertainty, and public location labels; Explore posts default to `private` location sharing but can be explicitly changed per post.                                                                                              |

Audio-only, description-only, and other non-visual captures resolve the cached
capture coordinate through the same environment-context path used by camera
captures before persistence. This ensures a sanitized location label is
available if the scan or an Explore post later uses `open` or `obscured`
sharing. Changing a post from `private` to `open` cannot invent a missing label;
legacy rows with exact coordinates but no `semantic_location` must first be
repaired with `services/supabase/scripts/retroactive_geocoding.ts`.

`users.default_geoprivacy` is the preference source of truth. New scans send the
current setting in the identify request where possible, and Edge insert helpers
fall back to `users.default_geoprivacy` for older clients or queued jobs that do
not include an explicit value.

## Backend Contract

The identify stack accepts an optional `geoprivacy` field on visual, multimodal,
describe, and audio requests. The shared insert helper resolves that field
through `resolveScanGeoprivacy(userId, supabaseAdmin, explicit)`:

1. Valid explicit values (`open`, `obscured`, `private`) are preserved.
2. Missing or invalid values read `users.default_geoprivacy`.
3. Missing or invalid user defaults fall back to `open`.
4. Lookup errors fail the insert instead of silently applying the wrong privacy.

For `private`, insert helpers also write `public_location_label = NULL` even if
an old client accidentally sends a label. The database trigger
`trg_set_scan_public_location_label` provides the durable guard on insert and on
updates to `public_location_label`, `semantic_location`, or `geoprivacy`.

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
- `PrivateScanMapView` is a deliberate owner-only exception to the Insight
  presentation rule. It projects every completed local biological scan with
  valid GPS at its exact saved coordinate, independent of scan geoprivacy,
  Explore publication, or post-level location sharing. Its passive Collections
  preview does not request live location; only the interactive page does. The
  exact exception, prohibited data paths, and acceptance matrix are defined in
  [Private Scan Map](./28-private-scan-map.md).
- `InsightBottomToolbar` seeds the Explore composer location option from
  `defaultGeoprivacy`. The composer can override that one post to `open`,
  `obscured`, or `private`.
- `AchievementContributionRow` hides private contribution locations in metadata
  and accessibility labels; `obscured` uses the sanitized public label.
- `MessageScanShareCacheWriter` writes App Group Messages share captions without
  location for `private`; `obscured` stores the sanitized public label.
- `MerianNetworkClient` sends `geoprivacy` with identify payloads and omits
  `publicLocationLabel` for private scans.
- Automatic camera-roll saves remain an owner-controlled local Photos export,
  not a public projection. When that separate default-off preference is enabled,
  the established capture behavior assigns the resolved shutter location to the
  Photos asset regardless of public geoprivacy. Explicit later Downloads do not
  inject `LocalScanRecord` telemetry into the exported asset. See
  [Camera Roll and Captured-Media Export](./27-camera-roll-media-export.md).

Local SwiftData still stores exact telemetry owned by the user. Do not treat
`LocalScanRecord.locationName`, `gpsLatitude`, or `gpsLongitude` as display-safe
without checking the current geoprivacy mode at the UI boundary, except inside
an explicitly reviewed owner-only surface such as the dedicated Scan map.

## Public Boundaries

Explore read RPCs expose public posts regardless of the backing scan's current
geoprivacy, as long as the post remains otherwise eligible. Public location is
controlled by `explore_posts.location_sharing`: `private` clears public location
fields, `obscured` can show a scrubbed label while staying off-map, and `open`
projects post-owned public map coordinates. Open posts may still render
approximate map points when species-safety or uncertainty rules round the public
projection. Nearby uses the same post-owned public coordinate projection for
spatial matching, so non-owned `obscured` and `private` posts remain out of
Nearby while still being eligible for non-spatial Explore feeds. Global Darwin
Core exports snapshot membership from records that are open when the job is
created; occurrence and multimedia phases must match that creation-time
eligibility revision. Personal exports may include the user's own exact
telemetry when they request their own archive.

Field trips have a separate public-profile boundary:

- active Field trip progress can appear on public profiles by default, but only
  as checklist status;
- automatic Backyard Safari Level 1 enrollment creates that profile-visible
  status immediately, including at `0/N` progress; stopping or resetting the
  unfinished outing hides the active summary;
- active summaries must not expose scan IDs, media URLs, field notes, exact
  coordinates, public location labels, or private evidence;
- publishing a Field trip creates a Field trip snapshot, not an Explore post;
- published Field trip pages may show selected snapshot media/species cards but
  do not create Explore feed cards, Explore map points, normal Explore post
  notifications, APNs, widgets, public web share pages, or change scan
  geoprivacy.
- Seasonal Challenge participation is private by default. Challenge badges are
  evidence-free profile cards, and challenge entries are Field trips-native
  snapshots that follow the same no-Explore-feed/no-map/no-widget boundary.

When adding a new public, shared, widget, extension, notification, or export
surface, use this checklist:

- never read exact GPS directly in public read RPCs;
- keep active Field trip profile summaries status-only;
- keep Field trip Challenge badges evidence-free and challenge entries scoped to
  Field trips surfaces;
- keep public Explore post visibility separate from scan geoprivacy;
- require `explore_posts.location_sharing = 'open'` for public spatial result
  sets such as Explore Map and non-owned Nearby matches;
- use post-owned `public_location_label` only after the DB trigger has scrubbed
  it;
- use post-owned `public_latitude`, `public_longitude`, and
  `public_coordinate_visibility` for Explore Map display and Nearby spatial
  matching;
- gate ordinary Insight owner-facing text/map rendering through
  `defaultGeoprivacy`;
- keep any exact-coordinate exception confined to a current-owner-only surface
  and independent from public DTOs, APIs, caches, logs, and telemetry;
- add a test for private hide and open/obscured restore behavior.

## Verification

Focused backend coverage lives in:

- `services/supabase/functions/_shared/identify/db_test.ts`
- `services/supabase/functions/_tests/geoprivacyDb.test.ts`

Use `deno test`, `deno check`, `deno lint`, `swiftlint lint`, and an Xcode build
for implementation changes. `geoprivacyDb.test.ts` requires a running local
Supabase/Postgres instance on the configured test port; otherwise it skips with
a connection-refused message.

Private Scan Map changes additionally require the local exact-coordinate tests,
Debug UI fixture/Release-marker boundary, and owner-only manual privacy matrix
in the
[Private Scan Map verification contract](./28-private-scan-map.md#verification-contract).
