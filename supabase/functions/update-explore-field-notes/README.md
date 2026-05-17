# update-explore-field-notes

Updates the public field-notes copy on an existing Explore post owned by the
current user.

This function intentionally does not update the private local notes stored in
SwiftData. The iOS app keeps private notes in `LocalScanRecord.fieldNotes` or
`OfflineQueuedScan.fieldNotes` and uses `FieldNotesRepository` as the local
source of truth. Explore receives only the public copy the user explicitly
chooses to show.

## Request

```json
{
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain."
}
```

`field_notes` may also be `null`.

## Response

```json
{
  "success": true,
  "post_id": "uuid",
  "field_notes": "Found at the shaded meadow edge after rain."
}
```

## Validation And Authorization

- Runs through `withEdgeHandler`; the caller must resolve to a Supabase user.
- `post_id` must be a valid UUID.
- `field_notes` must be a string or `null`.
- Empty or whitespace-only values are normalized to `null`.
- Non-empty values are trimmed and capped at 1000 characters.
- Updates are scoped to `explore_posts.id`, `explore_posts.user_id`, and
  `unshared_at IS NULL`; non-owned, missing, or unshared posts return 404.
