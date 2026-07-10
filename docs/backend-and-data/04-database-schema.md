# Database Schema & Data Models

This document maps the expected shape of our persistence layers. AI Agents
should refer to this to bind TypeScript interfaces and Swift `Codable` structs
without guessing.

## Supabase PostgreSQL Schema (`00001_initial_schema.sql`)

### `users`

Tracks the global state of the anonymous/authenticated user.

- `id` (UUID): Maps to the `auth.users` GoTrue unique identifier, automatically
  generated via standard Supabase Ghost Sessions with IDFV fallback. This UUID
  is the RevenueCat App User ID and the PostHog distinct ID; RevenueCat
  subscriber attributes also mirror auth email and public identity fields for
  support lookups.
- `subscription_tier` (ENUM): `'free'` | `'pro'`
- `subscription_expires_at` (TIMESTAMPTZ, nullable): Set only for Merian-owned
  timed Pro grants such as the detached `pro_week` non-renewing purchase.
  Standard RevenueCat subscriptions leave this null. The hourly
  `expire-subscription-passes` worker downgrades expired timed grants and clears
  this value.
- `default_geoprivacy` (ENUM): `'open'` | `'obscured'` | `'private'`. Dictates
  the privacy projection applied to scans. Current clients send this value on
  identify requests, and Edge insert helpers fall back to this column when the
  request omits or sends an invalid value. Updating this preference triggers a
  scan reprojection for that user: `private` clears public coordinates and
  public location labels, `obscured` rounds public coordinates with a 10 km
  uncertainty floor, and `open` restores exact public coordinates when exact GPS
  exists and species-safety rules allow it.
- `current_streak_count` (Int): Gamification metric.
- `total_species_discovered` (Int): Calculated at the database level via a
  Postgres `AFTER INSERT` trigger (`update_user_species_count()`). To avoid
  TOCTOU race conditions during bulk offline uploads, it recalculates the sum
  via a subquery (`COUNT(DISTINCT species_id)`) rather than auto-incrementing.
  DO NOT MANUALLY UPDATE THIS FROM CLIENT CODE OR EDGE FUNCTIONS. This metric is
  also maintained via an `AFTER DELETE` trigger
  (`decrement_user_species_count()`) that deducts from the sum when a user
  deletes their last scan of a species.
- `abuse_strikes` (INT, DEFAULT 0): Incremented by the `/identify` background
  moderation pipeline each time Gemini's safety ratings flag submitted media as
  `MEDIUM` or `HIGH` probability, or when `finishReason === "SAFETY"`. Never
  decremented automatically. See
  [Safety & Moderation](../development-guides/10-safety-and-moderation.md).
- `is_shadowbanned` (BOOLEAN, DEFAULT false): Set to `true` when `abuse_strikes`
  reaches 3. Shadowbanned users continue to receive AI identification responses
  (the HTTP response is unchanged), but all background ingestion silently halts
  — no scans are persisted. Not currently read by the iOS client.
- `public_author_name` (TEXT, NOT NULL): Explore-facing public display label
  derived from auth metadata (`First L.`) when safe, otherwise from a stable
  alias fallback. For alias-source identities this now matches
  `public_username`, so default/ghost Explore authors render as handles such as
  `@juniper_trail_27` while logged-in display-name authors can still render
  labels such as `Emre E.`. Added in migration
  `20260425000000_add_explore_posts.sql`.
- `public_username` (TEXT, NOT NULL): Canonical public handle stored without
  `@`, unique across users, and intended for profile handles and future comment
  mentions. Validation requires lowercase ASCII letters, numbers, and
  underscores; 3 to 24 characters; a leading letter; a trailing letter or
  number; no repeated underscores; and no reserved system names. Added in
  migration `20260526090000_add_public_usernames.sql`.
- `public_identity_source` (TEXT, NOT NULL): Source marker for the Explore
  author label. CHECK-constrained to `alias` | `derived_name` | `display_name`.
  Added in migration `20260425000000_add_explore_posts.sql`.
- `public_avatar_url` (TEXT, nullable): Public Explore avatar URL projected onto
  all public author surfaces. It resolves to `custom_avatar_url` when the user
  has uploaded a Merian profile picture; otherwise it falls back to auth
  metadata (`avatar_url` or `picture`) for authenticated users when available.
  `NULL` for ghost users or accounts with no avatar. Added in migration
  `20260426000000_add_public_author_avatar_to_explore.sql`; custom-avatar
  precedence was added in `20260528120000_add_custom_public_avatars.sql`.
- `custom_avatar_url` (TEXT, nullable): Public Cloudflare R2 URL for a user
  uploaded profile picture under
  `https://media.merian.app/avatars/{userId}/...`. This is durable profile media
  and must not be removed by scan purge jobs or R2 lifecycle expiration rules.
  Added in `20260528120000_add_custom_public_avatars.sql`.
- `custom_avatar_updated_at` (TIMESTAMPTZ, nullable): Last successful custom
  avatar promotion time. Updated by `/update-public-avatar`.

**Public identity refresh helpers**:
`refresh_public_author_identity(target_user_id)` and `handle_new_user()`
maintain the Explore-facing identity projection. These functions never expose
raw auth metadata directly; they copy only the safe public fields
(`public_author_name`, `public_identity_source`, `public_avatar_url`) onto
`public.users`. Username helpers `normalize_public_username(...)`,
`is_valid_public_username(...)`, and `build_unique_public_username(...)` keep
`public_username` valid and collision-safe. Avatar helpers keep uploaded profile
pictures sticky across OAuth metadata refreshes:
`resolve_public_avatar_url(custom_avatar_url, raw_meta)` returns the custom
avatar first and only then falls back to provider metadata. `public_author_name`
remains the display label; use `public_username` as the stable handle for
profile surfaces and future mentions.

### `species_dictionary`

The global source-of-truth for biological species models. The identify boundary
must keep manufactured, processed, or depicted objects out of this table; wool
rugs, leather goods, wooden furniture, paper, textiles, prepared food, toys,
artwork, ornaments, and species depictions are scan-level non-biological
results, not dictionary taxa.

- `id` (UUID): Primary key.
- `scientific_name` (Text): Unique. (e.g., _Danaus plexippus_)
- `common_names` (JSONB): Keyed by ISO 639-1 language code. e.g.,
  `{"en": "Monarch Butterfly"}`. Always written under the `"en"` key by the
  identify Cache Miss path. Existing `common_names.en` values are canonical and
  win over scan-level `common_name`; scan names only fill an empty English name
  for a normalized biological subject.
- `kingdom`, `phylum`, `class`, `order`, `family`, `genus` (Text, nullable):
  Standard Linnaean taxonomy. Migration
  `20260427000000_reset_invalid_lookalike_taxonomy.sql` removed the original
  `NOT NULL` constraint and normalized legacy placeholder values such as
  `"Unknown"` / blank strings to `NULL`. New identify writes never persist
  `"Unknown"` into these columns.
- `wikipedia_overview` (Text): Cached Wikipedia summary paragraph for the
  species. Written by the identify Cache Miss path from the Wikipedia REST API
  (`/page/summary`). Served to the client as `wikipedia_overview` in the
  `/identify` response. Mirrors `LocalScanRecord.wikipediaOverview` and
  `SpeciesData.wikipediaOverview` in the Swift layer.
- `hazard_type` (TEXT): Hazard classification for the species. CHECK constraint
  enforces one of: `'none'` | `'poisonous'` | `'venomous'` | `'allergenic'` |
  `'irritant'`. Added in migration `20260327000000_add_hazard_type.sql`. This
  column exists only on `species_dictionary` — **not on `scans`**. The feed
  reads it from `species_dictionary` via join.
- `wikipedia_url`, `gbif_taxon_key`: Extended biological context.
- `reference_image_url` (TEXT, nullable): Legacy comma-separated reference-image
  cache. New public dictionary and Explore detail readers prefer
  `species_reference_images` and fall back to this field for older rows/direct
  readers. Keep this cache until every iOS historical/backfill path has
  migrated.
- `native_region` (Text): Origin markers.
- `habitat_description` (Text): Summarizes the expected ecosystem parameters for
  the species.
- ~~`global_distribution_regions`~~ (JSONB): Dropped in migration
  `20260327140000_drop_global_distribution_regions.sql`. Previously populated
  with Gemini Flash-generated ISO 3166-1/3166-2 region codes that proved
  inaccurate. Species geographic range is now communicated exclusively through
  the GBIF occurrence density tile overlay (driven by `gbif_taxon_key`).
- `similar_species` (Text Array): Legacy flat array of validated similar-species
  scientific names. Kept only as a compatibility cache alongside the
  authoritative `species_lookalikes` join table. Raw Gemini Flash output is no
  longer persisted here; `enrich-scan` writes this field only after the names
  have been resolved back to `species_dictionary` rows and passed taxonomy
  validation. Added as `diagnostic_lookalike_name TEXT` in
  `20260326200000_add_diagnostic_comparison.sql`, converted to
  `diagnostic_lookalikes TEXT[]` in
  `20260329062600_add_lookalike_species_array.sql`, and renamed to
  `similar_species` in `20260329070941_rename_similar_species.sql`.
- `lookalikes_flash_attempted` (BOOLEAN, DEFAULT `FALSE`): Species-level memo
  that a validated Flash lookalike generation attempt has already been persisted
  for this species. It is only flipped to `TRUE` when
  `resolveLookalikesToJoinTable` actually writes validated rows; failed or
  taxonomy-insufficient attempts leave it `FALSE` so enrichment can retry later.
- ~~`diagnostic_primary_rationale`~~: Dropped in
  `20260329070941_rename_similar_species.sql`. Previously stored the primary
  identification rationale for low-confidence scans.
- ~~`diagnostic_differentiators_json`~~: Dropped in
  `20260329070941_rename_similar_species.sql`. Previously stored a JSON-encoded
  array of key field marks distinguishing the species from its lookalike.
- `group_tags` (Text Array): Broad-to-specific categorical labels for the
  species (e.g. `["animal", "bird", "songbird", "warbler"]`). Generated once by
  a `gemini-2.5-flash` background call on the first scan of a species;
  subsequent scans read from this cache. Returned to the client in the
  `/identify` response as `group_tags` and merged into
  `LocalScanRecord.semanticTags` for library keyword search. Added in migration
  `20260327100000_add_group_tags_to_species_dictionary.sql`.
- `alternative_common_names` (Text Array): All known English vernacular synonyms
  for the species beyond the primary `common_names.en` value. Populated from the
  GBIF vernacular names endpoint
  (`GET /v1/species/{key}/vernacularNames?language=eng&limit=30`) during the
  background enrichment pass that fires on the first Cache Miss. English-only
  filter applied (`language: eng | en`), normalised to Title Case, and
  deduplicated. The primary `common_names.en` value is excluded from this array
  (case-insensitive). `NULL` when GBIF returned no additional names or the
  species has not yet been enriched. Has a GIN index for array containment
  queries. Added in migration `20260407000000_add_alternative_common_names.sql`.
  Served to the client as `alternative_common_names` in the `/identify` Cache
  Hit response and the public `/species-dictionary` response; stored in
  `LocalScanRecord.alternativeCommonNames` (SwiftData V34) for scan surfaces
  only.
- `inaturalist_taxon_id` (INTEGER, nullable): Stable public iNaturalist taxon ID
  used by `/species-observation-stats` for observation charts. The stats Edge
  Function writes this after exact scientific-name resolution so future requests
  can use `taxon_id` rather than a name fallback. Constraint: `NULL OR > 0`.
  Added in migration `20260517190000_add_species_observation_stats.sql`.

**Public dictionary projection**: `/species-dictionary` reads only safe
species-level columns from this table: identifiers, canonical names, taxonomy,
hazard/conservation status, Wikipedia/habitat/GBIF fields, group tags, alternate
common names, and normalized public reference imagery from
`species_reference_images`. It must not project scan-specific or user-specific
data other than public media attribution labels stored on reference-image rows.

**Public observation stats**: `/species-observation-stats` reads
`species_dictionary.id`, `scientific_name`, and `inaturalist_taxon_id` only. It
does not read `scans` and does not receive local SwiftData observation records.

### `species_reference_images`

Normalized public reference images for each species dictionary row. Added in
migration `20260513030000_add_species_reference_images.sql`.

- `id` (UUID): Primary key.
- `species_id` (UUID FK → `species_dictionary.id`, CASCADE DELETE): Owning
  species.
- `url` (TEXT): Public image URL. `(species_id, url)` is unique.
- `source` (TEXT): `merian`, `wikipedia`, or `gbif`. Merian rows come from
  published Explore post media that met the quality threshold; GBIF includes
  verified occurrence imagery such as iNaturalist-hosted records returned by
  GBIF.
- `license` / `attribution` (TEXT, nullable): Media rights metadata for iOS
  attribution display and future web-safe public species pages. Web renderers
  must treat missing values as an attribution audit failure unless they can
  provide an equivalent source-specific attribution.
- `width` / `height` (INTEGER, nullable): Optional pixel dimensions.
- `sort_order` (INTEGER): Display order for galleries and thumbnails.
- `created_at` / `last_verified_at` (TIMESTAMPTZ): Creation and health-check
  timestamps.
- RLS: anyone can read; non-service writes are not exposed by policy.

Ordering uses `public.public_species_reference_image_source_rank(...)`: Merian
images first, then Wikipedia, then GBIF, with `sort_order`, `created_at`, and
`id` as tie-breakers.

### `taxonomy_versions`, `taxon_nodes`, `taxon_names`

Community Identification uses a pinned Merian taxonomy graph. Added in
`20260620120000_add_community_identifications.sql`, hardened in
`20260620143000_rebuild_community_identification_core.sql`, and expanded into a
GBIF-backed Community Taxonomy Index in
`20260622030000_long_term_community_taxonomy_index.sql`.

- `taxonomy_versions`: Version records for Merian dictionary taxonomy with
  `draft`, `active`, and `retired` status. Only one Merian dictionary version is
  active at a time.
- `taxon_nodes`: Durable taxonomy nodes scoped by `taxonomy_version_id`.
  `(taxonomy_version_id, path)` is unique, so future taxonomy refreshes do not
  rewrite historical IDs. Nodes now carry index provenance fields:
  `gbif_taxon_key`, `accepted_gbif_taxon_key`, `taxonomic_status`, `source`,
  `last_synced_at`, and `import_run_id`. `species_id = NULL` is valid for
  GBIF-only taxa that are searchable but not yet materialized into
  `species_dictionary`.
- `taxon_names`: Search names for scientific names, common names, and synonyms.
  The active version is seeded from `species_dictionary.common_names`,
  `alternative_common_names`, and cached GBIF suggestions.
- `taxonomy_import_runs`: Service-role audit rows for bounded GBIF imports and
  on-demand search cache misses. Tracks source, scope, status, requested query,
  target taxonomy version, row counts, errors, and metadata.
- `taxon_node_replacements`: Optional future mapping from retired nodes to newer
  nodes without mutating old identifications.

`refresh_taxonomy_nodes_from_species_dictionary()` builds a draft version from
the current Merian dictionary and activates it atomically. Community requests
pin their `taxonomy_version_id`; the AI scan result is only an anchor label, not
a consensus vote.

`sync_taxon_nodes_from_species_dictionary()` upserts Dictionary-backed taxa into
the active taxonomy index in place and preserves existing GBIF-only nodes.
`upsert_gbif_community_taxa(...)` caches GBIF search results and lineage into
the active index so Community ID suggestions are no longer limited to enriched
Dictionary species. The service-role `sync-community-taxonomy-index` endpoint
uses the same bridge for bounded GBIF imports, starting with
`gbif_bounded_birds` pages under GBIF taxon key `212` (`Aves`). The service-role
`community-taxonomy-status` endpoint reports the active taxonomy row, node
counts by source/rank, GBIF-only taxon counts, recent import runs, enrichment
queue health, and coverage targets without mutating taxonomy data. For import
operations, its lightweight `view = coverage` mode reads only recent bounded
import runs and coverage target rows so operators do not need to run the full
taxonomy count query after every page.

### `explore_community_requests`

One active Ask the Community request per Explore post. Status is `needs_id`,
`resolved`, or `withdrawn`.

- `post_id` / `scan_id` / `requested_by`: Connect the request to the existing
  Explore post, source scan, and requester. `requested_by` is the source of
  truth for the Identify Yours filter and owner-only request actions. It must
  stay aligned with the current scan owner across ghost-account merges.
- `taxonomy_version_id`: Pins the request, its search results, and its
  identifications to one taxonomy version.
- `initial_taxon_node_id`: The AI-derived starting label. Detail responses
  hydrate this `ai_initial` suggestion with the backing scan's
  `ai_confidence_score`, `ai_reasoning`, and top-level `inference_tier` so the
  UI can present the starting ID, model tier, optional confidence, and collapsed
  reasoning separately from community consensus.
- `current_community_taxon_node_id`: Finest active community consensus, if any.
- `resolved_taxon_node_id` and `resolved_observation_taxon_node_id`: Public
  resolved projection once the request graduates.
- `explore_published_at`: Owner-controlled publish marker for resolved community
  requests. Until this is set, a resolved request remains visible in Identify
  but is excluded from normal Explore feed, map, author, and hashtag reads.
  Publishing a resolved species-level request materializes the resolved taxon
  into `species_dictionary` when needed, links `taxon_nodes.species_id`, and
  sets the source scan's `confirmed_species_id`.
- `consensus_score`, `consensus_identification_count`, `consensus_rank`: Cached
  consensus state maintained by queued consensus jobs.
- `consensus_processing_state`: `idle`, `queued`, `processing`, or `failed`.
- `note`, `requested_at`, `resolved_at`, `withdrawn_at`, `updated_at`: Request
  metadata and lifecycle timestamps.

Normal Explore feed, map, author, and hashtag reads use
`explore_observation_projection`, excluding `community_needs_id` posts and
excluding `community_resolved` posts until their request has
`explore_published_at` set by the owner. Community detail responses derive
initial Suggest ID options from this pinned taxonomy version: the initial AI
taxon plus any resolvable `scans.candidates` entries, capped and deduplicated
server-side. The initial suggestion is always kept as
`suggestion_source = ai_initial`; its confidence comes from
`scans.ai_confidence_score`, its reasoning comes from `scans.ai_reasoning`, and
the detail response's top-level `inference_tier` comes from
`scans.inference_tier`. Alternative suggestions remain
`suggestion_source = ai_candidate` and keep their candidate-level confidence and
distinguishing feature. The Community request queue can be scoped to all visible
unresolved requests or to unresolved requests created by the viewer.

