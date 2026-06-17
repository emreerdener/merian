# Get Filtered Discovery Feed

The central query endpoint rendering the Merian Discovery timeline. Fetches
high-quality, live-capture scans whose scan-level geoprivacy is `open`. This is
the older Discovery scan feed, not the Explore post-level `location_sharing`
model. It actively strips all 11 trailing telemetry columns (such as
`device_locale`, `time_of_day`, and prompt tokens) from the `scans` table result
to reduce per-row HTTP payload size by ~60%.

It natively processes two core privacy bounds before dispatch:

1. **User Block Lists**: Implicitly ignores any scans from user IDs the
   requester has blocked, as well as themselves.
2. **IUCN Geoprivacy**: Identifies protected species (`endangered`,
   `vulnerable`, etc.) from the joined `species_dictionary` and destructively
   sanitizes their exact coordinates out of the payload, rounding the `public`
   coordinates down to an 11-kilometer bounding box resolution before dispatch
   to protect sensitive habitats from poachers.

## Architecture

To keep the synchronous router clean and properly typed, logic is decoupled:

- **`index.ts`**: The strict HTTP orchestrator. Modestly coordinates pulling the
  blocklist, fetching the DB array, routing it through the destructive
  `sanitizeFeedData` geometry mask, and dispatching.
- **`db.ts`**: Handles the explicit raw PostgREST operations to `supabase`
  (including the complex `!inner()` join to guarantee
  `is_shadowbanned = false`).
- **`types.ts`**: Statically guarantees the `FeedScan` boundaries so Deno
  doesn't drop explicitly defined columns before HTTP validation.
