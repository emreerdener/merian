# update-explore-field-notes

Updates the public share options on an existing Explore post owned by the
current user. Despite the legacy function name, this endpoint now updates the
public field-notes copy, public common-name snapshot, hashtags, and post-level
location sharing.

This function intentionally does not update the private local notes stored in
SwiftData. The iOS app keeps private notes in `LocalScanRecord.fieldNotes` or
`OfflineQueuedScan.fieldNotes` and uses `FieldNotesRepository` as the local
source of truth. Explore receives only the public copy the user explicitly
chooses to show.

## Request

```json
{
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "species_common_name": "Black-Tailed Deer",
  "hashtags": ["deer", "urbanwildlife"],
  "location_sharing": "obscured"
}
```

`field_notes` and `species_common_name` may also be `null`. `location_sharing`
may be `open`, `obscured`, or `private`; legacy `hidden` input is accepted as
`private`.

## Response

```json
{
  "success": true,
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain.",
  "hashtags": ["deer", "urbanwildlife"],
  "species_common_name": "Black-Tailed Deer",
  "location_sharing": "obscured"
}
```

## Validation And Authorization

- Runs through `withEdgeHandler`; the caller must resolve to a Supabase user.
- `post_id` must be a valid UUID.
- `field_notes` must be a string or `null`.
- Empty or whitespace-only values are normalized to `null`.
- Non-empty values are trimmed and capped at 1000 characters.
- `species_common_name`, when supplied, is trimmed, internal whitespace is
  collapsed, and the stored public snapshot is capped at 200 characters.
- `hashtags`, when supplied, replaces the post's public hashtag edges after the
  same normalization used by `share-scan-to-explore`.
- `location_sharing`, when supplied, updates only this Explore post. It does not
  mutate `scans.geoprivacy` or `users.default_geoprivacy`.
- `open` can make the post eligible for Explore Map and non-owned Nearby when
  public coordinates are safe; `obscured` can keep a scrubbed public label but
  stays off spatial results; `private` clears public location fields.
- Updates are scoped to `explore_posts.id`, `explore_posts.user_id`, and
  `unshared_at IS NULL`; non-owned, missing, or unshared posts return 404.