### `explore_identifications`

Append-only human identification audit rows for community requests.

- `request_id`, `post_id`, `user_id`: Request, Explore post, and identifier.
- `taxon_node_id` / `taxonomy_version_id`: Chosen taxon within the request's
  pinned taxonomy version.
- `disagreement_mode`: `implicit_support`, `explicit_disagreement`, or
  `maverick`.
- `is_genus_best_possible`: Marks a genus-level consensus as good enough to
  graduate.
- `reasoning`: Optional explanation for conflicts.
- `withdrawn_at` / `restored_at`: Withdraw/restore lifecycle without deleting
  history.

A partial unique index enforces one active identification per user per request.
Changing an ID withdraws the old active row and inserts a new row.

### `community_consensus_jobs`, `community_consensus_events`

Consensus recalculation is queued instead of driven by a heavy row trigger.

- `community_consensus_jobs`: One coalesced pending/failed/completed job per
  request. Submit, withdraw, and restore enqueue a job and attempt one immediate
  best-effort process pass.
- `community_consensus_events`: Append-only state-change history recording old
  and new status, taxon, score, count, rank, reason, and job ID.

Consensus still uses active human IDs only: at least two IDs, score strictly
greater than `2 / 3`, ancestor IDs neutral unless explicit disagreement,
species-level consensus resolving immediately, and genus resolving only when an
exact genus ID marks it as the best practical level.

### `explore_observation_projection`

One public projection row per Explore post. Projection state is `normal`,
`community_needs_id`, `community_resolved`, or `withdrawn`.

Community request creation sets the post to `community_needs_id`. Consensus
resolution sets it to `community_resolved` and points `public_taxon_node_id` at
the resolved community taxon. Normal Explore surfaces still hide
`community_resolved` projections until the owner explicitly publishes the
resolved request to Explore. Owner publish does not mutate `scans.species_id`;
it sets `scans.confirmed_species_id` to the resolved species after materializing
new GBIF-backed taxa into `species_dictionary`.

**Backfill and compatibility**: the migration splits, trims, and dedupes
`species_dictionary.reference_image_url` into this table, preserving order.
`upsertSpeciesDictionary` dual-writes verified cache URLs into this table for
new or refreshed species. Public readers now prefer normalized rows, while
`reference_image_url` remains a compatibility cache for older direct readers and
historical scan backfills.

### `species_reference_image_merian_sources`

Private provenance/candidate table for Merian-sourced reference imagery. Added
in migration `20260513080000_add_merian_reference_image_refresh.sql`; confidence
provenance fields were added in
`20260514110000_add_species_confidence_gate_to_merian_reference_images.sql`.

- Stores source `species_id`, `explore_post_id`, `scan_id`, `user_id`, image URL
  and index, scan-level `image_quality_score`, raw `ai_confidence_score`
  snapshot, confidence qualification source (`ai` or `confirmed_species`),
  author attribution snapshot, and qualification/promotion timestamps.
- `reference_image_id` links to the public `species_reference_images` row when a
  candidate is currently promoted.
- `(species_id, image_url)` is unique so duplicate Explore media for the same
  species collapse to the best candidate.
- RLS is enabled with no anon/authenticated read policy; only `service_role`
  receives table grants. Public APIs expose only the safe
  `species_reference_images` row fields.

### `species_observation_stats_cache`

Server-side cache for global public species observation chart payloads. Added in
migration `20260517190000_add_species_observation_stats.sql`.

- `species_id` (UUID FK -> `species_dictionary.id`, CASCADE DELETE): Owning
  species.
- `source` (TEXT): Provider key. V1 supports only `inaturalist`.
- `scope` (TEXT): Public aggregation scope. V1 supports only `global`.
- `scientific_name` (TEXT): Normalized species name used for display/debugging.
- `payload` (JSONB): Full public stats response payload stored as an object.
- `status` (TEXT): `fresh`, `stale`, `no_data`, `unavailable`, or `partial`.
- `provider_error` (TEXT, nullable): Joined provider error messages from the
  most recent refresh attempt.
- `fetched_at` (TIMESTAMPTZ): Provider/cache payload timestamp.
- `expires_at` (TIMESTAMPTZ): Freshness cutoff. V1 writes a 7-day TTL.
- `created_at` / `updated_at` (TIMESTAMPTZ): Audit fields. `updated_at` is
  maintained by trigger.
- Primary key: `(species_id, source, scope)`.
- Index: `idx_species_observation_stats_cache_expires_at`.
- RLS: anyone can read; writes are service-role only.

The payload contains public iNaturalist aggregates only: seasonality, rolling
seven-year history, life-stage annotation series, sex annotation series, total
observations, most recent observation date, provider metadata, and provider
errors. It must not contain Merian user IDs, scan IDs, Explore post IDs, field
notes, local media, locations, or local observation counts.

### `user_species_preferences`

Per-user preferred common name overrides. Keyed on `(user_id, scientific_name)`.
Added in migration `20260407000000_add_alternative_common_names.sql`.

- `user_id` (UUID FK → `users.id`, CASCADE DELETE): The owning user.
- `scientific_name` (TEXT): The species this preference applies to.
- `preferred_common_name` (TEXT): The user's chosen display name — one of the
  names from `alternative_common_names` or the species primary
  `common_names.en`.
- `deleted_at` (TIMESTAMPTZ, nullable): Soft-delete tombstone for cross-device
  clears. Active rows have `deleted_at IS NULL` and a non-empty
  `preferred_common_name`; cleared rows have `deleted_at IS NOT NULL` and
  `preferred_common_name IS NULL`.
- `updated_at` (TIMESTAMPTZ): Auto-updated by trigger on every write.
- Primary key: `(user_id, scientific_name)`.
- RLS: users can only read and write their own rows.

> **iOS implementation note**: `SpeciesPreferredNameRepository` uses SwiftData
> `UserSpeciesPreference` as the local source of truth and syncs directly to
> this table through the authenticated Supabase client. `MerianApp` promotes
> legacy `speciesPreferredName_*` `UserDefaults` keys at startup, then clears
> them after SwiftData saves. Local clears are queued as pending delete
> timestamps until the cloud tombstone upsert succeeds. Preferred-name sync is
> single-flight on the repository boundary, records a trailing follow-up request
> for mid-flight triggers, and persists lightweight diagnostics
> (`lastAttemptAt`, `lastSuccessAt`, status/message, last pushed/pulled counts)
> in `UserDefaults`; those diagnostics are not database state and should not be
> modeled in Postgres.

### `species_lookalikes`

Self-referential join table linking species that are visually similar or
commonly confused. Added in migration
`20260329200000_add_species_lookalikes.sql`. This is the authoritative source
for rich lookalike data returned by the `/enrich-scan` Edge Function, the public
`/species-dictionary` endpoint, and the Explore post detail projection.

- `species_id` (UUID FK → `species_dictionary.id`, CASCADE DELETE): The subject
  species.
- `lookalike_id` (UUID FK → `species_dictionary.id`, CASCADE DELETE): A species
  that could be confused with the subject.
- `reason` (TEXT, nullable): Concise species-level explanation for why the
  relationship is visually confusing.
- `visual_traits` (TEXT[], default empty): Shared visual traits such as wing
  pattern, flower shape, silhouette, bark texture, or growth habit.
- `confidence` (NUMERIC, nullable): Relation confidence in the inclusive `0..1`
  range.
- `source` (TEXT): `model_enrichment`, `taxonomy_trigger`, `manual_curation`,
  `user_review`, `system_backfill`, or `unknown`.
- `review_status` (TEXT): `unreviewed`, `needs_review`, `approved`, or
  `rejected`. Public readers omit rejected rows.
- `is_bidirectional` (BOOLEAN): Curated marker that the relation is considered
  semantically bidirectional. It does not create or imply a reverse row.
- `sort_order` (INTEGER): Display order within a subject species'
  similar-species list.
- `created_at` / `updated_at` (TIMESTAMPTZ): Audit fields for relation metadata.
- Primary key: `(species_id, lookalike_id)`. Composite ensures uniqueness; a
  `CHECK (species_id != lookalike_id)` prevents self-links.
- All links are **one-directional** — `resolveLookalikesToJoinTable` inserts
  `(speciesId, lookalike)` only; the reverse `(lookalike, speciesId)` is
  intentionally not written. A pine cone is not necessarily a lookalike for a
  rose just because Flash once suggested the reverse. Bidirectional writes
  caused cross-family contamination that bypassed the kingdom-only validation
  guard.

**Postgres trigger** (`trg_link_taxonomy_lookalikes`): Fires `AFTER INSERT` on
`species_dictionary`. Auto-links same-genus species at zero token cost, but only
when both rows have a real non-placeholder genus and a matching real kingdom.
Migration `20260427000000_reset_invalid_lookalike_taxonomy.sql` replaced the
original trigger after `"Unknown"` genus values were found mass-linking
unrelated species. Migration
`20260513060000_add_species_lookalike_relation_metadata.sql` adds relation
metadata to these automatic rows with `source = taxonomy_trigger`, modest
confidence, and `sort_order = 100`.

**Rich hydration**: The `/enrich-scan` and `/species-dictionary` Deno paths
resolve entries via an explicit embedded PostgREST join — `species_lookalikes`
joined to `species_dictionary` via `!lookalike_id` FK hint, fetching only the
columns their client DTOs decode. Lookalike thumbnails prefer the first
`species_reference_images` row and fall back to the legacy comma-separated
cache. The Explore detail SQL RPC hydrates the same relationship into a public
`similar_species` JSONB array. All hydrated public lookalike entries include the
lookalike row's `species_dictionary.id` as `species_id` so clients can route by
stable dictionary identity instead of scientific name alone. New additive
metadata fields include `reason`, `visual_traits`, `confidence`, `source`,
`review_status`, `is_bidirectional`, and `sort_order`; old clients ignore them.
The `!lookalike_id` hint is required for PostgREST paths because
`species_lookalikes` has two FKs referencing `species_dictionary` (`species_id`
and `lookalike_id`); without the explicit hint PostgREST cannot determine which
FK to follow.

**Shared public projection**: Deno Edge code uses
`services/supabase/functions/_shared/publicSpeciesProjection.ts` for public
species DTOs, common-name fallback, normalized/legacy reference-image mapping,
and private-field contract checks. Explore detail uses matching SQL helpers
(`public.public_species_common_name`,
`public.public_species_reference_image_urls`,
`public.public_species_first_reference_image_url`, and
`public.public_species_similar_species`) so SQL-hydrated lookalikes follow the
same public projection rules.

**Taxonomy validation guard**: `resolveLookalikesToJoinTable` only persists rows
when the primary species has usable taxonomy (`kingdom` plus either `order` or
`family`). Each candidate lookalike must also have a real matching `kingdom`,
and then either a matching `order` or, if order is unavailable, a matching
`family`. Candidates with missing taxonomy, placeholder taxonomy, or no
`species_dictionary` row are dropped rather than returned as provisional stubs.
This prevents cross-kingdom and cross-clade hallucinations from becoming durable
cache.

### `species_content_provenance`

Species-level provenance and refresh metadata for public dictionary content.
Added in migration `20260513050000_add_species_content_provenance.sql`.

- `species_id` (UUID FK -> `species_dictionary.id`, CASCADE DELETE): Owning
  species dictionary row.
- `content_key` (TEXT): Field bucket being described. Current values are
  `common_names`, `alternative_common_names`, `taxonomy`, `wikipedia_url`,
  `wikipedia_overview`, `habitat_description`, `gbif_taxon_key`,
  `reference_images`, `lookalikes`, `group_tags`, `iucn_red_list_status`, and
  `hazard_type`.
- `source` (TEXT): Origin classification. Current values are `gbif`,
  `wikipedia`, `model_enrichment`, `user_review`, `manual_curation`,
  `system_backfill`, `taxonomy_trigger`, `mixed`, and `unknown`.
- `source_detail` (TEXT, nullable): Human-readable detail such as
  `Wikipedia REST summary extract`, `GBIF vernacular names`, or
  `legacy backfill; original freshness unknown`.
- `confidence` (NUMERIC, nullable): Source confidence in the inclusive `0..1`
  range. Backfilled rows default lower than live GBIF/Wikipedia/model writes so
  the refresh queue can prioritize legacy data.
- `metadata` (JSONB object): Small structured details, such as populated
  taxonomy ranks, URL counts, or group-tag counts.
- `last_refreshed_at` / `refresh_after` (TIMESTAMPTZ): Freshness clock and next
  refresh target. `manual_curation` may set `refresh_after = NULL`.
- `created_at` / `updated_at` (TIMESTAMPTZ): Audit fields. `updated_at` is
  maintained by trigger.
- Primary key: `(species_id, content_key)`.
- RLS: anyone can read; non-service writes are not exposed by policy.

**Writers**: `services/supabase/functions/_shared/speciesContentProvenance.ts`
owns the Deno row builders and best-effort upsert helper. The shared identify
path, audio identify path, and `enrich-scan` write provenance when they update
dictionary fields, reference-image-backed content, group tags, or durable
lookalike rows. Provenance write failures are logged and do not fail the
user-facing scan or dictionary response.

**Backfill**: the migration inserts low-confidence provenance rows for existing
dictionary data, reference images, and lookalikes with
`source_detail = 'legacy backfill; original freshness unknown'` and a 30-day
refresh target.

**Refresh queue**:
`public.get_species_content_refresh_queue(max_rows INTEGER DEFAULT 100, as_of TIMESTAMPTZ DEFAULT NOW())`
returns stale or low-confidence content rows joined to
`species_dictionary.scientific_name`. It is revoked from `PUBLIC` and executable
by `service_role` only. The scheduled `refresh-species-content` Edge worker
consumes this queue, refreshes GBIF/Wikipedia-backed fields, and records new
provenance rows.

### `species_enrichment_jobs`

Operational queue for species-level hydration work. Added in
`20260622030000_long_term_community_taxonomy_index.sql`.

- `species_id` (UUID FK -> `species_dictionary.id`, CASCADE DELETE): Species to
  hydrate.
- `content_group` (TEXT): One of `gbif_wikipedia_reference`, `habitat`,
  `lookalikes`, or `group_tags`.
- `status` (TEXT): `queued`, `running`, `succeeded`, `failed`, or `cancelled`.
- `priority`, `attempts`, `max_attempts`, `next_run_at`, `locked_at`,
  `completed_at`: Retry and scheduling controls.
- `source_trigger`, `last_error`, `metadata`: Debuggable cause and failure
  context.

`refresh-species-content` claims `gbif_wikipedia_reference` jobs first and uses
the older provenance queue only as a fallback. `refresh-species-model-content`
claims `habitat`, `lookalikes`, and `group_tags` jobs and reuses the same
species-level primitives behind `enrich-scan`. New GBIF-backed species
materialized from Community ID publish enqueue all four content groups so
external refresh and model-heavy enrichment can proceed independently.
`20260707153931_species_dictionary_enrichment_queue_backfill.sql` adds an
insert trigger on `species_dictionary` so every future species row, regardless
of creator, queues only the enrichment groups it is missing. The same migration
backfills existing sparse rows into `species_enrichment_jobs` with
`source_trigger = 'species_dictionary_sparse_backfill'`.
`community-taxonomy-status` exposes queue counts, next queued jobs, and recent
failures for service-role monitoring.

### `taxonomy_coverage_targets`

Bounded taxonomy-completeness targets for future gamification. Added in
`20260622030000_long_term_community_taxonomy_index.sql`.

- `slug` / `display_name`: Stable target identity, starting with `birds`.
- `root_rank` / `root_scientific_name` / `root_taxon_node_id`: Defines the
  indexed taxonomy scope.
- `indexed_species_count`, `dictionary_species_count`, `coverage_ratio`:
  Coverage metric where enriched Dictionary species are compared with indexed
  GBIF species in the target scope.
- `last_imported_offset`: Most recent GBIF page offset that successfully wrote
  rows for the target.
- `next_import_offset`: Machine cursor used by `sync-community-taxonomy-index`
  when `offset` is omitted. This is the preferred continuation pointer for
  operator scripts and cron.
- `last_successful_import_at`, `last_import_error`, `gbif_total_count`,
  `import_cursor_metadata`: Bounded-import health and cursor diagnostics,
  including the last GBIF count reported for the target and retry metadata.
- `last_computed_at`: Freshness marker for
  `refresh_taxonomy_coverage_targets()`.

The Birds target is populated by bounded `sync-community-taxonomy-index` imports
and recomputed by `refresh_taxonomy_coverage_targets()` after each successful
worker run, not after every page. Individual GBIF upsert pages pass
`refresh_coverage = false` so larger batches do not repeatedly recompute the
same coverage counts. Do not show gamified completion claims until the target's
`indexed_species_count` has been seeded from the bounded import.

### `scans`

The transaction log for every successful identification.

- `id` (UUID)
- `user_id` (UUID - Foreign Key)
- `species_id` (UUID - Foreign Key nullable)
- `ai_confidence_score` (Float): 0.0 to 1.0. Bounded explicitly within the
  Gemini schema description ruleset.
- `blur_score` (Float): 0.0 to 1.0. Mathematically derived natively in the Edge
  orchestrator from Gemini's `image_quality.sharpness` score to reduce
  generation latency.
- `zoom_factor` (Float, nullable): Non-default camera zoom factor at capture.
  Added in migration `20260628100000_add_zoom_factor_to_scans.sql` so
  server-side follow-up surfaces can use the same capture-quality context shown
  locally. `NULL` for 1x captures, unsupported modalities, and older scans.
- `gps_lat_exact` / `gps_long_exact` (Float): **CHECK constraints**
  (`20260405000005`): `gps_lat_exact` bounded `[-90, 90]`, `gps_long_exact`
  bounded `[-180, 180]`. Added `NOT VALID` — future inserts/updates validated;
  existing rows not retroactively checked.
- `gps_lat_public` / `gps_long_public` (Float): Same CHECK constraints as exact
  columns. These are scan-level privacy-safe coordinate projections used as an
  input to post-owned Explore location projection, not the public map source of
  truth. Migration
  `20260428213000_fix_explore_map_public_coordinate_fallback.sql` added
  `derive_public_scan_coordinate(...)` plus the
  `trg_sync_scan_public_coordinates` trigger so inserts/updates automatically
  normalize public coordinates from exact coordinates, geoprivacy, uncertainty,
  and species safety context. `private` scans null these fields; `obscured`
  scans round into a coarse public display cell rather than exposing the capture
  point; `open` scans may retain exact coordinates. The same migration backfills
  older rows that were missing public coordinates.
