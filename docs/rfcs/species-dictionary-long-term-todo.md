# Species Dictionary Long-Term TODO

This TODO tracks the work needed to turn the in-app Species Dictionary Page into
a durable public content layer for iOS and the future web frontend.

## Scope 1 — Canonical Species Identity

Status: iOS/Edge implemented; public web slugs still planned.

- [x] Keep `scientific_name` lookup backward compatible.
- [x] Allow `/species-dictionary` requests to use `species_id` as the canonical
      lookup key.
- [x] Teach iOS dictionary routes and `MerianNetworkClient` to prefer
      `species_id` when a similar-species payload provides one.
- [x] Include `species_id` in hydrated similar-species payloads from
      `/enrich-scan`, `/get-explore-post-detail`, and `/species-dictionary` when
      the entry is backed by `species_dictionary`.
- [ ] Add public web/deep-link slugs after the first web routing design lands.

Why it matters: scientific names can change, collide across stale caches, or be
corrected after review. Stable dictionary IDs let the app route by identity
while still displaying canonical names.

## Scope 2 — Normalize Reference Images

Status: iOS/Edge/SQL readers implemented; identify upserts dual-write verified
URLs while preserving the legacy cache.

- [x] Add a `species_reference_images` table with `species_id`, `url`, `source`,
      `license`, `attribution`, `width`, `height`, `sort_order`, `created_at`,
      and `last_verified_at`.
- [x] Backfill rows from comma-separated
      `species_dictionary.reference_image_url`.
- [x] Update `/species-dictionary`, Explore detail, and scan enrichment to read
      from the normalized table.
- [x] Keep the legacy comma-separated field as a compatibility cache until all
      readers are migrated.
- [x] Dual-write identify/external enrichment image URLs into normalized rows
      for new or refreshed species.
- [ ] Add richer license/attribution ingestion once provenance refresh is
      designed.

Why it matters: reference media needs attribution, ordering, health checks, and
licensing before the same data is exposed on the public web.

## Scope 3 — Shared Public Species Projection

Status: Edge shared module and SQL helper projection implemented; future web
should consume the same contract.

- [x] Define one public species projection used by `/species-dictionary`,
      Explore detail similar species, and the future web frontend.
- [x] Centralize common-name fallback, image source mapping, nullable taxonomy
      handling, and privacy filtering.
- [x] Add contract tests proving scan-specific fields never leak into the public
      projection.
- [ ] Reuse the shared projection directly from the first web species endpoint
      when web routing lands.

Why it matters: the same species data should not be reshaped in three subtly
different ways across Edge Functions and SQL RPCs.

## Scope 4 — Provenance And Refresh Metadata

Status: service-role refresh queue, scheduled external refresh worker, automatic
insert/backfill queue coverage, and scheduled model-heavy worker implemented;
manual curation tools still planned.

- [x] Track source and freshness for overview, habitat, taxonomy, GBIF key,
      images, common names, group tags, conservation/hazard fields, and
      lookalikes.
- [x] Store whether a value came from GBIF, Wikipedia, user review, a
      model-generated enrichment pass, manual curation, taxonomy trigger, mixed
      sources, or a legacy backfill.
- [x] Add a service-role refresh queue query for stale or low-confidence species
      content rows.
- [x] Build the scheduled refresh worker that consumes
      `get_species_content_refresh_queue(...)` and selectively refreshes stale
      content.
- [x] Route new and existing sparse dictionary rows into `species_enrichment_jobs`
      with missing `gbif_wikipedia_reference`, `habitat`, `lookalikes`, and
      `group_tags` work.
- [x] Build the scheduled model-heavy refresh worker for habitat prose,
      lookalikes, and group tags.
- [ ] Add curation tools that can write `manual_curation` provenance with no
      automatic refresh deadline.

Current rules:

- `refresh-species-content` runs hourly through `pg_cron`/`pg_net`,
  authenticating with `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}`.
- The worker caps each invocation at 100 rows, with the scheduled run using
  `limit = 25`.
- Species refreshes run with a concurrency cap of 4 to stay within Edge runtime
  bounds without overwhelming GBIF/Wikipedia.
