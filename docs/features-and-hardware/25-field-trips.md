# Field Trips

Field Trips are Explore-adjacent checklist quests for finding species and
ecological categories in a neighborhood, park, state, national park, or other
regional environment. They are separate from low-power Expedition Mode, which is
only a camera/performance setting.

## V1 Scope

- Field Trips live under Explore in `apps/ios/Merian/Features/Explore/FieldTrips/`.
- Templates are curated in Supabase with region, season, habitat, difficulty,
  rotating-free, and Pro access tags.
- Levels unlock sequentially. A scan can complete an item only after the user
  has started that Field Trip.
- New scans can auto-start an eligible Field Trip when the scan matches a
  current-level item.
- A checklist item can match by species, scientific name, taxonomy, ecology,
  habitat text, or dictionary group tag.
- AI matches and later user confirmations/corrections both call the progress
  updater.

## Privacy Model

Active Field Trip progress is visible on public profiles by default, but it is
status-only:

- template title
- current level
- completed count
- target count
- checklist item labels

Active profile summaries must not expose scan IDs, media URLs, field notes,
exact coordinates, public location labels, or private evidence details.

Published Field Trip pages are explicit snapshots stored separately from
Explore posts. Publication items may include species names, taxonomy, reference
images, and selected scan media snapshots, but publishing a Field Trip does not
create Explore feed posts, Explore map points, or normal Explore notifications.

## Backend

Field Trip storage is created by
`services/supabase/migrations/20260708021110_field_trips_v1.sql`.

Core tables:

- `field_trip_templates`
- `field_trip_levels`
- `field_trip_checklist_items`
- `user_field_trips`
- `user_field_trip_item_completions`
- `field_trip_publications`
- `field_trip_publication_items`
- `field_trip_publication_likes`
- `field_trip_publication_comments`

The `/field-trips` Edge Function exposes action-based API modes for catalog,
scan progress, profile summaries, publication detail, publishing, likes, and
comments. Field Trip comments are stored separately from Explore comments, but
the client presents them with the same compact comment pattern.

## Access

Free users see starter and rotating-free trips. Pro users can access the full
active catalog. Locked Pro trips may still appear in the catalog so the UI can
show the available upgrade path without starting progress.

## Deferred

V1 intentionally excludes leaderboards, prizes, sponsored trips, regional
rankings, and reward eligibility. Those require stronger verification, abuse
controls, moderation policy, and legal/eligibility rules.