- `geoprivacy` (ENUM): Per-scan privacy state (`open`, `obscured`, `private`).
  New identify/describe/audio inserts resolve this from the explicit request
  field when valid, otherwise from `users.default_geoprivacy`. Migration
  `20260613100000_sync_user_default_geoprivacy_to_scans.sql` adds a user default
  sync trigger so Settings changes reproject existing scans.
- `coordinate_uncertainty_in_meters` (INTEGER, nullable): Public-location
  uncertainty band paired with `gps_lat_public` / `gps_long_public`. The same
  trigger clamps obscured Explore-visible rows to a coarse uncertainty floor
  (`>= 10000`) and exact/public rows to a low-uncertainty range (`<= 999`).
  `private` scans clear it to `NULL`.
- `gps_elevation` (Float): Altitude at capture. CHECK constraint bounds
  `[-500, 9500]` (below Dead Sea floor to above Everest).
- `is_live_capture` (Boolean): AI flags whether this was a real photo vs a
  screen/book capture.
- `ecology_type` (ENUM): `'wild'` | `'urban'` | `'domesticated'` | `'unknown'`
- `colors` (Text Array): 1–3 dominant biological colors extracted by Gemini for
  semantic searchability.
- `weather_condition`, `semantic_location`, `device_locale`, `time_of_day`,
  `depth_scale_text` (Text)
- `public_location_label` (TEXT, nullable): Sanitized public label used by
  Explore feeds, maps, share text, and hashtag suggestions. Trigger
  `trg_set_scan_public_location_label` derives it from `public_location_label` /
  `semantic_location` for open and obscured scans and sets it to `NULL` for
  private scans. Local owner-facing UI must not treat `semantic_location` as
  display-safe without checking geoprivacy.
- `device_time_zone` (TEXT, nullable): IANA timezone identifier sent by the
  client as `deviceTimeZone` during identify, multimodal, describe, and audio
  ingestion. Added in migration
  `20260511120000_add_explore_author_profiles.sql`. Public Explore author
  profiles use the author's latest valid persisted timezone to compute current
  streak and 52-week heatmap day boundaries; rows without a valid timezone fall
  back to UTC.
- `estimated_size_cm` (Float): Physical size dimension computed client-side
  using LiDAR distance and Vision bounding boxes.
- `life_stage` (ENUM): Phenology tracking extracted by Gemini mapped to Darwin
  Core vocabulary (`egg`, `larva`, `pupa`, `nymph`, `juvenile`, `subadult`,
  `adult`, `seedling`, `sapling`, `unknown`).
- `reproductive_condition` (ENUM): Multi-kingdom condition tracking extracted by
  Gemini mapped to Darwin Core vocabulary (`flowering`, `fruiting`, `budding`,
  `vegetative`, `sporing`, `pregnant`, `gravid`, `mating`, `spawning`,
  `nesting`, `dormant`, `not_applicable`).
- `sex` (Text): Darwin Core sex annotation extracted by Gemini only when direct
  evidence supports it. Values are constrained to `female`, `male`,
  `hermaphrodite`, `mixed`, `cannot_determine`, or `not_applicable`.
- `sex_confidence` (Float): Confidence from direct sex evidence only, bounded to
  `0...1`.
- `sex_evidence` (Text): Short phrase naming the visible, described, or acoustic
  cue supporting the sex annotation.
- `individual_count` (Int): Primary subject population density within the frame.
- `ecological_interactions` (Text Array): Biotic interactions between subjects
  (e.g., predation, pollination, parasitism) derived by the AI.
- `extracted_visual_traits` (Text[]): Array of 3 specific physical/structural
  bullet points extracted by the Gemini vision model (Micro-CoT) _before_
  evaluating identity or scientific name (forced by schema key-ordering) to
  prevent false-positive pareidolia.
- `ai_reasoning` (Text): Per-scan visual justification text generated by the
  Gemini vision model for the specific photo submitted. Unique per scan — never
  shared across scans of the same species. Ordered aggressively at the top of
  the schema to guarantee it evaluates before classification. Returned as
  `insight_data.ai_reasoning` in the `/identify` response.
- `weather_temperature_f` (Float)
- `llm_prompt_tokens`, `llm_candidate_tokens`, `llm_total_tokens` (Int): Token
  counts from `usageMetadata` per scan.
- `current_month` (Int)
- `image_storage_urls` (Text Array): Public Cloudflare image links generated
  after moderation. For video scans, this remains a compatibility/storage
  surface for moderated sampled frames; the app-facing media timeline comes from
  `captured_media`.
- `video_storage_urls` (Text Array): Public Cloudflare video links for promoted
  upload-bounded playback `.mp4` scan clips. These are normally compressed 720p
  exports, with upload-safe original recordings allowed as a client fallback.
  The AI receives five sampled frames and optional extracted accompanying audio,
  not these public playback URLs. For new video scans this column is a
  durability gate: if a requested playback video cannot be promoted, the scan
  insert fails/retries instead of creating a frame-only video row.
- `captured_media` (JSONB): Canonical captured-media timeline using the iOS
  `SerializedMediaItem` shape. Video entries attach the playback clip and poster
  thumbnail together so sampled inference frames do not hydrate as standalone
  Insight carousel images, and include an audio reference only when extracted
  video audio was actually persisted. Video rows should be present whenever
  `video_storage_urls` is present. Ready display/playback rows in
  `scan_media_assets` are refreshed from this manifest when present and fall
  back to legacy media arrays for older rows.
- `is_flagged` (Boolean): Managed via `00005_flagged_reviews.sql` for
  human-reported moderation flags.
- `is_tombstoned` (Boolean): Managed via `00006_apply_user_tombstone.sql` for
  GDPR-compliant account deletions. Anonymizes historical AI data while
  preserving offline cache continuity.
- `custom_tags` (Text Array): User-defined plain-text labels for personal
  categorization. Synchronized via direct PostgREST RPC, favoring the cloud
  state as the source-of-truth. Added in
  `20260328221000_add_custom_tags_to_scans.sql`.
- `candidates` (JSONB, nullable): Per-scan array of 2 alternative species
  generated by Gemini for biological subjects. The edge function strips this to
  `NULL` server-side before insert when `confidence_score >= diagnosticTrigger`
  (`0.99` for both Flash and Pro — see `_shared/identify/thresholds.ts`). The
  threshold is intentionally above `FLASH_STRONG` (0.95) and `PRO_STRONG` (0.85)
  so that every Possible, Weak, **and Strong match** scan below that diagnostic
  line can still persist candidates as an escape hatch. Client UI visibility is
  separately gated by `CandidateReviewVisibilityPolicy`. Only scans at or above
  `0.99` (effectively certain) have candidates stripped. `NULL` for those
  near-certain scans, non-biological/processed-material demotions, and all scans
  captured before migration
  `20260330000000_add_candidates_to_scans.sql`. Shape:
  `[{"scientific_name": "...", "confidence_score": 0.71}, ...]`. A partial index
  (`idx_scans_candidates_not_null WHERE candidates IS NOT NULL`) keeps index
  overhead minimal since the majority of scans are high-confidence (NULL).
  Processed-material demotions are normalized before insert so the stored scan
  is `is_biological_subject = false`, has no source-species link, and cannot
  carry biological candidates forward.
- `user_identification_override` (TEXT, nullable): The scientific name the user
  selected when they disputed the AI's primary identification in
  `CandidatesCard`. `NULL` for scans where the user confirmed the AI's
  identification or has not yet reviewed. Added in migration
  `20260330120000_add_user_identification_override.sql`. Synced to the cloud via
  a direct PostgREST PATCH in `InferenceEngine.syncIdentificationReviewToCloud`,
  guarded by a `.eq("user_id", userId)` IDOR bound.
- `user_confirmed_identification` (BOOLEAN, default `FALSE`): Set to `TRUE` when
  the user explicitly confirmed the AI's primary identification as correct via
  the `CandidatesCard` "Yes, correct" button. Distinct from override — this
  records ground-truth positive feedback (the AI was right) rather than a
  correction. Added in migration
  `20260330130000_add_user_confirmed_identification.sql`. Synced to the cloud in
  the same `ReviewSyncPayload` PATCH as `user_identification_override`.
- `confirmed_species_id` (UUID, nullable): The database dictionary ID
  corresponding to the final user-verified species identity. Populated upon both
  Confirmation (resolves the `scans.species_id` fallback) and Override (resolves
  via `fetchAndPatchOverrideData`). Owner-published Community Identification
  consensus also sets this column after materializing the resolved taxon into
  `species_dictionary`; that path does not imply
  `user_confirmed_identification = TRUE`, because it is a final owner-approved
  ID rather than positive feedback that the AI primary ID was correct. Serves as
  the authoritative source of truth for reference dataset extraction. Added in
  migration `20260330230000_add_confirmed_species_id_to_scans.sql`. Synced to
  the cloud in the same `ReviewSyncPayload` PATCH as
  `user_identification_override` and `user_confirmed_identification`.
- `user_review_state` (public.user_review_state enum, default `'unreviewed'`):
  The definitive typed state representing user feedback. Valid values:
  `unreviewed`, `ai_confirmed`, `user_overridden`. Added in migration
  `20260411000001_add_user_review_state.sql`. Resolves query complexities caused
  by dual-column boolean/string combinations. Synced to the cloud in the same
  `ReviewSyncPayload` PATCH as the related legacy override columns.
- `image_quality_score` (SMALLINT, nullable): Gemini's overall image quality
  rating for the captured photo, on a 0–100 scale. Derived from three
  sub-dimensions evaluated in-memory by the model (`sharpness` 1–10, `framing`
  1–10, `diagnostic_utility` 1–10); only the aggregate `overall_score` is
  persisted here. A `CHECK (image_quality_score BETWEEN 0 AND 100)` constraint
  is enforced at the database level. Added in migration
  `20260330150000_add_image_quality_score_to_scans.sql`. `NULL` for all scans
  captured before this migration — no backfill is performed. Feature is "collect
  now, use later": scores are gathered for future community reference-photo
  curation use cases.
- `user_observation_context` (JSONB, nullable): Structured observation context
  staged by the user before submission. On the active multimodal path this is
  the first serialized iOS `ObservationContext` object, currently
  `{ "freeText": "...", "addedAt": "..." }`. Legacy rows may still contain older
  shapes documented during earlier describe experiments. `NULL` for image-only
  scans. Added in migration `20260414000000_add_user_observation_context.sql`.
  Never mutated after scan insertion.
- `pet_identification` (JSONB, nullable): Optional dog/cat display metadata
  added in migration `20260621120000_add_pet_identification_to_scans.sql`.
  Populated only when the primary taxon remains `Canis lupus familiaris` or
  `Felis catus`. Shape:
  `{"species_group":"dog|cat","label":"...","label_type":"breed|breed_mix|coat_pattern|body_type","confidence_score":0.0-1.0,"evidence":["..."]}`.
  The identify edge sanitizes this field before insert: labels are trimmed and
  length-capped, evidence is capped to three entries, confidence is clamped,
  generic labels such as "Dog", "Cat", "Domestic Dog", and "Domestic Cat" are
  dropped, labels below `0.70` confidence are dropped, and non-dog/cat taxa
  never receive this object. This field is not copied into `species_dictionary`;
  species identity remains keyed by `scientific_name`.

Processed or manufactured objects are not biological scan subjects even when
they are made from biological material. The identify edge demotes wool rugs,
kilims, leather goods, wooden furniture, paper/cardboard, cotton or linen
fabric, prepared food, toys, artwork, ornaments, and species depictions to
`is_biological_subject = false` before species lookup or dictionary writes.
These demotions retain the object display name when useful, clear source-species
scientific names and candidates, and do not trigger `is_new_to_merian_dictionary`.

### `insight_chat_conversations`, `insight_chat_messages`, `insight_chat_message_feedback`, `insight_chat_feature_feedback`

Private saved follow-up chat for completed biological Insight sheets. Chat
conversations/messages were added in migration
`20260626120000_add_insight_chat.sql`; answer feedback was added in
`20260628120000_add_insight_chat_feedback.sql`; sheet-level feature feedback was
added in `20260629100000_add_insight_chat_feature_feedback.sql`.

- `insight_chat_conversations.id` (UUID): Primary key.
- `scan_id` (UUID FK -> `scans.id`, cascade delete): The owned scan this chat is
  attached to. `scan_id` and `user_id` are unique together so each user has one
  saved Field chat per scan.
- `user_id` (UUID FK -> `users.id`, cascade delete): Owner. RLS allows users to
  read, insert, update, and delete only rows where `auth.uid() = user_id`.
- `created_at`, `updated_at`: Conversation timestamps; `updated_at` is
  maintained by the shared timestamp trigger.
- `insight_chat_messages.id` (UUID): Primary key.
- `conversation_id` (UUID FK -> `insight_chat_conversations.id`, cascade
  delete): Parent conversation. Deleting a scan deletes its conversation and
  messages.
- `scan_id`, `user_id`: Denormalized owner bounds for indexes, RLS, analytics,
  and daily send limits.
- `role`: CHECK-constrained to `user` or `assistant`.
- `message_text`: Plain text message content. User messages are capped by the
  Edge Function at 600 characters.
- `client_message_id`: Optional client-generated UUID for idempotent user sends;
  unique per conversation when present.
- `model`, `llm_prompt_tokens`, `llm_candidate_tokens`, `llm_thinking_tokens`,
  `llm_total_tokens`, `llm_cached_tokens`: Gemini telemetry for assistant
  replies.
- `is_refusal`, `refusal_reason`, `safety_metadata`: Safety/refusal audit fields
  for local guardrail refusals and model-declared refusals.
- `insight_chat_message_feedback.id` (UUID): Primary key for private answer
  feedback.
- `message_id`, `conversation_id`, `scan_id`, `user_id`: Owner and
  cascade-delete bounds. Feedback is unique per `(message_id, user_id)` and
  deletes with the assistant message, conversation, scan, or user.
- `rating`: CHECK-constrained to `helpful`, `not_helpful`, `wrong`, `unsafe`, or
  `other`.
- `note`: Optional short private feedback note, capped at 1000 characters.
- `created_at`, `updated_at`: Feedback timestamps maintained by trigger.
- `insight_chat_feature_feedback.id` (UUID): Primary key for private feedback on
  the Field chat experience itself.
- `conversation_id` (UUID FK -> `insight_chat_conversations.id`, set null):
  Optional chat thread context. The row remains useful if the thread is deleted.
- `scan_id`, `user_id`: Owner bounds. Feature feedback deletes with the scan or
  user and is RLS owner-only.
- `sentiment`: Optional CHECK-constrained `positive` / `negative` rating from
  the sheet-level feedback modal.
- `note`: Optional short private feature-feedback note, capped at 1000
  characters. Feature feedback requires either `sentiment` or `note`.
- `created_at`: Submission timestamp.

These tables are private scan data. They are not read by Explore, public species
dictionary endpoints, public web pages, or Darwin Core exports.

### `flagged_reviews`

Captures user feedback reporting improper or harmful inferences.

- `id` (UUID): Primary key.
- `scan_id` (UUID - Foreign Key): References `scans`.
- `user_id` (UUID - Foreign Key): References the `auth.users` GoTrue identifier
  of the reporting user.
- `flag_reason` (Text): e.g. "Incorrect Species" or "Inappropriate Content".
- `user_suggestion` (Text): Optional custom text feedback.
- `status` (Text): Defaults to `PENDING_REVIEW`.

### `export_jobs`

Stateful queueing table for asynchronous Darwin Core Archive (DwC-A) exports.

- `id` (UUID): Primary key.
- `user_id` (UUID - Foreign Key): References `auth.users`. Rate-limited to 1
  request per 24 hours per user inside the Edge Function.
- `status` (ENUM): `'pending'` | `'processing'` | `'completed'` | `'failed'`.
- `export_scope` (Text): Default `'personal'`. Accepted values: `'personal'` |
  `'global'`. Validated at the Edge layer — values outside this set are rejected
  with `HTTP 400`. Defines whether to export only the requesting user's captures
  (`'personal'`) or all globally open data (`'global'`).
- `include_precise_coordinates` (Boolean): Access control flag.
- `file_url` (Text): The Cloudflare R2 signed URL holding the completed zip.
  Exists when `status == 'completed'`.
- `error_message` (Text): Present if `status == 'failed'`.
- `created_at`, `completed_at` (TIMESTAMPTZ): Lifecycle tracking metrics.

_Note: A `pg_net` Postgres Trigger listens to `INSERT` on this table to invoke
the background `export-dwca` Server-to-Server edge function webhook._

**Export jobs watchdog cron** (`20260405000004`): A `pg_cron` job
(`expire-stuck-export-jobs`) runs every 5 minutes and tombstones any job stuck
in `'processing'` for more than 30 minutes by setting `status = 'failed'` with a
descriptive `error_message`. Without this watchdog, a killed Edge function (OOM,
cold-start restart, or edge timeout) leaves the job in `'processing'`
permanently and the iOS client shows an infinite loading state. The watchdog is
a plain SQL function (`public.expire_stuck_export_jobs()`) run by the cron
schedule — no additional Edge Function is required.

### `failed_scan_ingestions`

Dead-letter table for background scan ingestion failures. Added in migration
`20260405000003`.

- `id` (UUID): Primary key.
- `scan_id` (TEXT): The `client_scan_id` that was being inserted when the
  failure occurred. TEXT (not UUID FK) because the scan row may not exist if the
  failure was a FK violation.
- `user_id` (UUID, NOT NULL): The user who submitted the scan. Enables per-user
  failure queries.
- `error_message` (TEXT, nullable): The error thrown by `insertScan()`.
- `failed_at` (TIMESTAMPTZ, DEFAULT NOW()): When the ingestion failed.

**Context**: Older background ingestion originally wrote this row only after
`insertScan()` failed (FK violation, DB timeout, network partition) even though
the iOS client had already received a `200` with the AI result. Current
scan-producing paths should first write `scan_ingestion_jobs` plus sanitized
`scan_ingestion_intents`; `/identify-multimodal` does this natively and the
compatibility endpoints (`/identify`, `/identify-describe`, `/audio-spec`) use
the shared compatibility ledger. `failed_scan_ingestions` remains as legacy ops
evidence and detailed insert-failure history, not the primary recovery surface.
Insight-originated Explore sharing and Ask the Community can still repair the
user-facing path by recreating a minimal owned `public.scans` row from the local
record before retrying media restore.