- V1 refreshes only externally authoritative fields: alternate common names,
  taxonomy, Wikipedia URL/overview, GBIF taxon key, and reference images.
- `refresh-species-model-content` runs through the same service-role cron
  pattern with `limit = 12` and claims `habitat`, `lookalikes`, and
  `group_tags` jobs.
- New species dictionary inserts enqueue only missing enrichment groups with
  `source_trigger = 'species_dictionary_insert'`; the sparse-row backfill uses
  `source_trigger = 'species_dictionary_sparse_backfill'`.
- Common-name overrides, IUCN status, and hazard type stay curation-owned.
- `public.replace_species_reference_images(...)` keeps normalized reference
  imagery aligned with refreshed URLs while preserving existing
  license/attribution metadata.

Why it matters: cached species content will age. Provenance lets Merian refresh
data deliberately instead of overwriting fields blindly.

## Scope 5 — Stronger Lookalike Modeling

Status: SQL/Edge/iOS additive metadata implemented; curation workflow still
planned.

- [x] Extend `species_lookalikes` with relation metadata: `reason`,
      `visual_traits`, `confidence`, `source`, `review_status`,
      `is_bidirectional`, and `sort_order`.
- [x] Support explaining why two species are visually similar through optional
      public `reason` and `visual_traits` fields.
- [x] Keep relation direction explicit; do not assume every lookalike
      relationship is symmetric.
- [ ] Build review/curation tooling for approving, rejecting, reordering, and
      manually editing lookalike relationships.

Why it matters: a dictionary page should eventually explain the confusion, not
only list names and photos.

## Scope 6 — Public API Versioning

Status: implemented for current public species surfaces.

- [x] Add response `schema_version` to `/species-dictionary` and Explore post
      detail's public species payload wrapper before the web frontend depends on
      the contract.
- [x] Document compatibility expectations for nullable fields and additive
      response keys.
- [ ] Introduce a versioned endpoint path only if a future breaking response
      change cannot be handled additively.

Why it matters: iOS and web clients will update on different schedules.

## Scope 7 — Caching Strategy

Status: implemented for the public Edge response and the iOS in-memory route
cache.

- [x] Add safe HTTP cache headers for public dictionary responses.
- [x] Add iOS client memoization for recently opened species pages.
- [x] Track cache invalidation rules for refreshed species rows.

Current rules:

- `/species-dictionary` `200 OK` responses send
  `Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800`
  and `Vary: Accept-Encoding`; error responses remain uncached.
- iOS keeps a 10-minute, 64-key in-memory memo cache in `MerianNetworkClient`,
  keyed by canonical dictionary ID when available and normalized scientific name
  as a fallback.
- Refreshed species rows become visible after the shorter of the iOS memo TTL
  and any downstream HTTP/browser cache freshness window. Manual curation or
  scheduled refreshes that need immediate global visibility should pair the data
  write with CDN/cache purge tooling once the public web frontend exists.

Why it matters: species dictionary data is public and slow-changing, so it
should be cheap to reopen and cheap to serve.

## Scope 8 — Content Quality States

Status: implemented for the species dictionary API and iOS page.

- [x] Classify species rows as `complete`, `sparse`, or `needs_enrichment`.
- [x] Render sparse pages intentionally instead of making missing sections feel
      broken.
- [x] Track not-found and sparse-load rates.

Current rules:

- `/species-dictionary` returns additive `content_quality`, derived from public
  reference images, a usable Wikipedia overview, habitat/distribution data, and
  meaningful taxonomy.
- `complete` means all four public content signals are present; `sparse` means
  at least two are present; `needs_enrichment` means the row has fewer than two
  usable public content signals.
- iOS treats `content_quality` as optional and estimates the same state for
  older payloads that do not include the field.
- Sparse and needs-enrichment pages render a small status card instead of
  silently omitting most sections.
- TelemetryDeck events from Scope 10 track sparse-load and not-found rates with
  zero-PII entry-point metadata.

Why it matters: users will tap into incomplete species rows, especially early in
the dictionary rollout.

## Scope 9 — Web-Safe Licensing

Status: implemented for normalized media metadata, iOS display, and future web
audit hooks.