**Ops workflow**: Query by `user_id` and `failed_at` to identify affected users.
Prefer `scan_ingestion_jobs` plus `scan_ingestion_intents` for current rows and
let `replay-scan-ingestion` re-invoke `identify-multimodal` with the same
`client_scan_id` when the intent is resumable. Inline-media compatibility rows
are intentionally non-resumable because raw media bytes are redacted. The
`ignoreDuplicates: true` guard in `insertScan` makes replay safe. Row Level
Security is enabled; the table is never read by the client SDK — only the edge
function (service role) writes to it and ops queries it via the Supabase
dashboard.

**Indexes**: `idx_failed_scan_ingestions_user_id` on `(user_id, failed_at DESC)`
for per-user lookups; `idx_failed_scan_ingestions_failed_at` on
`(failed_at DESC)` for chronological monitoring sweeps.

### `scan_ingestion_jobs`

Durable server-side lifecycle ledger for accepted scan ingestion requests. Added
in migration `20260705120000_add_scan_ingestion_jobs.sql`.

- `scan_id` (TEXT): The client-generated scan id used for idempotent scan
  insertion and status polling. TEXT keeps failure rows representable even when
  a malformed legacy id never becomes a `public.scans.id`.
- `user_id` (UUID): The submitting auth user. This intentionally does not FK to
  `public.users`, because ghost-user upsert happens later in ingestion.
- `endpoint` (TEXT): Current writer, usually `identify-multimodal`.
- `status` (TEXT): `processing`, `finalizing`, `retrying`, `failed_retryable`,
  `failed_terminal`, or `complete`.
- `stage` (TEXT): Fine-grained state such as `ai_inference_started`,
  `video_promotion_started`, `scan_insert_started`, or `scan_inserted`.
- `attempt_count` (INT): Incremented by `public.claim_scan_ingestion_job(...)`
  each time the same user/scan id is accepted again, unless the job is already
  complete.
- `media_counts` (JSONB): Count metadata such as image/audio/video counts,
  required video count, video frame count, and description presence.
- `media_object_keys` (JSONB): Staged R2 object-key references only. Raw media
  bytes are never stored in this ledger.
- `upload_session_ids` (UUID[]): Upload-session ids created by
  `/generate-upload-urls` and recovered from `scan_media_assets` during
  ingestion.
- `manifest_checksum` (TEXT, added by
  `20260705130000_extend_scan_ingestion_jobs_media_manifest.sql`): SHA-256 of
  the normalized ingestion media manifest: expected media counts, staged object
  keys, and upload session ids. Used to distinguish true retries from accidental
  media-shape drift for the same `client_scan_id`.
- `locked_at`, `lock_expires_at`, `retry_after`, `last_error`, `completed_at`:
  Lease, retry, failure, and completion metadata for status polling and ops.

`identify-multimodal` claims the row after request/media validation and updates
it through AI inference, moderation, media promotion, scan insert, and failure
paths. `/check-scan-status` keeps returning `status: "found" | "not_found"` for
client compatibility, and includes optional `job_status`, `job_stage`,
`job_attempt_count`, `retry_after`, and failed-job `last_error` fields when a
scan row is not yet complete. RLS allows owners to read their own job rows;
service-role writers own mutation, and the claim RPC is executable only by
`service_role`.

The media reconciliation worker also feeds back into this ledger. If a stale
capture-upload row still belongs to an active or future-retry job, the worker
leaves the media pending. If a surviving staged playback video repairs an
existing scan and satisfies the job's required video count, the job is marked
`complete`. If media is abandoned after the TTL without a scan row, the job is
marked `failed_terminal` with a reconciliation stage for operator review.

### `scan_ingestion_intents`

Service-role-only sanitized request snapshots for accepted scan ingestion
attempts. Added in migration `20260705140000_add_scan_ingestion_intents.sql`.

- `scan_id` / `user_id` (TEXT / UUID): Same ownership key as
  `scan_ingestion_jobs`.
- `request_payload` (JSONB): Sanitized replay intent containing telemetry,
  observation context, media descriptors, staged object keys, media counts,
  upload-session ids, and manifest checksum. Raw base64 media bytes and local
  device paths are never stored here.
- `media_counts`, `media_object_keys`, `upload_session_ids`,
  `manifest_checksum`: Duplicated from the job claim so replay workers and ops
  can recover the exact media shape without joining through logs.
- `payload_checksum` (TEXT): SHA-256 checksum of the sanitized replay payload,
  used to detect request-intent drift separately from the media manifest.
- `resumable` (BOOLEAN): `true` when the intent contains enough staged/cloud
  references for server-side replay. Inline foreground base64 media is redacted,
  so those rows remain client-retry-only until the client stages media first.
- `inline_media_redacted` / `redacted_media_counts` (BOOLEAN / JSONB): Records
  that inline media existed and how many inline image/audio payloads were
  omitted.
- `last_replayed_at`, `replay_attempt_count`, `last_replay_error`: Control
  fields maintained by `replay-scan-ingestion` when it claims and dispatches a
  resumable staged media/audio/video or text-only retry. Server replay is capped
  at 10 automatic claims per sanitized intent before the paired ingestion job is
  marked `failed_terminal`.

The table has RLS enabled with no client read policy; only service-role Edge
code and operators should read the sanitized intent. The
`public.record_scan_ingestion_intent(...)` RPC is executable only by
`service_role` and upserts by `(user_id, scan_id)`.

`20260705150000_schedule_scan_ingestion_replay.sql` adds
`public.claim_replayable_scan_ingestion_jobs(...)`, also service-role-only. The
RPC atomically claims due retryable or lease-expired jobs whose paired intent is
resumable and not inline-redacted, moves the job to
`stage = 'server_replay_claimed'`, increments the intent replay counter, and
returns the sanitized request payload to the scheduled replay dispatcher. The
follow-up migration `20260707143157_cap_scan_ingestion_replay_attempts.sql`
keeps the same RPC signature but excludes over-budget intents from new claims
and marks them terminal at `server_replay_limit_reached`.

### `user_blocks`

Registers blocked users so they are excluded from Discovery and Explore
surfaces.

- `blocker_id` (UUID - Foreign Key): The user executing the block.
- `blocked_id` (UUID - Foreign Key): The UUID of the blocked user.

Blocking also removes Explore follow relationships in both directions. Migration
`20260511161000_add_explore_following.sql` adds an `AFTER INSERT` trigger on
`user_blocks` so stale `user_follows` rows and follow notifications are removed
even when the block is inserted outside the `/block-user` Edge Function.

### `user_follows`

Asymmetric Follow relationships for public Explore author profiles. Added in
migration `20260511161000_add_explore_following.sql`.

- `follower_user_id` (UUID FK -> `users.id`, CASCADE DELETE): The viewer who
  followed an author.
- `followee_user_id` (UUID FK -> `users.id`, CASCADE DELETE): The followed
  Explore author.
- `created_at` (TIMESTAMPTZ): Relationship creation time.
- Composite primary key: `(follower_user_id, followee_user_id)` for idempotent
  follow writes.
- Check constraint: `follower_user_id <> followee_user_id` rejects self-follows.

Indexes:

- `idx_user_follows_follower_created_at` on
  `(follower_user_id, created_at DESC, followee_user_id)` supports the Following
  feed and viewer follow-state checks.
- `idx_user_follows_followee_created_at` on
  `(followee_user_id, created_at DESC, follower_user_id)` supports
  follower-count lookups.

RLS:

- Users can insert their own follows.
- Users can delete their own follows.
- Users can select only their own following relationships.

Follower/following counts are exposed only as aggregate fields on visible
Explore author profiles. No v1 endpoint exposes browsable follower or following
identities.

### `explore_posts`

Manual-share public feed wrapper around `scans`. Added in migration
`20260425000000_add_explore_posts.sql`.

- `id` (UUID): Primary key.
- `user_id` (UUID FK → `users.id`, CASCADE DELETE): The post author.
- `scan_id` (UUID FK → `scans.id`, CASCADE DELETE, UNIQUE): The backing scan. V1
  enforces one active Explore post per scan.
- `shared_at` (TIMESTAMPTZ): Reverse-chronological feed ordering key.
- `unshared_at` (TIMESTAMPTZ, nullable): Soft-removes the post from the public
  feed without deleting the scan.
- `species_common_name` (TEXT, nullable): Author-selected public common-name
  snapshot for the post. Added by
  `20260614120000_snapshot_explore_species_common_name.sql`. Share/edit Edge
  Functions trim, collapse whitespace, and cap this value at 200 characters.
  Read RPCs prefer it over `species_dictionary.common_names`; omitted or null
  values preserve the legacy dictionary/common-name fallback.
- `location_sharing` (TEXT): Post-level geoprivacy override with `open`,
  `obscured`, or `private`. The global/user scan geoprivacy seeds the composer,
  but editing a shared post changes only this post-owned value.
- `public_latitude` / `public_longitude` / `public_coordinate_visibility`
  (nullable): Post-owned spatial projection populated only when
  `location_sharing = 'open'`. Explore Map and non-owned Nearby matching read
  these fields rather than scan GPS. Protected-species and uncertainty rules can
  store rounded coordinates with `public_coordinate_visibility = 'obscured'`.
- `public_location_label` (TEXT, nullable): Scrubbed post-owned location label.
  `private` posts clear it; `obscured` posts may keep the label but stay off the
  map.
- `like_count` / `comment_count` (INT): Denormalized counters maintained by
  triggers.

**Post media rule**: Explore no longer reads media directly from
`scans.image_storage_urls` at response time. Sharing snapshots safe public image
and video URLs into `explore_post_media`, while `hero_image_url` remains the
backward-compatible cover thumbnail on `explore_posts`. If the scan is
tombstoned, unshared, auto-purged, moderated unsafe, or later loses public scan
media, cleanup flows remove or hide the corresponding public post media. Scan
geoprivacy no longer hides the post itself; post-level `location_sharing`
controls public location output. Share-state reads also require at least one
`explore_post_media` row before returning a post as feed-visible, so partial
post rows left by failed media writes are hidden until sharing succeeds.

### `scan_media_assets`

Normalized scan media lifecycle assets. Added in migration
`20260705100000_add_scan_media_assets.sql`. Migration
`20260706100000_allow_staged_scan_media_without_scan_id.sql` repairs early
deployed tables by dropping any lingering `NOT NULL` requirement from
`scan_id`. Migration
`20260707020956_allow_staged_scan_media_without_url.sql` does the same for
`url`, because staged upload rows exist before a public media URL is available.
Migration
`20260706193954_fix_scan_media_refresh_image_url_ambiguity.sql` replaces the
refresh helper after an early deployment exposed an ambiguous PL/pgSQL
`image_url` reference in the legacy-array fallback path. Migration
`20260707041259_fix_video_has_audio_metadata.sql` corrects video `has_audio`
derivation so generated media rows and Explore snapshots only mark audio when a
captured-media video audio reference exists.

- `scan_id` (UUID FK -> `scans.id`, CASCADE DELETE, nullable): The owning scan
  once the scan row exists. Pre-scan upload-session rows keep this null until
  finalization.
- `client_scan_id` (UUID, nullable): Client-generated scan UUID used to
  correlate staged uploads before the `scans` row is inserted.
- `upload_session_id` (UUID, nullable): Server-generated upload session UUID
  shared by media assets signed for one scan in a `/generate-upload-urls`
  request.
- `user_id` (UUID FK -> `users.id`, CASCADE DELETE): Denormalized owner for RLS
  and efficient owner-scoped media reads.
- `kind` (TEXT): `image`, `video`, or `audio`. Audio rows are lifecycle
  diagnostics for inference input, not user-visible media.
- `role` (TEXT): Lifecycle role. Current user-visible rows use `display` for
  still images and `playback` for playable video clips; reserved roles include
  `thumbnail` and `inference_frame`.
- `status` (TEXT): Lifecycle state: `staged`, `promoted`, `processing`, `ready`,
  `failed`, or `deleted`. Explore/composer/status readers only surface `ready`
  rows whose role is `display` or `playback`.
- `source` (TEXT): Writer that created the row, such as `scan_refresh`,
  `capture_upload`, `repair`, `backfill`, or `manual`.
- `url` (TEXT, nullable): Current public CDN URL. Required for ready
  display/playback rows; staged and failed rows may only have `storage_key` or
  diagnostics.
- `storage_key` (TEXT, nullable): Durable storage object key when known.
  Legacy/backfilled rows may only have a public URL.
- `thumbnail_url` (TEXT, nullable): Public image thumbnail for compact previews
  and video poster frames.
- `order_index` (INT): Stable media order within the scan's captured-media
  timeline for ready display/playback rows.
- `duration_seconds` (DOUBLE PRECISION, nullable): Reserved for video playback
  metadata.
- `has_audio` (BOOLEAN): Whether the playback video has a persisted audio
  companion. This must be derived from normalized media metadata or a
  `captured_media` video audio reference, not merely from `kind = 'video'`.
- `content_type`, `byte_size`, `checksum_sha256`, `width`, `height` (nullable):
  Optional durability, integrity, and presentation metadata.
- `failure_reason`, `ready_at`, `deleted_at` (nullable): Lifecycle diagnostics
  for failed, ready, and deleted assets.
- `metadata` (JSONB): Reserved structured metadata for codecs, processing
  details, repair context, and future media-specific fields.
- `created_at` / `updated_at` (TIMESTAMPTZ): Asset lifecycle timestamps.

`public.refresh_scan_media_assets(scan_id)` rebuilds generated
`scan_refresh`/`backfill` rows from `scans.captured_media` first. If the
manifest is absent, it falls back to `image_storage_urls` / `video_storage_urls`
and collapses legacy sampled video frames behind a single ready playback video
asset whose `has_audio` is false because legacy URL arrays cannot prove that an
audio companion was persisted. The fallback query uses qualified aliases such as
`media_images.raw_image_url` and `media_videos.raw_video_url`; avoid
unqualified names that match PL/pgSQL variables, because scan inserts execute
this helper through the `scans` trigger. A trigger keeps generated rows
synchronized after scan media inserts, updates, and deletes; Edge write paths
also make best-effort refresh RPC calls after critical scan inserts and
video-repair updates, but existing manifest/array fallbacks remain available if
refresh fails. RLS lets owners read their lifecycle rows; public open-scan reads
are limited to ready display/playback rows so staged/failed diagnostics stay
private. The refresh helpers are service-role-only RPC surfaces; app roles
should read `scan_media_assets`, not call refresh functions directly.

`/generate-upload-urls` creates `capture_upload` rows with `status = 'staged'`
when structured scan uploads include `clientScanId` and `mediaRole`.
Capture-upload rows must keep a client scan id and storage key; promoted
capture-upload rows must also have a final `scan_id` and public URL.
`identify-multimodal` links those rows to `scan_id` during finalization:
promoted image/video rows become `promoted`, consumed staged audio rows become
`deleted`, and failed moderation/promotion/insert paths mark remaining staged
rows as `failed`. The scheduled `reconcile-scan-media-assets` worker revisits
old staged rows: existing scan rows can be repaired from surviving staged
playback videos, while abandoned upload sessions are failed and garbage
collected after their TTL.

Operational note: `20260705110000_schedule_scan_media_asset_reconciliation.sql`
also repairs early deployed `scan_media_assets` tables that were created before
the final lifecycle columns existed. It backfills `source` before creating the
staged capture-upload index so remote deploys do not fail on older table shape.

### `scan_media_reconciliation_runs`

Service-role audit log for the scheduled scan-media reconciliation worker. Added
in migration `20260705110000_schedule_scan_media_asset_reconciliation.sql`.

- `started_at` / `finished_at` (TIMESTAMPTZ): Worker execution window.
- `status` (TEXT): `success`, `partial_failure`, `failed`, or `dry_run`.
- `scanned_count`, `promoted_count`, `repaired_video_scan_count`,
  `deleted_staging_object_count`, `failed_asset_count`, `missing_object_count`,
  `still_pending_count`, `error_count` (INT): Bounded operational counters for
  media lifecycle drift.
- `errors` (JSONB): Truncated structured error list for rows that could not be
  reconciled in that run.

The table is RLS-enabled without client policies. It is written by the
service-role worker and intended for operations/monitoring queries, not app
payloads.

### `explore_post_media`

Post-owned public media snapshots for Explore and Community ID posts. Added in
migration `20260703130000_add_explore_post_media.sql`.

- `post_id` (UUID FK -> `explore_posts.id`, CASCADE DELETE): The owning public
  post.
- `kind` (TEXT): `image` or `video`.
- `url` (TEXT): Public CDN URL for the image or playback video object.
- `thumbnail_url` (TEXT, nullable): Public image thumbnail for video playback
  and compact previews. Video posts require a thumbnail when shared.
- `order_index` (INT): Stable carousel ordering within the post.
- `duration_seconds` (DOUBLE PRECISION, nullable): Reserved for video playback
  metadata.
- `has_audio` (BOOLEAN): Whether the video has a persisted audio companion.
  Public playback starts muted; audio requires explicit viewer action. Snapshot
  writers copy this from ready media rows or from the `captured_media` video
  audio reference; legacy URL-array video sources default false.
- `created_at` / `updated_at` (TIMESTAMPTZ): Snapshot lifecycle timestamps.

`public.explore_post_media_items(post_id)` returns ordered media JSON for feed,
detail, author, hashtag, map, and Community ID read paths. Map, widget, profile
grid, and compact surfaces should keep using `hero_image_url` thumbnails.
In-app compact previews may add a play indicator when any returned media item is
video, but Home Screen widgets intentionally show clean still thumbnails without
a video badge. Scan media source
resolution prefers ready display/playback `scan_media_assets` rows, then
`captured_media`, and finally legacy URL arrays so playback video URLs and
poster thumbnails remain paired.

### `explore_post_hashtags`

Normalized public tag edges for Explore posts. Added in migration
`20260521190000_add_explore_post_hashtags.sql`.

- `post_id` (UUID FK -> `explore_posts.id`, CASCADE DELETE): The tagged post.
- `tag` (TEXT): Lowercase hashtag text without the leading `#`. Two to forty
  letters, digits, or underscores. `share-scan-to-explore` accepts display input
  with or without `#` and persists only this normalized text.
- `created_at` (TIMESTAMPTZ): Edge creation time.
- Composite primary key: `(post_id, tag)` keeps post tags idempotent.

The `(tag, post_id)` lookup index powers `public.get_explore_hashtag_posts(...)`
for the in-app tagged-post collection and is also intended for future event and
BioBlitz matching without extracting tags from field notes or comments.

**Current map-coordinate note**: The shipped Explore map reads post-owned public
coordinates on `explore_posts`. Spatial reads only return posts whose
`location_sharing` is `open`; `obscured` and `private` posts remain off-map and
out of non-owned Nearby matches.

### `explore_post_likes`

Like edge table for Explore posts. Added in migration
`20260425000000_add_explore_posts.sql`.

- `post_id` (UUID FK → `explore_posts.id`, CASCADE DELETE)
- `user_id` (UUID FK → `users.id`, CASCADE DELETE)
- `created_at` (TIMESTAMPTZ)
- Composite primary key: `(post_id, user_id)` for idempotent likes.

**Trending support index**: Migration
`20260505120000_add_explore_feed_filters.sql` adds
`idx_explore_post_likes_created_at_post_id` on `(created_at DESC, post_id)` so
the 30-day trending feed can aggregate recent like activity without full-table
scans over the like edge table.

### `explore_post_comments`

Comment table for Explore posts. Added in migration
`20260425000000_add_explore_posts.sql`.

- `id` (UUID): Primary key.
- `post_id` (UUID FK → `explore_posts.id`, CASCADE DELETE)
- `user_id` (UUID FK → `users.id`, CASCADE DELETE)
- `body` (TEXT): Server-capped and non-blank.
- `created_at` (TIMESTAMPTZ)
- `deleted_at` (TIMESTAMPTZ, nullable): Soft delete marker for author-initiated
  comment deletion.
- `moderated_at` (TIMESTAMPTZ, nullable): Soft removal marker when a post owner
  removes someone else's comment from their post.
- `moderated_by_user_id` (UUID FK → `users.id`, nullable): Which post owner
  performed the moderation action.

Only comments where both `deleted_at` and `moderated_at` are `NULL` are visible
in Explore reads and counted in `explore_posts.comment_count`. Comment author
names, usernames, and avatars are not copied into `explore_post_comments`;
`get_explore_comments` joins `public.users` at read time and returns
`public_author_name`, `public_username`, and `public_avatar_url` as
`author_name`, `author_username`, and `author_avatar_url`.

### `explore_comment_reactions`

Emoji reactions for Explore comments. Added in migration
`20260505000000_add_explore_comment_reactions.sql`.

- `id` (UUID): Primary key.
- `comment_id` (UUID FK → `explore_post_comments.id`, CASCADE DELETE)
- `user_id` (UUID FK → `users.id`, CASCADE DELETE)
- `emoji` (TEXT): The selected reaction emoji.
- `created_at` (TIMESTAMPTZ)
- Unique constraint: `(comment_id, user_id, emoji)` prevents a single user from
  casting the same reaction twice on a single comment.

### `explore_comment_reports`

Moderation queue ingress for abusive Explore comments. Added in migration
`20260427113000_add_explore_comment_moderation.sql`.

- `id` (UUID): Primary key.
- `comment_id` (UUID FK → `explore_post_comments.id`, CASCADE DELETE)
- `post_id` (UUID FK → `explore_posts.id`, CASCADE DELETE)
- `reporter_user_id` (UUID FK → `users.id`, CASCADE DELETE)
- `comment_author_user_id` (UUID FK → `users.id`, CASCADE DELETE)
- `reason` (TEXT): Current client values are `Spam`, `Harassment`,
  `Inappropriate content`, or `Other`.
- `details` (TEXT, nullable): Optional freeform context from the caller.
- `created_at` (TIMESTAMPTZ): Report creation time.

Uniqueness is enforced on `(comment_id, reporter_user_id)` so repeat reports
from the same viewer update the existing row instead of creating duplicates.

### `explore_post_notifications`

In-app Explore activity feed for Explore post owners and comment authors. Added
in migration `20260427010000_add_explore_notifications.sql`.

- `id` (UUID): Primary key.
- `user_id` (UUID FK → `users.id`, CASCADE DELETE): Notification recipient.
  Post-like and post-comment rows target the Explore post owner;
  comment-reaction rows target the comment author; follow rows target the
  followed user.
- `post_id` (UUID FK → `explore_posts.id`, CASCADE DELETE, nullable): The post
  the activity belongs to. `NULL` for follow notifications because they are not
  post-backed.
- `community_request_id` (UUID FK → `explore_community_requests.id`, nullable):
  Present for Community Identification notifications.
- `type` (`public.explore_notification_type`): `'like_aggregated'` | `'comment'`
  | `'comment_reaction'` | `'comment_reply'` | `'comment_mention'` | `'follow'`
  | `'community_identification_added'` | `'community_request_resolved'` |
  `'community_identification_helped'`.
- `comment_id` (UUID FK → `explore_post_comments.id`, nullable): Present for
  comment and comment-reaction notifications.
- `reaction_emoji` (TEXT, nullable): Present only for `'comment_reaction'` rows
  so the client and push layer can render the reacted emoji.
- `triggering_user_id` (UUID FK → `users.id`, nullable): The latest actor for
  aggregated likes and comment reactions, the comment author for plain comment
  rows, or the follower for follow rows.
- `recent_actor_ids` (UUID array): Latest actor IDs for aggregated-like and
  aggregated comment-reaction rows, capped at 3 entries.
- `action_count` (INT): Aggregate like count for `'like_aggregated'`, aggregate
  reactor count for `'comment_reaction'`, and always `1` for plain comment and
  follow notifications.
- `is_read` (BOOLEAN): Client-controlled read state for the in-app bell badge
  and notifications sheet.
- `created_at` / `updated_at` (TIMESTAMPTZ): Ordering keys for the notifications
  feed.

**Uniqueness + RLS**:

- Partial unique index on `(user_id, post_id, type)` where
  `type = 'like_aggregated'` guarantees a single aggregated like row per
  owner/post.
- Partial unique index on `comment_id` where `type = 'comment'` guarantees one
  notification row per comment.
- Partial unique index on `(user_id, comment_id, reaction_emoji)` where
  `type = 'comment_reaction'` guarantees one aggregated reaction row per
  recipient/comment/emoji.
- Partial unique index on `(user_id, triggering_user_id, type)` where
  `type = 'follow'` guarantees one follow notification row per follower/followee
  pair.
- Partial unique indexes on `(user_id, community_request_id, type)` guarantee
  one active notification row per recipient/request for each Community
  notification type.
- Row Level Security allows users to `SELECT` and `UPDATE` only their own
  notification rows.

**Lifecycle triggers**:

- `sync_like_notification_for_post(target_post_id)` recomputes aggregated like
  notifications from the authoritative `explore_post_likes` table after every
  insert/delete, excludes self-likes, refreshes `recent_actor_ids`, resets
  `is_read = false`, and deletes the row when the non-self like count reaches
  `0`.
- Comment notification triggers suppress self-comments, create a notification
  row on insert, delete the row when the comment is soft-deleted, and recreate
  it if the comment is restored.
- `sync_comment_reaction_notification_for_comment(target_comment_id, target_emoji)`
  recomputes aggregated comment-reaction notifications from
  `explore_comment_reactions`, excludes self-reactions by the comment author,
  tracks the latest reactor plus up to three recent actors, and deletes the row
  when no non-self reactions remain for that emoji.
- Follow notification triggers create a postless `follow` row after a follow
  insert when the follower is not shadowbanned and the users do not block each
  other. The row is deleted when the follow is removed.
- Community identification triggers aggregate new active IDs for the request
  owner, create an owner notification when consensus resolves, and create helper
  notifications for active compatible identifiers.
- A post-level trigger deletes Explore notifications when
  `explore_posts.unshared_at` is set, keeping the activity feed aligned with the
  existing soft-unshare model.
- A block trigger removes follow notification rows when either user blocks the
  other.
- A push-delivery trigger invokes the `send-push-notification` Edge Function for
  newly inserted visible post-backed rows and for like/comment-reaction
  aggregate updates where `action_count` increased. It also dispatches Community
  request notifications and Community aggregate updates where `action_count`
  increased. It intentionally skips `type = 'follow'`.

### `user_push_devices`

Remote push device registry for Explore activity delivery. Added in migration
`20260427010002_add_explore_push_delivery.sql`.

- `id` (UUID): Primary key.
- `user_id` (UUID FK → `users.id`, CASCADE DELETE): Owning Merian user.
- `device_token` (TEXT): Lowercase APNs token, unique per
  `(device_token, platform, environment)`.
- `platform` (TEXT): Currently `'ios'`.
- `environment` (TEXT): `'sandbox'` or `'production'` so debug and release
  tokens are routed to the correct APNs host.
- `explore_enabled` (BOOLEAN, default `TRUE`): Whether this device should
  receive remote Explore activity pushes.
- `comment_mentions_enabled` (BOOLEAN): Whether this device should receive
  remote pushes for `comment_mention` Explore notifications. Defaults to `TRUE`
  and is independent from `explore_enabled`, which controls
  likes/comments/replies on the viewer's own Explore activity.
- `community_identifications_enabled` (BOOLEAN): Whether this device should
  receive remote pushes for Community Identification updates. Defaults to `TRUE`
  and is independent from regular Explore activity pushes.
- `is_active` (BOOLEAN): Disabled when APNs reports a terminal token failure.
- `last_registered_at` (TIMESTAMPTZ): Last successful registration heartbeat
  from the app.
- `last_error_at` / `last_error_reason` (TIMESTAMPTZ / TEXT, nullable): Most
  recent push delivery failure metadata.
- `created_at` / `updated_at` (TIMESTAMPTZ): Auditing fields.

### Explore read RPCs

Explore uses SQL RPCs to project a privacy-safe public read model out of
`explore_posts`, `scans`, `users`, and `species_dictionary`.

`public.explore_post_species_common_name(snapshot_common_name, common_names,
scientific_name)`
centralizes post-name fallback. Feed, detail, author, map, and hashtag post
projections call this helper so an Explore post shows the author-selected
`explore_posts.species_common_name` snapshot when one exists and falls back to
dictionary English common names or the scientific name for legacy posts.

The same Explore projections also expose `scans.pet_identification` when
present. Clients may use `pet_identification.label` as the visible dog/cat card
title, but the projected `species_common_name` and `species_scientific_name`
remain unchanged for dictionary navigation, species statistics, and taxonomy
surfaces.

Migration `20260505120000_add_explore_feed_filters.sql` also added
`public.haversine_distance_meters(...)`, which the nearby feed uses to
radius-filter post-owned public coordinates without exposing raw scan
coordinates to the client contract.

- `public.get_explore_feed(self_id UUID, max_limit INTEGER, before_shared_at TIMESTAMPTZ, before_post_id UUID)`:
  The shipped `recent` feed projection. It returns reverse-chronological feed
  rows with public author identity, hero image URL, coarse location, optional
  public telemetry (`time_of_day`, `current_month`, `weather_condition`,
  `weather_temperature_f`), denormalized like/comment counts, viewer-specific
  flags (`viewer_has_liked`, `is_owned_by_viewer`), and a compatibility
  `ranking_value` column that is `NULL` for this mode. `author_avatar_url` is
  sourced from `public.users.public_avatar_url`, never directly from
  `auth.users`. Paging is stable on `(shared_at DESC, post_id DESC)` so new
  posts inserted above the viewer do not cause skips or duplicates while
  scrolling.
- `public.get_explore_feed_following(self_id UUID, max_limit INTEGER, before_shared_at TIMESTAMPTZ, before_post_id UUID)`:
  The shipped `following` feed projection. It returns the same card-shaped rows
  as `get_explore_feed`, but joins `public.user_follows` so only followed
  authors' currently visible posts survive. It preserves all standard Explore
  filters for unshared, tombstoned, media-less, shadowbanned, blocked, and
  non-species-backed content. Post `location_sharing` controls public location
  output rather than post visibility. Paging is stable on
  `(shared_at DESC, post_id DESC)`.
- `public.get_explore_feed_trending(self_id UUID, max_limit INTEGER, before_ranking_value DOUBLE PRECISION, before_shared_at TIMESTAMPTZ, before_post_id UUID)`:
  The shipped `trending` feed projection. It ranks posts by trailing-30-day like
  activity, then breaks ties on `(shared_at DESC, post_id DESC)`. The response
  populates `ranking_value` with the recent-like count used for pagination, and
  the cursor is stable on `(ranking_value DESC, shared_at DESC, post_id DESC)`.
- `public.get_explore_feed_nearby(self_id UUID, target_latitude DOUBLE PRECISION, target_longitude DOUBLE PRECISION, max_limit INTEGER, before_shared_at TIMESTAMPTZ, before_post_id UUID)`:
  The shipped `nearby` feed projection. It reads `explore_posts.public_latitude`
  / `public_longitude`, which are populated only from the post's saved
  `location_sharing` and the protected-species / uncertainty safety rules.
  Non-owned posts therefore need post-level `location_sharing = 'open'` and a
  stored public coordinate to match the radius query; `obscured` and `private`
  posts remain visible in non-spatial Explore feeds but cannot be discovered by
  Nearby. The RPC filters matches to roughly 50 miles around the viewer, then
  sorts surviving rows by `(shared_at DESC, post_id DESC)`. This keeps the
  client feed feeling like Explore rather than a pure nearest-neighbor list
  while preserving the same coordinate boundary used by the map.
- `public.get_explore_post(self_id UUID, target_post_id UUID)`: Returns the same
  card projection as `get_explore_feed` for a single post. This is used by
  notification taps and future deep-link paths so routing does not depend on the
  post already being present in the loaded in-memory feed page.
- `public.get_explore_post_detail(self_id UUID, target_post_id UUID)`: Returns a
  single public species-detail projection for the Explore detail page. Fields
  currently include `field_notes`, `species_dictionary_id`,
  `alternative_common_names`, taxonomy ranks (`kingdom`, `phylum`, `class`,
  `order`, `family`, `genus`), conditional public `ai_reasoning`,
  `habitat_description`, `gbif_taxon_key`, `iucn_red_list_status`,
  `wikipedia_url`, `reference_image_url`, `wikipedia_overview`, and
  `similar_species` JSONB hydrated from `species_lookalikes`.
  `reference_image_url` is still a comma-separated compatibility string, but the
  RPC composes it through `public.public_species_reference_image_urls(...)` from
  `species_reference_images` first and falls back to
  `species_dictionary.reference_image_url`. `similar_species` is projected
  through `public.public_species_similar_species(...)` so common-name, thumbnail
  fallback, relation ordering, rejection filtering, and optional explanation
  metadata match `/species-dictionary`. It enforces the same unshared, media,
  shadowban, and block filters as the feed. Post `location_sharing` is returned
  so edit surfaces can hydrate the saved post-level location choice, but it does
  not hide an otherwise visible detail page.
- `public.get_species_content_refresh_queue(max_rows INTEGER DEFAULT 100, as_of TIMESTAMPTZ DEFAULT NOW())`:
  Internal service-role queue query over `species_content_provenance`. It
  returns stale or low-confidence species content rows with `species_id`,
  `scientific_name`, `content_key`, source metadata, timestamps, and a `reason`
  of `low_confidence` or `stale`. The function clamps `max_rows` to `1..500` and
  is not callable by public client roles.
- `public.replace_species_reference_images(p_species_id UUID, p_images JSONB)`:
  Internal service-role helper used by `refresh-species-content` after
  GBIF/Wikipedia image refreshes. It upserts refreshed image rows, removes stale
  unlicensed rows, preserves existing license/attribution/size metadata for
  matching URLs, demotes curated licensed extras behind freshly verified rows,
  and never deletes, recategorizes, or demotes `source = 'merian'` rows.
- `public.community_materialize_resolved_species(target_taxon_node_id UUID)`:
  Internal service-role helper used by Community Identification publish. It
  turns a resolved species-level `taxon_nodes` row into a minimal
  `species_dictionary` row when the species is new to Merian, records GBIF
  provenance, links the taxon node back to the dictionary row, and queues
  species-content hydration/provenance keys for alternate names, Wikipedia,
  habitat, reference images, lookalikes, and group tags. The scheduled
  `refresh-species-content` worker fills its supported GBIF/Wikipedia-backed
  subset, while `refresh-species-model-content` fills habitat, lookalikes, and
  group tags through the same species-level biology primitives used by
  `enrich-scan`.
- `public.publish_resolved_community_request_to_explore(target_post_id UUID, self_id UUID)`:
  Internal service-role helper used by `/share-scan-to-explore` when the owner
  accepts a resolved Identify request. It materializes the resolved species,
  sets `scans.confirmed_species_id`, and stamps `explore_published_at`.
- `public.refresh_merian_reference_images(p_quality_threshold INTEGER DEFAULT 80, p_per_species_limit INTEGER DEFAULT 8, p_dry_run BOOLEAN DEFAULT FALSE, p_species_confidence_threshold DOUBLE PRECISION DEFAULT 0.95)`:
  Internal service-role helper used by `/refresh-merian-reference-images`. It
  selects currently visible Explore posts, unnests all non-empty
  `scans.image_storage_urls`, requires `image_quality_score >= 80` by default,
  requires `ai_confidence_score >= 0.95` unless `confirmed_species_id` is
  present, resolves species via `COALESCE(confirmed_species_id, species_id)`,
  dedupes by `(species_id, image_url)`, promotes up to 8 Merian images per
  species, and removes Merian public rows whose source content is no longer
  visible. Public video clips are excluded from Dictionary/reference galleries.
- `public.can_view_explore_author_profile(self_id UUID, target_author_user_id UUID)`:
  Returns whether the target author has a visible Explore profile for the
  requester through either a currently visible Explore post or a visible Field
  Trip profile surface. `set-user-follow` uses this before inserting follows so
  following does not become a general user lookup surface.
- `public.get_user_follow_state(self_id UUID, target_author_user_id UUID)`:
  Returns `author_user_id`, aggregate `follower_count`, aggregate
  `following_count`, and requester-specific `viewer_is_following`. Counts ignore
  shadowbanned counterpart users and do not expose identities.
- `public.get_explore_author_profile(self_id UUID, target_author_user_id UUID, preview_limit INTEGER)`:
  Returns a public author profile row only when the target author has at least
  one currently visible Explore post or visible Field Trip profile surface for
  the requester. It emits public author identity, species count, current streak,
  52-week heatmap JSON, achievement-progress JSON, total visible published post
  count, follower/following counts, requester follow state, up to
  `preview_limit` preview posts, and Field Trip summaries. Aggregate scan stats
  are computed from all non-tombstoned scans; follow counts are computed from
  `user_follows`; preview posts use the stricter Explore visibility filters and
  never include private, unshared, tombstoned, media-less, or
  non-species-backed scans. Active Field Trip summaries include checklist
  status only and never return scan IDs, media URLs, field notes, exact
  coordinates, public location labels, or private evidence. Achievement
  progress never returns qualifying scan IDs.