- [x] Store image licenses and attribution beside each reference image.
- [x] Render attribution in iOS where appropriate and require it on web.
- [x] Add tests or audits that prevent unattributed public web media.

Current rules:

- `species_reference_images.license` and `species_reference_images.attribution`
  are the canonical public media rights fields.
- `/species-dictionary` includes `license` and `attribution` on each normalized
  `reference_images` item when stored metadata exists.
- iOS shows the active reference image's attribution/license below the gallery
  when either field is present.
- Future web species pages must run
  `publicWebReferenceImageAttributionIssues(...)` from
  `_shared/publicSpeciesProjection.ts` before rendering public reference media,
  and must not publish an image unless license and attribution are present or a
  source-specific renderer supplies an equivalent attribution.

Why it matters: Wikimedia and GBIF-backed imagery can have attribution
obligations that become more important on a public website.

## Scope 10 — Analytics

Status: implemented for current iOS entry points; future search, web, and deep
links have reserved entry-point values.

- [x] Track dictionary opens by entry point: Insight, Explore detail, future
      search, web, and deep links.
- [x] Track not-found, sparse-content, image-fallback, and retry rates.
- [x] Use those metrics to prioritize enrichment backfills and reference-image
      cleanup.

Current rules:

- `SpeciesDictionaryRoute` carries a zero-PII `entryPoint` enum. Current iOS
  values are `insight_similar_species` and `explore_detail_similar_species`;
  reserved values are `search`, `deep_link`, `web`, and `unknown`.
- `SpeciesDictionaryOpened` tracks sheet opens once per route/view-model
  lifecycle.
- `SpeciesDictionaryLoaded` tracks successful loads with `entryPoint` and
  `contentQuality`, which covers sparse-load rates.
- `SpeciesDictionaryNotFound` tracks missing public rows with `entryPoint`.
- `SpeciesDictionaryRetry` tracks explicit retry taps from error/not-found
  states.
- `SpeciesDictionaryImageFallback` tracks dictionary reference-image load
  failures with `entryPoint` and image `source`.
- No event attaches species name, species ID, scan ID, Explore post ID, user
  location, field notes, comments, image URL, or user review state.
- Prioritization query pattern: group `SpeciesDictionaryLoaded` by
  `contentQuality` and `entryPoint` to find sparse surfaces, group
  `SpeciesDictionaryImageFallback` by `source` to clean reference imagery, and
  group `SpeciesDictionaryNotFound`/`Retry` by `entryPoint` to find missing
  dictionary coverage in launch flows.

Why it matters: the dictionary should improve where users actually encounter
gaps.

## Scope 11 — Merian-Sourced Reference Images

Status: implemented for published Explore media; future moderation/review tools
can refine promotion policy.

- [x] Add `merian` as a normalized `species_reference_images.source`.
- [x] Promote currently visible Explore post media with
      `image_quality_score >= 80`.
- [x] Gate AI-resolved media with `ai_confidence_score >= 0.95`, while allowing
      `confirmed_species_id` to qualify as the authoritative species signal.
- [x] Use all non-empty image URLs from qualifying scans, cap at 8 promoted
      Merian images per species, and order Merian images before Wikipedia/GBIF.
- [x] Store private source scan/post/user provenance in
      `species_reference_image_merian_sources` without exposing it through
      public species APIs.
- [x] Mirror source visibility: unshared posts, private backing-scan geoprivacy,
      cleared media, tombstoned scans, and shadowbanned authors remove public
      Merian rows on the next refresh.
- [ ] Add manual review/curation tooling for exceptional promotion, demotion,
      and representative-photo diversity after automated V1 has production data.

Current rules:

- `/refresh-merian-reference-images` runs hourly through `pg_cron`/`pg_net`,
  authenticating with `Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}`.
- The scheduled run uses
  `{ "quality_threshold": 80, "species_confidence_threshold": 0.95, "per_species_limit": 8 }`.
- Public rows use `source = "merian"`,
  `license = "Used with permission via Merian"`, and the author's public Explore
  label as `attribution`.
- External `/refresh-species-content` image refreshes preserve Merian rows and
  cannot delete or demote them.

Why it matters: Merian's own high-quality published observations should become
the strongest visual layer in the dictionary while preserving contributor
visibility controls.