- `public.get_explore_author_posts(self_id UUID, target_author_user_id UUID, max_limit INTEGER, before_shared_at TIMESTAMPTZ, before_post_id UUID)`:
  Returns the author's currently visible published Explore posts for the full
  profile library. Rows share the same card projection as the feed, use the same
  visibility filters as `get_explore_author_profile.preview_posts`, and page
  stably on `(shared_at DESC, post_id DESC)`.
- `public.field_trip_templates`:
  Curated Field Trip definitions with slug, title, region/season/habitat tags,
  difficulty, Pro/rotating-free access flags, active state, optional cover
  image, estimated duration, and curated guide sections.
- `public.field_trip_levels`:
  Sequential levels for a template. Levels unlock in `level_number` order.
- `public.field_trip_checklist_items`:
  Curated checklist prompts for each level. Items support species,
  scientific-name, taxonomy/group, habitat/ecology, prompt-text matching, and
  optional curated item-level tips.
- `public.user_field_trips`:
  Per-user progress rows with start time, current level, profile visibility,
  completion time, and denormalized progress counts.
- `public.user_field_trip_item_completions`:
  Idempotent item completion rows linking a Field Trip item to the saved scan
  that completed it. Rows are written only for caller-owned scans made after the
  Field Trip start time.
- `public.field_trip_publications`:
  Published Field Trip snapshot headers with user-editable title, optional
  description, optional AI summary, counts, author/template linkage, and
  optional profile pin position metadata capped at 3 per author.
- `public.field_trip_publication_items`:
  Snapshot item rows for published pages. These can include species/taxonomy
  labels and selected snapshot media, but they do not make the underlying scans
  Explore posts.
- `public.field_trip_publication_likes`:
  Field Trip publication likes, separate from `explore_post_likes`.
- `public.field_trip_publication_comments`:
  Field Trip publication comments and one-level replies, separate from
  `explore_post_comments`.
- `public.field_trip_activity_notifications`:
  Field Trip-only in-app activity rows for publication comments, replies, and
  followed-author publications. These rows are separate from
  `explore_post_notifications` and never trigger APNs, widgets, feed cards, map
  rows, or `explore_posts`. `type` is checked text
  (`field_trip_comment`, `field_trip_reply`, or
  `field_trip_followed_publication`) rather than a new
  `explore_notification_type` enum value, so the migration can deploy in one
  transaction while keeping Field Trip activity separate from push-backed Explore
  notifications.
- `public.field_trip_challenges`:
  Curated/admin-created seasonal challenge definitions linked to a Field Trip
  template. Rows store title, description, cover image, start/end timestamps,
  region/season/habitat tags, normalized suggested hashtags, access flags,
  active state, and sort order.
- `public.field_trip_challenge_participants`:
  Explicit per-user challenge joins with `joined_at`, linked
  `user_field_trip_id`, current level, completion time, badge timestamp, and
  private/profile visibility flags.
- `public.field_trip_challenge_item_completions`:
  Challenge-specific item completions keyed by participation and checklist item.
  Rows link to caller-owned scans made after `joined_at` and before the
  challenge `ends_at`; they do not retroactively satisfy normal Field Trip
  progress.
- `public.field_trip_challenge_badges`:
  Completion badge rows for non-competitive challenges. Profile-visible badges
  expose no scan IDs, media, exact locations, notes, or private evidence.
- `public.field_trip_challenge_entries`:
  Published challenge completion snapshots. These are distinct from
  `field_trip_publications` so repeat seasonal challenges on the same template
  do not overwrite normal Field Trip publication history.
- `public.field_trip_challenge_entry_items`:
  Snapshot item rows for challenge entries, including species/taxonomy labels
  and selected snapshot media without creating Explore posts.
- `public.field_trip_challenge_entry_likes`:
  Challenge entry likes, separate from Explore post likes and normal Field Trip
  publication likes.
- `public.field_trip_challenge_entry_comments`:
  Challenge entry comments and one-level replies, separate from Explore post
  comments and normal Field Trip publication comments.
- `public.get_field_trip_catalog(self_id UUID, user_region TEXT, max_limit INTEGER)`:
  Returns active templates with access state, levels, checklist items, and the
  requester's progress.
- `public.get_field_trip_template_detail(self_id UUID, target_template_id UUID, target_slug TEXT)`:
  Returns one catalog-shaped template payload with guide fields, item tips,
  access state, and viewer progress.
- `public.start_field_trip(self_id UUID, target_template_id UUID)`:
  Explicitly starts or unhides the caller's progress row for an accessible
  Field Trip template.
- `public.get_field_trip_community_publications(self_id UUID, mode TEXT, target_template_id UUID, user_region TEXT, viewer_habitat_tags TEXT[], viewer_season_tags TEXT[], max_limit INTEGER, before_rank_bucket INTEGER, before_published_at TIMESTAMPTZ, before_publication_id UUID)`:
  Returns visible published completed trips for the Field Trips `Community`
  surface. `smart` ranks by followed-author and coarse region/habitat/season or
  template relevance buckets, `following` filters to `user_follows`, and
  `recent` orders reverse chronologically. Pagination is stable on
  `(rank_bucket ASC, published_at DESC, publication_id DESC)`.
- `public.get_recent_field_trip_publications(self_id UUID, user_region TEXT, viewer_habitat_tags TEXT[], max_limit INTEGER, before_published_at TIMESTAMPTZ, before_publication_id UUID)`:
  Compatibility wrapper for `get_field_trip_community_publications(...)` with
  `mode = 'recent'`.
- `public.field_trip_item_matches_scan(target_item_id UUID, target_scan_id UUID)`:
  Internal matcher used by progress application. It checks species,
  scientific-name, taxonomy/group, habitat/ecology, and prompt-text signals
  against the saved scan.
- `public.apply_field_trip_scan_progress(self_id UUID, target_scan_id UUID)`:
  Applies server-authoritative progress for one caller-owned scan. It counts
  only scans made after the trip starts and only against the current unlocked
  level.
- `public.get_field_trip_profile_summaries(self_id UUID, target_author_user_id UUID, max_limit INTEGER)`:
  Returns active status-only, pinned published, and general published Field Trip
  summaries visible to the requester. Pinned publications are omitted from the
  general published list.
- `public.set_field_trip_pinned_publications(self_id UUID, publication_ids UUID[])`:
  Replaces the caller's pinned published Field Trips, preserving supplied order
  and rejecting more than 3 publication IDs.
- `public.can_view_field_trip_publication(self_id UUID, target_publication_id UUID)`:
  Returns whether the requester may view a published Field Trip after
  publication state, shadowban, and block checks.
- `public.publish_field_trip(self_id UUID, target_user_field_trip_id UUID, title TEXT, description TEXT, ai_summary TEXT)`:
  Publishes a completed trip into Field Trip publication tables without writing
  `explore_posts`, map points, APNs, widgets, or normal Explore post
  notifications. V3 followed-author publication activity is stored only in
  `field_trip_activity_notifications`.
- `public.get_field_trip_publication_detail(self_id UUID, target_publication_id UUID)`:
  Returns a visible Field Trip publication detail payload.
- `public.get_field_trip_comments(self_id UUID, target_publication_id UUID, max_limit INTEGER, after_created_at TIMESTAMPTZ, after_comment_id UUID)`:
  Returns paginated Field Trip comments using the Explore comment-shaped client
  DTO.
- `public.get_field_trip_challenges_catalog(self_id UUID, user_region TEXT, max_limit INTEGER)`:
  Returns curated seasonal challenges with schedule status, access state,
  suggested hashtags, aggregate counts, and the requester's participation
  summary.
- `public.get_field_trip_challenge_detail(self_id UUID, target_challenge_id UUID, target_slug TEXT, entries_limit INTEGER)`:
  Returns one challenge with linked template guide context, schedule, counts,
  viewer progress, badge state, and initial published challenge entries.
- `public.join_field_trip_challenge(self_id UUID, target_challenge_id UUID)`:
  Idempotently joins a live accessible challenge, starts or continues the linked
  Field Trip, and creates/returns the separate participant row.
- `public.apply_field_trip_challenge_scan_progress(self_id UUID, target_scan_id UUID)`:
  Applies challenge progress for a caller-owned scan when the user joined the
  live challenge before the scan and the scan falls before the challenge ends.
  It returns `challenge_updates` payloads for V4 clients.
- `public.get_field_trip_challenge_hashtags_for_scan(self_id UUID, target_scan_id UUID)`:
  Returns normalized suggested hashtags for challenge items completed by a scan,
  for optional Explore composer suggestions only.
- `public.get_field_trip_challenge_publications(self_id UUID, target_challenge_id UUID, max_limit INTEGER, before_published_at TIMESTAMPTZ, before_entry_id UUID)`:
  Returns visible published challenge entries with stable
  `(published_at DESC, entry_id DESC)` pagination and Field Trip block/shadowban
  checks.
- `public.publish_field_trip_challenge_entry(self_id UUID, target_participation_id UUID, entry_title TEXT, entry_description TEXT)`:
  Publishes or updates a completed challenge participation into challenge entry
  snapshot tables without writing Explore posts, maps, widgets, APNs, prizes,
  leaderboards, or automatic hashtags.
- `public.get_field_trip_challenge_entry_detail(self_id UUID, target_entry_id UUID)`:
  Returns a visible challenge entry detail payload.
- `public.get_field_trip_challenge_entry_comments(self_id UUID, target_entry_id UUID, max_limit INTEGER, after_created_at TIMESTAMPTZ, after_comment_id UUID)`:
  Returns paginated challenge entry comments using the compact Explore
  comment-shaped client DTO.
- `public.get_field_trip_challenge_badges(self_id UUID, target_author_user_id UUID, max_limit INTEGER)`:
  Returns profile-visible completion badges for public profile modules.
- `public.get_explore_comments(self_id UUID, target_post_id UUID, max_limit INTEGER, after_created_at TIMESTAMPTZ, after_comment_id UUID)`:
  Returns visible public comments for one Explore post. Rows are ordered on
  `(created_at ASC, comment_id ASC)`, filter soft-deleted, moderated, hidden, or
  blocked authors, expose viewer capability flags for delete/moderate/report
  actions, and include `author_avatar_url` from
  `public.users.public_avatar_url`. Paging is cursor-based so long threads do
  not skip or duplicate comments while loading more.
- `public.get_explore_map_posts(self_id UUID, north_latitude DOUBLE PRECISION, south_latitude DOUBLE PRECISION, east_longitude DOUBLE PRECISION, west_longitude DOUBLE PRECISION, max_limit INTEGER)`:
  Returns privacy-safe map rows for the current visible bounds. The projection
  joins `explore_posts`, `scans`, `users`, and `species_dictionary`, emits
  `coordinate_visibility = exact|obscured`, filters unshared posts,
  media-cleared scans, shadowbanned authors, both directions of blocking, and
  any non-open post `location_sharing`. It reads post-owned public coordinates
  from `explore_posts.public_latitude` / `public_longitude` and returns the
  scrubbed `explore_posts.public_location_label`; it does not derive map output
  from exact GPS or raw semantic location fields at read time.
- `public.get_explore_notifications(self_id UUID, max_limit INTEGER, before_updated_at TIMESTAMPTZ, before_notification_id UUID)`:
  Returns the owner's in-app Explore activity feed. Like rows are aggregated,
  comment rows are filtered against comment soft deletes and both-direction user
  blocks, follow rows are validated against the active `user_follows`
  relationship, Community rows include `community_request_id` and request/taxon
  display fields, and `recent_actor_names` preserves the server-side actor order
  from `recent_actor_ids`. Follow rows have `post_id = NULL` and are
  informational only; Field Trip rows have `field_trip_publication_id` and route
  to Field Trip publication detail. Paging is stable on
  `(updated_at DESC, notification_id DESC)` so new activity does not cause
  duplicates while the sheet paginates.
- `public.get_unread_explore_notification_count(self_id UUID)`: Returns the
  unread bell badge count for visible Explore notifications and Field Trip
  in-app activity rows.
- `public.mark_explore_notifications_read(self_id UUID)`: Marks all of the
  viewer's Explore notification and Field Trip activity rows as read. The iOS
  client calls this only after a successful notifications fetch.
- `public.get_explore_push_notification_payload(target_notification_id UUID)`:
  Internal push-delivery projection used by `send-push-notification`. It filters
  hidden/unshared/blocked activity the same way the in-app feed does and returns
  APNs-safe actor names plus comment body text or Community request/taxon
  display fields for one pushable notification row. Follow notifications are
  skipped before push dispatch and have no post payload.
- `public.reparent_user_follows(ghost_id UUID, target_user_id UUID)`:
  Ghost-merge helper that inserts target-user copies of ghost follower/followee
  rows, ignores conflicts, and deletes rows still referencing the ghost or any
  self-follow produced by the merge.
- `public.repair_community_request_ownership_for_user(target_user_id UUID)`:
  Repairs existing Ask the Community rows whose `requested_by` no longer matches
  the owner of their backing `scans` row. This keeps the Identify Yours filter,
  owner-only actions, and account-merge cleanup aligned after legacy ghost
  ownership drift.

These RPCs intentionally avoid raw auth metadata and private scan-only fields.
Feed/detail/notification reads avoid coordinates entirely, while
`public.get_explore_map_posts(...)` and non-owned Nearby matching read only
post-owned public coordinates from `explore_posts`. Spatial result sets require
post-level `location_sharing = 'open'`; `coordinate_visibility = obscured` is
reserved for open posts whose public coordinates are rounded by species-safety
or uncertainty rules. Together these RPCs allow Explore to reuse safe species
visuals such as taxonomy and habitat/distribution cards without mounting the
private Insight `InferenceEngine`.

### `00007_auto_purge_nonbio_cron.sql` (Lifecycle Sync)

Configures the automated garbage collection pipeline using `pg_cron` and
`pg_net`. Schedules an HTTP POST to the `/functions/v1/auto-purge-nonbio` Deno
node at 03:00 UTC, authenticating via `SUPABASE_SERVICE_ROLE_KEY` from
`vault.decrypted_secrets`. Bridges logical `is_biological_subject = false`
database purges with Cloudflare R2 object deletion to prevent storage bloat.

### `20260513070000_add_species_content_refresh_worker_schedule.sql`

Adds `public.replace_species_reference_images(...)` and schedules the
`refresh_species_content_hourly` `pg_cron` job. The job posts to
`/functions/v1/refresh-species-content` at minute 17 every hour using
`SUPABASE_SERVICE_ROLE_KEY` from Vault/current settings and a small
`{ "limit": 25 }` body. The Edge worker consumes
`get_species_content_refresh_queue(...)`, refreshes externally authoritative
species fields, and leaves model/curation-backed fields untouched until
dedicated tooling exists.

### `20260513080000_add_merian_reference_image_refresh.sql`

Adds `merian` as a reference-image source, the private
`species_reference_image_merian_sources` provenance table,
`public.refresh_merian_reference_images(...)`, Merian-first public ordering, and
the `refresh_merian_reference_images_hourly` cron job. The job posts to
`/functions/v1/refresh-merian-reference-images` at minute 37 every hour with
`{ "quality_threshold": 90, "per_species_limit": 8 }`.

### `20260514110000_add_species_confidence_gate_to_merian_reference_images.sql`

Adds private species-confidence provenance fields to
`species_reference_image_merian_sources`, replaces
`public.refresh_merian_reference_images(...)` with a confidence-aware helper,
and reschedules the hourly cron payload with
`{ "quality_threshold": 90, "species_confidence_threshold": 0.95, "per_species_limit": 8 }`.
AI-resolved scans must meet both the image-quality and species-confidence gates;
confirmed-species scans may qualify through `confirmed_species_id` while still
recording their raw AI confidence privately.

### `20260617120000_lower_merian_reference_image_quality_threshold.sql`

Lowers the current Merian reference-image quality threshold to
`image_quality_score >= 80`, updates the SQL helper default, and reschedules the
hourly cron payload with
`{ "quality_threshold": 80, "species_confidence_threshold": 0.95, "per_species_limit": 8 }`.

## SwiftData Schema (Local Offline Queue)

_Note: The iOS persistence layer is enforced via `ModelContainer` in
`MerianApp.swift`. If a store open fails during a production app update, the
application first uses store metadata to choose the narrowest safe migration
strategy, attempts corruption-specific quarantine and retry only for verified
store corruption, archives non-corrupt legacy migration failures under
`store-rescue/` before opening a fresh persistent store, then falls back to an
in-memory safe-mode container if recovery fails, and finally shows a
startup-blocked recovery surface if no container can be created.
It must not silently wipe `URL.documentsDirectory`, and it must not hard-crash
from bootstrap with `fatalError`. To prevent schema failures as the app evolves,
Merian uses `MerianMigrationPlan` with lightweight and custom `.migrationStage`
closures that safely transpose old structures (e.g. `MerianSchemaV8` to
`MerianSchemaV9`) without corrupting local scan data._

**File layout:** The universally active models natively live in the global
namespace within `apps/ios/Merian/Models/ActiveSchema/`. Historical schema
snapshots live in their own file (`apps/ios/Merian/Models/Schema/SchemaV1.swift`
through `SchemaV39.swift`). The file
`apps/ios/Merian/Models/SchemaVersions.swift` declares `MerianMigrationPlan` —
the ordered list of schemas and migration stages. When bumping to V{N+1}, follow
the runbook at `.agents/workflows/schema_update.md`:

1. Manually freeze the outgoing schema V{N} from the current `ActiveSchema/`
   before any changes. Declare changed models inside the schema enum body, not
   in an extension, unless a documented macro bug requires otherwise.
2. Update `SchemaV{N}.swift` or the V{N} block in `SchemaVersions.swift`
   `models` array to use fully-qualified `MerianSchemaV{N}.LocalScanRecord.self`
   references — this locks the checksum and prevents the iOS 26 "equal model
   references" crash for custom migration stages.
3. Create `SchemaV{N+1}.swift` tying its `models` array to the active global
   classes.
4. Update `typealias CurrentSchema = MerianSchemaV{N+1}` in `Aliases.swift`.
5. Add the `migrateV{N}toV{N+1}` stage to `MerianMigrationPlan.stages`.

There is **no need** to update model references in `MerianApp.swift`, nor
anywhere else in the application, because the entire app dynamically inherits
`CurrentSchema` and the active global models natively.

Custom migration stages must save through the shared migration save helper in
`SchemaVersions.swift`. The helper rolls back and rethrows on save failure, and
scratchpad namespaces are cleared only after the save succeeds. Do not use
`try? context.save()` or a bare `try context.save()` in migration code; a failed
media/history backfill must abort migration rather than silently opening an
incomplete upgraded store. Migration fetch failures must also propagate instead
of being logged and ignored. Fetches inside migration stages must use the
concrete schema type for that stage (`MerianSchemaV{N}.LocalScanRecord`, etc.),
not `CurrentSchema` or active global models, because the migration context is
bound to historical model metadata. Relationship models that are added in a
historical schema must also be schema-scoped snapshots; V41 owns
`MerianSchemaV41.CapturedMediaEntry` so V40→V41 can create media-entry rows
without SwiftData casting V41 records to active `LocalScanRecord` or
`OfflineQueuedScan`. Custom migrations that create relationship rows must insert
each new row into the migration `ModelContext` before assigning the relationship;
relationship assignment alone is not a durable insert path while SwiftData is
inside staged store migration.

The current active schema is `MerianSchemaV49`. Recent milestones:

- V38 added single-value audio/context storage (`audioFilePath`,
  `observationContextJSON`) to both local and offline scan models.
- V39 normalized those payloads into array-based intermediates
  (`audioFilePaths`, `observationContextsJSON`) for mixed-media migration
  safety.
- V40 added `capturedMediaJSON` and `coverImagePath`, backfilling the ordered
  mixed-media history used by the active models. `capturedMediaJSON` remains the
  preferred scalar read source for hot UI paths.
- V41 added first-class schema-scoped `CapturedMediaEntry` rows and
  `capturedMediaEntries` relationships on both `LocalScanRecord` and
  `OfflineQueuedScan`, while continuing to write `capturedMediaJSON` as the
  scalar durability/read mirror.
- V42 added first-class `fieldNotes` columns to both `LocalScanRecord` and
  `OfflineQueuedScan`, then performed the active-schema handoff after freezing
  V41 snapshots. The legacy per-scan UserDefaults bridge remains a fallback
  only; `FieldNotesRepository` promotes bridge-only notes back into SwiftData.
- V43 added AI-derived sex observation metadata (`sex`, `sexConfidence`,
  `sexEvidence`) to completed local scans, matching the cloud `scans` columns
  introduced by migration `20260518090000_add_scan_sex_metadata.sql`.
- V44 added optional `petIdentificationData` to completed local scans. It stores
  the sanitized dog/cat `PetIdentification` object from `public.scans` so
  Insight, library search, sharing, and Explore can show a confident pet label
  without rewriting species taxonomy or preferred-name data.
- V45 added optional invasive-status context (`invasiveStatusRegion`,
  `invasiveRationale`, `invasiveConfidence`) to completed local scans, matching
  the cloud `scans` columns introduced by migration
  `20260703120000_add_invasive_context_to_scans.sql`.
- V46 was a shipped no-op schema with the same SwiftData model checksum as V45.
  V44/V45/V46 remain available as historical types and source-specific recovery
  inputs, but they must not appear in the full historical
  `MerianMigrationPlan.schemas` or `MerianMigrationPlan.stages`; that plan jumps
  V42→V49 or V43→V49 so unknown older stores do not force SwiftData to validate the
  duplicate-prone recent representatives. V47 keeps local-scan, captured-media,
  and collection entities frozen inside V47, and keeps its queued scan model
  scalar-only. V44, V45, and V46 stores skip V47 and jump directly to V49 from
  source-isolated V44→V49, V45→V49, and V46→V49 plans so SwiftData never
  migrates unchanged entities across duplicate-prone recent representatives.
  App startup reads store metadata before creating `ModelContainer`: fresh/current
  stores open without a migration plan, known recent stores use the source-isolated
  V48/V47/V46/V45/V44/V43/V42 plans, and only unknown older stores use the full
  historical plan. The V42 and V43 recent plans jump directly to V49 to avoid
  validating older full-historical custom stages and to keep V42 off the older
  V42→V43 bridge that still failed on real TestFlight stores, while V45 and V46 deliberately use one
  matching source representative each before the V49 repair target.
  Stores that still hit SwiftData's duplicate-checksum validator during plan
  construction retry with the same source-isolated recent plans before legacy
  rescue or safe mode.
- V47 added `OfflineQueuedScan.inferenceImagePaths` and `visualMediaItemsJSON`
  so queued video replay can keep sampled inference frames separate from the
  user-visible playback video timeline.
- V48 added persisted queue retry metadata on `OfflineQueuedScan`, plus
  `OfflineJobRecord` and bounded `OfflineQueueEvent` models for scan ingestion,
  cloud deletion, collection sync, diagnostics, and future offline work.
- V49 is a startup store-repair schema. It preserves the V48 scheduler model,
  adds `OfflineQueuedScan.queueSchemaRepairGeneration`, and migrates both the
  known-good V48 source and the accidental optional-queue V48 TestFlight source
  forward through source-specific V48→V49 plans. Startup diagnostics now record
  redacted store metadata, model-version fingerprints, attempted plan names, and
  error-domain/code fingerprints so failing devices can share evidence without
  exposing local paths, account IDs, scan text, or media URLs.

**Edge DTO Layer** (`apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift`): Declares
`EdgeResponseWrapper`, `EdgeResponse` (the `/identify` response), and
`EnrichScanResponse` (the `/enrich-scan` response). `EnrichScanResponse`
contains nested `EnrichData` (maps `habitat_description`, `gbif_taxon_key`,
`taxonomy`, and `similar_species: [SimilarSpeciesEntry]?`) and
`SimilarSpeciesEntry` (maps `scientific_name`, `common_name`,
`reference_image_url`, `iucn_red_list_status`, plus optional lookalike relation
metadata such as `reason`, `visual_traits`, `confidence`, `source`,
`review_status`, `is_bidirectional`, and `sort_order`) structs. `EdgeResponse`
also contains a nested `IdentificationCandidate` struct
(`scientific_name: String`, `confidence_score: Double`,
`distinguishing_feature: String?`) and a
`candidates: [IdentificationCandidate]?` field mapping the `/identify` response
candidates array. `distinguishing_feature` is required in the Gemini schema and
TypeScript types but optional in Swift (`String?`) for graceful decoding of
pre-migration JSONB rows that have the two-field shape. `EdgeResponse`
additionally contains a nested `ImageQuality` struct (`sharpness: Int?`,
`framing: Int?`, `diagnostic_utility: Int?`, `overall_score: Int?`) and an
`image_quality: ImageQuality?` field. `EdgeResponse` may also include
`pet_identification: PetIdentification?`, decoded into `SpeciesData` only when
the sanitized confidence is displayable. When adding new fields to either Edge
Function response, update both the TypeScript schema and the corresponding Swift
`Codable` struct simultaneously.

**`SpeciesData` pet display field**
(`apps/ios/Merian/Models/SpeciesData.swift`): `PetIdentification` is a
`Codable`, `Equatable`, `Hashable`, and `Sendable` value with `speciesGroup`,
`label`, `labelType`, `confidenceScore`, and `evidence`.
`SpeciesData.petIdentification` is optional and display-only. It can make the
Insight headline read like "Australian Cattle Dog mix" while the subtitle still
shows the underlying scientific name, such as `Canis lupus familiaris`. It must
not be stored as a species preferred common name.

**`SpeciesData` override fields** (`apps/ios/Merian/Models/SpeciesData.swift`):
`SpeciesData` carries four identification-review fields that are never part of
the Edge response but are synthesised from `LocalScanRecord` when opening a
historical scan:

- `aiScientificName: String` — always set to `LocalScanRecord.scientificName`
  (the AI's original identification). Preserved immutably (`let`) so the UI can
  display "AI originally suggested X" after an override. Derived in
  `InferenceEngine.load(from:)` as `record.scientificName`.
- `userIdentificationOverride: String?` — mirrors
  `LocalScanRecord.userIdentificationOverride`. When non-nil,
  `InferenceEngine.load(from:)` sets `speciesData.scientificName` to the
  override name directly (not via an async patch), so the correct title is
  immediately visible on sheet open. All accompanying species-dict fields
  (`commonName`, `hazardType`, `taxonomy`, etc.) are persisted to
  `LocalScanRecord` by `fetchAndPatchOverrideData` →
  `BackgroundDatabaseActor.updateScanWithOverrideSpeciesData` when the override
  is first applied, so they survive reopen without a network call. Drives the
  "Your ID" state in `ConfidenceBadge`.
- `userConfirmedIdentification: Bool` — mirrors
  `LocalScanRecord.userConfirmedIdentification`. Cloud-synced. Drives the
  "Confirmed" state in `ConfidenceBadge`.
- `isFlagged: Bool` — mirrors `LocalScanRecord.isFlagged`. Legacy V31 moderation
  field retained for schema compatibility; it no longer affects the Insight
  confidence badge or candidate-review UI.

**`SpeciesData` mutable display fields**: Three `SpeciesData` properties are
declared `var` (not `let`) specifically because the identification override
hydration path (`fetchAndPatchOverrideData`) patches them in-place after
querying `species_dictionary` for the override species:

- `var scientificName: String` — patched by `applyIdentificationOverride` and
  `resetIdentificationReview` to the chosen/reverted name. On `load(from:)`, set
  to `userIdentificationOverride ?? record.scientificName` so the correct name
  is visible immediately.
- `var commonName: String` — patched by `fetchAndPatchOverrideData` to the
  override species' canonical common name from
  `species_dictionary.common_names`. Also persisted to
  `LocalScanRecord.commonName` by `updateScanWithOverrideSpeciesData` so the
  name survives reopen.
- `var iucnRedListStatus: String?` — patched by `fetchAndPatchOverrideData` to
  the override species' conservation status. Also persisted to
  `LocalScanRecord.iucnRedListStatus` by `updateScanWithOverrideSpeciesData`.

`aiScientificName` remains `let` — it is set once at init and never mutated,
making it a safe anchor for revert operations regardless of how many times the
user cycles through overrides.

**Historical Sync DTO**
(`apps/ios/Merian/Core/Data/Database/ScanRepository.swift`):
`HistoricalScanResponse` (the cloud sync DTO) includes
`candidates: [CloudIdentificationCandidate]?`,
`pet_identification: PetIdentification?`,
`user_identification_override: String?`, `user_confirmed_identification: Bool?`,
and `image_quality_score: Int?` fields. `CloudIdentificationCandidate` is a
plain `Codable` struct (`scientific_name: String`, `confidence_score: Double`)
that maps the JSONB array from `public.scans`. `ingestScans` re-encodes
candidates to `[IdentificationCandidate]`, writes
`user_identification_override`, writes `user_confirmed_identification`
(defaulting to `false`), and writes `image_quality_score`. `updateExistingScans`
only writes `candidatesData` if `existing.candidatesData == nil`; only writes
`userConfirmedIdentification` in the `true` direction (cloud=true, local=false)
to avoid overwriting an unsynced local state; backfills `imageQualityScore` when
the local value is `nil` and the cloud has a value.

### `OfflineQueuedScan`

Captures state when network connectivity is unavailable. `MerianSchemaV13` added
`zoomFactor` so the active zoom level is preserved through offline queuing and
replayed to the Edge function when connectivity is restored. `MerianSchemaV40`
introduced the canonical ordered mixed-media timeline, and `MerianSchemaV41`
promoted that timeline into a first-class related model while keeping the JSON
mirror for migration safety and compatibility.

- `id`: String (UUID)
- `timestamp`: Date
- `capturedMediaJSON`: String? (Added in `MerianSchemaV40`. Preferred scalar
  read source for the ordered mixed-media timeline. Still written alongside
  relationship rows so UI, migration, and lightweight fetch paths can
  reconstruct media without faulting child `@Model` objects.)
- `capturedMediaEntries`: [CapturedMediaEntry]? (Added in `MerianSchemaV41`.
  Relationship mirror of the ordered persisted media timeline. Each entry stores
  its slot index, modality, storage location, and either a media path or
  serialized description payload. Used as a fallback if `capturedMediaJSON` is
  missing or unparsable.)
- `coverImagePath`: String? (Added in `MerianSchemaV40`. First image extracted
  from the canonical media timeline, used for queue thumbnails without reparsing
  the full payload.)
- `fieldNotes`: String? (Added in `MerianSchemaV42`. Private user-authored notes
  captured while the scan is queued. These are carried through
  `BackgroundDatabaseActor` when the queued row becomes a `LocalScanRecord` and
  are resolved through `FieldNotesRepository` before falling back to the legacy
  UserDefaults bridge.)
- `gpsLatitude`, `gpsLongitude`, `gpsElevation`: Double?
- `weatherCondition`, `locationName`: String?
- `weatherTemperatureF`, `blurScore`: Double?
- `subjectDistanceInMeters`: Float?
- `zoomFactor`: Double? (Added in `MerianSchemaV13`. Active zoom factor at
  capture. `nil` at 1× — omitted when it carries no signal.)
- `scanStateRaw`: Int (Added in `MerianSchemaV33`. Raw value of
  `ScanQueueState`, replacing the old `isUploaded: Bool` + `isDeleted: Bool`
  pair. Stored as `Int` for `#Predicate` compatibility. Valid values: `0` =
  `.pending`, `1` = `.uploading`, `2` = `.staged`, `3` = `.inferencing`, `5` =
  `.failed` (raw value 4 reserved). Defaults to `0` (`.pending`). Access via the
  typed `queueState: ScanQueueState` computed property — never read
  `scanStateRaw` directly in business logic. The `migrateV32toV33` custom
  migration stage backfills this field from the old booleans: `isDeleted=true` →
  `5`, `isUploaded=true` → `2`, else → `0`.)
- `stagedR2Keys`: [String]? (Added in `MerianSchemaV33`. Cloudflare R2 object
  keys written atomically by `BackgroundDatabaseActor.markScanAsStaged` when the
  last media upload receives HTTP 200. The array may contain image staging keys
  plus queued-audio and queued-video staging keys;
  `dispatchInferenceDownloadTask` splits them into `r2ObjectKeys`,
  `audioR2ObjectKeys`, and `videoR2ObjectKeys` based on the canonical media
  timeline. Eliminating auth-dependent key reconstruction at inference time —
  keys are recorded at upload-completion time under the auth session that
  performed the upload, preventing the 403 IDOR edge case that occurred when
  keys were reconstructed hours later from an expired session. `nil` for scans
  migrated from V32; `replayInferenceForUploadedScans` falls back to
  reconstructing keys from the current session for those records.)
- `inferenceImagePaths`: [String]? (Added in `MerianSchemaV47`.
  Documents-relative image filenames used only for inference replay. Video
  captures store sampled frames here while `capturedMediaJSON` keeps the
  user-facing media timeline as one video item with a thumbnail.)
- `visualMediaItemsJSON`: String? (Added in `MerianSchemaV47`. Encoded
  `[IdentifyVisualMediaItem]` aligned one-to-one with `inferenceImagePaths`, so
  replay can tell `/identify-multimodal` which inference images are still photos
  versus ordered video frames.)
- `queueAttemptCount`: Int (Added in `MerianSchemaV48`. Persisted retry count
  for the queued scan. Replaces the older process-local `uploadRetryCount`
  authority and feeds the automatic retry budget.)
- `queueLastAttemptAt`, `queueNextRetryAt`: Date? (Added in V48. Used by
  `OfflineQueueRetryPolicy` and the scheduler to survive app relaunch without
  losing backoff state.)
- `queueLastErrorCode`, `queueLastErrorMessage`: String? (Added in V48.
  User/support-facing last local retry or terminal error.)
- `queueLastHTTPStatus`: Int? (Added in V48. Last HTTP response status
  associated with upload or inference retry handling.)
- `queueLastServerStatus`, `queueLastServerStage`: String? (Added in V48.
  Mirrors `/check-scan-status` ingestion job state for server-owned work.)
- `queueLastServerRetryAfter`: Date? (Added in V48. Parsed server retry window
  for retryable ingestion jobs.)
- `queueUpdatedAt`: Date (Added in V48. Last durable queue metadata mutation.)
- `queueNeedsAttention`: Bool (Added in V48. Terminal user-actionable local
  problems stay visible instead of being purged as disposable tombstones.)
- `queueSchemaRepairGeneration`: Int (Added in V49. Marks queued scans that have
  passed through the startup repair schema. Defaults to `1`; used as a checksum
  differentiator and a simple support signal when diagnosing V48 store repair.)

The V47→V49 migration is custom. It initializes the retry/status fields for
every existing queued scan and creates a `scan-ingestion:{scanId}`
`OfflineJobRecord` so stores that already contain queued image, video, audio, or
description scans reopen persistently instead of falling back to safe mode after
the schema update. Preserve the display timeline (`capturedMediaJSON` /
`capturedMediaEntries`) and inference-only video frame fields during this
backfill. V47 source stores snapshot every queued-scan field needed to recreate
the row in `willMigrate`, delete the scalar V47 source rows, then use those
snapshots to repair or recreate current-schema queued scans and seed
`OfflineJobRecord` / `OfflineQueueEvent` rows. That avoids SwiftData carrying a
stale V47 model identity into V49 while preserving all queued media kinds.

The V48→V49 migrations snapshot queued scans before recreating V49 rows and normalize
queued-scan retry metadata. Known-good V48 stores migrate directly to V49. The accidental
optional-queue V48 TestFlight source has its own `MerianSchemaV48OptionalQueue`
and recovery plan; it snapshots optional queue fields in `willMigrate`, deletes
the source rows, and recreates V49 queued scans with non-optional defaults
(`queueAttemptCount = 0`, `queueUpdatedAt = now`, `queueNeedsAttention = false`)
when the optional source stored `nil`.

### `OfflineJobRecord`

Added in `MerianSchemaV48` and carried forward unchanged in V49.
Scheduler/control-plane row for media-agnostic
offline work. Current `kindRaw` values are `scanIngestion`, `cloudDeletion`,
`collectionSync`, `speciesPreferenceSync`, and `future`; current `statusRaw`
values are `pending`, `running`, `waiting`, `needsAttention`, `complete`, and
`cancelled`.

- `id`: String (unique stable job id such as `scan-ingestion:{scanId}`,
  `cloud-deletion:{scanId}`, or `collection-sync`.)
- `kindRaw`, `statusRaw`: String enum raw values.
- `subjectId`: String? (Scan id or other domain id, when applicable.)
- `priority`: Int
- `createdAt`, `updatedAt`: Date
- `lastAttemptAt`, `nextRunAt`: Date?
- `attemptCount`: Int
  Tracks bounded automatic retry attempts for durable offline jobs. Scan
  ingestion, cloud deletion, and collection sync pause at `needsAttention` after
  `OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts` automatic failures.
- `lastErrorCode`, `lastErrorMessage`: String?
- `lastHTTPStatus`: Int?
- `serverStatus`, `serverStage`, `serverRetryAfter`: server ingestion status
  mirrors for scan jobs.
- `requiresUnconstrainedNetwork`, `allowsCellular`: Bool policy hints.
- `approximateBytes`: Int64 redacted local footprint estimate.
- `metadataJSON`: String? reserved for non-media scheduler metadata.

### `OfflineQueueEvent`

Added in `MerianSchemaV48`. Bounded local diagnostics rows for support export
and developer debugging. Events are metadata-only; raw media bytes and private
media paths must never be stored here.

- `id`: String
- `jobId`: String?
- `scanId`: String?
- `kindRaw`: String (`queued`, `claimed`, `uploadStarted`, `uploadCompleted`,
  `staged`, `inferenceStarted`, `serverWait`, `retryScheduled`, `completed`,
  `failed`, `cancelled`, `needsAttention`, or `diagnostics`.)
- `createdAt`: Date
- `message`, `errorCode`: String?
- `httpStatus`: Int?
- `metadataJSON`: String? metadata only; diagnostics export redacts it to a
  boolean presence flag.

### `LocalScanRecord` (Scans)

Tracks locally synchronized species scans for the Scans library.

- `id`: String (UUID bound 1-to-1 to the Postgres/Cloudflare `/scans` row ID,
  resolving the Duplicate Tile race condition).
- `speciesId`: String (UUID linking scan tiles for the same `scientificName`).
- `timestamp`: Date
- `captureDate`: Date? (Original asset capture date when available. Distinct
  from `timestamp`, which tracks when the scan record was created.)
- `capturedMediaJSON`: String? (Added in `MerianSchemaV40`. Preferred scalar
  read source for the ordered mixed-media timeline. Still maintained alongside
  V41 relationship rows so SwiftUI and historical load paths can rebuild media
  without faulting child `@Model` objects during layout.)
- `capturedMediaEntries`: [CapturedMediaEntry]? (Added in `MerianSchemaV41`.
  Relationship mirror of the persisted mixed-media timeline for the scan.
  Replaces ad hoc restoration from parallel image/audio/context fields and
  remains a fallback when the scalar JSON is unavailable.)
- `coverImagePath`: String? (Added in `MerianSchemaV40`. First image extracted
  from the canonical media timeline, used as the primary thumbnail path.)
- `scientificName`: String
- `commonName`: String
- `confidenceScore`: Double?
- `petIdentificationData`: Data? (Added in `MerianSchemaV44`. JSON-encoded
  `PetIdentification` for confident dog/cat breed, mix, coat-pattern, or
  body-type display. The computed `petIdentification` helper decodes this value
  for Insight headlines, share/export text, Explore sync, and library search. It
  does not alter `commonName`, `scientificName`, or species preference keys.)
- `fieldNotes`: String? (Added in `MerianSchemaV42`. Private user-authored
  discovery notes. Local insight surfaces read and write this through
  `FieldNotesRepository`; Explore receives a public copy only when the user
  explicitly shares notes through `/share-scan-to-explore` or
  `/update-explore-field-notes`.)
- Image, audio, and description items are restored through
  `serializedCapturedMediaItems` / `capturedMediaSnapshot`. Those helpers prefer
  `capturedMediaJSON` first and only lazily fault `capturedMediaEntries` if the
  JSON is missing or unparsable. Do not reverse this order in SwiftUI-facing
  paths: a TestFlight crash on May 12, 2026 showed SwiftData can trap in
  `_InvalidFutureBackingData.getValue` while faulting
  `CapturedMediaEntry.kindRaw` during `BiologicalView` layout.
- ~~`insightDescription`~~: Removed in `MerianSchemaV17`. Per-scan AI reasoning
  is now stored exclusively in `aiReasoning` (see below). The V17 custom
  migration stage backfills `aiReasoning` from `insightDescription` for any
  pre-V15 records that had a description but no `aiReasoning` value.
- `hazardType`: String — hazard classification for the species. One of: `"none"`
  | `"poisonous"` | `"venomous"` | `"allergenic"` | `"irritant"`. Added in
  `MerianSchemaV16`. Migration `migrateV15toV16` maps old `isPoisonous = true`
  records to `hazardType = "poisonous"`.
- `isBiological`: Bool (from Edge)
- `isLiveCapture`: Bool (from Edge)
- `isInvasive`: Bool (from Edge)
- `invasiveStatusRegion`: String? (from Edge; region label used by the original
  AI invasive-status assessment)
- `invasiveRationale`: String? (from Edge; concise explanation for the original
  AI invasive-status assessment)
- `invasiveConfidence`: Double? (from Edge; 0.0–1.0 confidence for the
  invasive-status assessment, separate from identification confidence)
- `ecologyType`: String (from Edge)
- `semanticTags`: [String] (AI-generated contextual tags powering local offline
  semantic search).
- `wikipediaUrl`: String? (Hydrated asynchronously by `BackgroundDatabaseActor`
  via REST)
- `wikipediaOverview`: String? (Wikipedia summary paragraph cached from the REST
  API. Renamed from `wikipediaExtract` in `MerianSchemaV17` using
  `@Attribute(originalName:)` — existing data is preserved automatically via
  lightweight migration. Written by
  `BackgroundDatabaseActor.updateScanWithWikipedia`.)
- `referenceImageUrl`: String? (Stores Wikipedia/GBIF biological reference
  images only. Kept separate from scan images to prevent duplication in the UI
  Image Carousel).
- `isLocallyArchived`: Bool (Legacy/backward-compatible flag for records whose
  visual payload was previously copied into local Documents storage).
- `taxonomyKingdom`, `taxonomyPhylum`, `taxonomyClass`, `taxonomyOrder`,
  `taxonomyFamily`, `taxonomyGenus`: String? (Linnaean taxonomy fields added in
  `MerianSchemaV3`, enabling background semantic discovery without relying on
  `ecology_type`.)
- `locationName`, `weatherCondition`, `weatherTemperatureF`: String/Double?
  (Added in `MerianSchemaV5`. Stores environmental context via MapKit reverse
  geocoding, powering the `InsightSheetView`.)
- `collections`: [ScanCollection]? (Added in `MerianSchemaV6`. Establishes
  relationships to top-level custom user galleries without duplicating raw
  data.)
- `similarSpecies`: [String]? — Similar or commonly confused species for the
  identified subject. Renamed from `diagnosticLookalikes` in `MerianSchemaV26`
  (backfilled via `migrateV25toV26`). Retained as a backwards-compatible
  fallback — the richer persistence path is `lookalikesData` (see below). When
  `lookalikesData` is nil (historical record), `InferenceEngine.load(from:)`
  wraps each entry in a `SimilarSpeciesEntry` with nil enrichment fields.
- `candidatesData`: Data? (Added in `MerianSchemaV28`. JSON-encoded
  `[IdentificationCandidate]` blob — each entry is
  `{ scientificName, confidenceScore }`. Written by
  `BackgroundDatabaseActor.saveLiveScanRecord` from the live `/identify`
  response, and by `ScanRepository.ingestScans` / `updateExistingScans` on
  historical cloud sync. `InferenceEngine.load(from:)` decodes this field back
  to `[IdentificationCandidate]` via `JSONDecoder` and sets it as
  `speciesData.candidates`. `nil` for scans at or above the diagnostic trigger
  where the server stripped candidates, and for all scans captured before V28. A
  lightweight migration (`migrateV27toV28`) handles the version bump — no data
  transform required since the field is optional with a nil default.)
- `userIdentificationOverride`: String? (Added in `MerianSchemaV29`. The
  scientific name the user selected when overriding the AI's primary
  identification via `CandidatesCard`. `nil` when the user confirmed the AI or
  hasn't reviewed. Synced to `public.scans.user_identification_override` via
  `InferenceEngine.syncIdentificationReviewToCloud`. A lightweight migration
  (`migrateV28toV29`) handles the version bump.)
- `userConfirmedIdentification`: Bool (Added in `MerianSchemaV29`, defaults to
  `false`. Set to `true` when the user taps "Yes, correct" in `CandidatesCard`.
  Cloud-synced via `InferenceEngine.syncIdentificationReviewToCloud` (same PATCH
  payload as `userIdentificationOverride`). Backfilled from
  `public.scans.user_confirmed_identification` by `ScanRepository.ingestScans`
  and `updateExistingScans`. `updateExistingScans` propagates this field in the
  `true` direction only — a cloud `false` (written by
  `resetIdentificationReview` on another device) does not overwrite a local
  `true`. Full bidirectional review-state sync across devices is deferred. Used
  to trigger the `ConfidenceBadge` "Confirmed" state and to render
  `ConfirmedView` in `CandidatesCard`.)
- `userReviewStateRaw`: String (Added in `MerianSchemaV36`, defaults to
  `"unreviewed"`. Replaces the boolean/string combinator logic and maps cleanly
  to the `UserReviewState` Swift enum and the `public.user_review_state`
  Postgres enum. Cloud-synced via
  `InferenceEngine.syncIdentificationReviewToCloud`.)
- `observationContextsJSON`: [String]? (Added in `MerianSchemaV39`. Raw JSON
  array of structured `ObservationContext` values staged by the user before
  submission. Replaced the singular `observationContextJSON` field from V38 as
  part of the mixed-media migration. Mirrors the structured description entries
  that are serialized into `capturedMediaJSON` in V40.)
- `isFlagged`: Bool (Added in `MerianSchemaV31`, defaults to `false`. Legacy
  local moderation flag retained for schema compatibility. It no longer drives
  the Insight confidence badge, candidate review visibility, or an in-app
  identification-flag flow.)
- `imageQualityScore`: Int? (Added in `MerianSchemaV30`. Gemini's 0–100 overall
  image quality rating for the captured photo, persisted from
  `image_quality.overall_score` in the `/identify` response. Immutable after
  init (`let` in `SpeciesData`) — the score is a property of the image, not
  something that changes. `nil` for scans captured before V30. A lightweight
  migration (`migrateV29toV30`) handles the version bump — no data transform
  required since the field is optional with a nil default. Backfilled from
  `public.scans.image_quality_score` by `ScanRepository.updateExistingScans`
  when the local value is nil and the cloud has a value. Gathered for future
  community reference-photo curation use cases.)
- `lookalikesData`: Data? (Added in `MerianSchemaV27`. JSON-encoded
  `[SimilarSpeciesEntry]` blob persisting the full rich lookalike payload —
  `scientificName`, `commonName`, `referenceImageUrl`, `iucnRedListStatus`, and
  optional relation metadata such as `reason`, `visualTraits`, `confidence`,
  source/review fields, direction marker, and `sortOrder` — through the
  SwiftData layer. Written by `InferenceEngine.fetchAndApplyEnrichment` after
  decoding the `/enrich-scan` response. `InferenceEngine.load(from:)` decodes
  this field first; if nil, it falls back to the flat
  `similarSpecies: [String]?` array. A lightweight migration (`migrateV26toV27`)
  handles the version bump — no data transform is required since the field is
  optional with a nil default on existing records.)
- ~~`diagnosticPrimaryRationale`~~: Removed in `MerianSchemaV26`. Previously
  stored the primary identification rationale for low-confidence scans (added in
  `MerianSchemaV9`).
- ~~`diagnosticDifferentiatorsJson`~~: Removed in `MerianSchemaV26`. Previously
  stored a JSON-encoded `[String]` array of key field marks distinguishing the
  species from its lookalike (added in `MerianSchemaV9`).
- `iucnRedListStatus`: String? (Added in `MerianSchemaV10`. Tracks international
  species risk status, powering the offline `ConservationBanner`.)
- `gpsElevation`: Double? (Added in `MerianSchemaV11`. Syncs capture altitude
  for the offline `InsightLocationWeatherCard`.)
- `gpsLatitude`, `gpsLongitude`: Double? (Added in `MerianSchemaV12`. Stores raw
  GPS coordinates for the `ScanInformationCard` MapKit integration.)
- `zoomFactor`: Double? (Added in `MerianSchemaV13`. Records the active optical
  zoom at the moment of capture. `nil` for 1× scans and any scan captured before
  V13. Displayed in `ScanInformationCard` and forwarded to the Edge function as
  a Gemini telemetry cue.)
- `aiReasoning`: String? (Added in `MerianSchemaV15`. The sole storage for
  per-scan AI vision reasoning as of `MerianSchemaV17` — replaces
  `insightDescription`. Populated from the `insight_data.ai_reasoning` field in
  the `/identify` response, and on cloud sync from `scans.ai_reasoning`. Unique
  to each photo submitted — never shared across scans of the same species.)
- `extractedVisualTraits`: [String]? (Not mapped to the SwiftData schema; this
  data point is currently edge-and-cloud-only for diagnostic and hallucination
  telemetry.)
- `habitatDescription`: String? (Added in `MerianSchemaV15`. Populated
  asynchronously by `BackgroundDatabaseActor.updateScanWithEnrichment` after
  `enrich-scan` returns. Loads 2–3 seconds after each biological scan completes
  via `InferenceEngine.fetchAndApplyEnrichment`. Displayed in
  `HabitatAndDistributionCard` inside `BiologicalView`.)
- ~~`globalDistributionRegionsJson`~~: Removed in `MerianSchemaV19`. Was added
  in `MerianSchemaV15` to cache AI-generated region codes, but proved
  inaccurate. Distribution data is now communicated exclusively through the GBIF
  tile overlay driven by `gbifTaxonKey`.
- `gbifTaxonKey`: Int? (Added in `MerianSchemaV18`. The GBIF species usage key
  sourced from `species_dictionary.gbif_taxon_key`, which is populated by
  `fetchExternalEnrichment` during the `identify` background task via a REST
  call to `api.gbif.org/v1/species/match`. Not AI-generated — it is GBIF's own
  deterministic taxonomy ID. Forwarded to the client at the top-level of the
  `/identify` response for **all tiers** on Cache Hit, and via `/enrich-scan`
  for all users on the enrichment path. Used by `GBIFHeatmapMapView` in
  `HabitatAndDistributionCard` to fetch occurrence density tile overlays from
  `api.gbif.org/v2/map/occurrence/density`, visible to free and Pro users alike.
  `nil` for scans of Cache Miss species where the GBIF background lookup has not
  yet completed, or for scans captured before V18.)
- `estimatedSizeCm`: Double? (Added in `MerianSchemaV20`. Physical dimension
  metric computed via LiDAR / AI context. Parsed and persistently cached
  locally.)
- `lifeStage`: String? (Added in `MerianSchemaV20`. Phenological tracking, e.g.
  "adult" or "larva", extracted by Gemini API.)
- `reproductiveCondition`: String? (Added in `MerianSchemaV20`. Phenological
  state, e.g. "flowering" or "fruiting", extracted by Gemini API.)
- `sex`: String? (Added in `MerianSchemaV43`. Darwin Core sex annotation when
  directly supported by scan evidence.)
- `sexConfidence`: Double? (Added in `MerianSchemaV43`. Confidence in the local
  sex annotation.)
- `sexEvidence`: String? (Added in `MerianSchemaV43`. Short evidence phrase for
  the local sex annotation.)
- `individualCount`: Int? (Added in `MerianSchemaV20`. Core population scale
  within the frame.)
- `ecologicalInteractions`: [String]? (Added in `MerianSchemaV20`. Array of
  behavioral interactions observed, such as predation or parasitism.)
- `customTags`: [String] (Added in `MerianSchemaV22`. User-defined textual tags
  enabling personal categorization and precise local library search queries.)
- `captureDate`: Date? — Secondary date field distinct from `timestamp`. Stores
  the EXIF capture date from the original photo asset when available.
- `inferenceTier`: String? — Records the Gemini model tier (`"flash"` or
  `"pro"`) used for this scan. Forwarded from the `/identify` response. Used by
  `InferenceEngine` to apply the correct confidence threshold for diagnostics
  display.
- `hasBeenViewed`: Bool — Defaults to `true` on historical cloud-synced records.
  Set to `false` on newly inferred scans so the Scans library can display a
  "New" badge until the user opens the insight sheet.

### `ScanCollection` (User Albums)

A top-level album type associated with `LocalScanRecord` nodes, added in
`MerianSchemaV9`.

- `id`: String (UUID)
- `name`: String
- `createdAt`: Date
- `scans`: [LocalScanRecord]? (Inverse `@Relationship` using IDs rather than
  encoded objects, reducing memory pressure.)
- `isDeleted`: Bool (Added in `MerianSchemaV14`. Soft-delete flag explicitly
  passed to the Edge function for safe cloud erasure instead of destructive
  state-diffs.)

**`pending_storage_deletions` — cleanup index** (`20260405000002`): Added
composite index `idx_pending_storage_deletions_status_user` on
`(status, target_user_id, created_at)`. The table had no index at creation — any
background cleanup sweep filtering by `status = 'pending'` was performing a full
sequential scan.

### `PendingCloudDeletionTask`

Queues offline cloud deletions, added in `MerianSchemaV7`.

- `scanId`: String (UUID of the remote record to delete)
- `timestamp`: Date

### `CapturedMediaEntry`

Added in `MerianSchemaV41`. This is the first-class persisted media model for
both queued and completed scans.

- `id`: String (UUID)
- `orderIndex`: Int (stable position inside the scan's ordered media timeline)
- `kindRaw`: String (`image` | `video` | `audio` | `description`)
- `storageRaw`: String (`documents` | `remoteURL` | `absolutePath`; empty for
  descriptions)
- `mediaPath`: String (serialized image/video/audio path; empty for
  descriptions)
- `observationContextJSON`: String (serialized `ObservationContext`; empty for
  images/video/audio)
- `localScanRecord`: Local scan relationship (cascade delete)
- `offlineQueuedScan`: Queue relationship (cascade delete)

`CapturedMediaEntry` is intentionally low-level. Higher-level readers should go
through `CapturedMediaSnapshot`, which rebuilds the shared derived views used by
the queue, insight sheet, export, and thumbnail code paths. The snapshot bridge
intentionally reads `capturedMediaJSON` before touching this relationship so
layout and export code do not fault child rows unless the scalar mirror is
unavailable.

- image paths and image references
- video paths, poster references, and extracted-audio references
- audio paths and audio references
- description text and serialized observation contexts
- `CapturedMediaSummary`
- `ActiveScanMedia`
