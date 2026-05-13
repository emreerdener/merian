# Species Dictionary Long-Term TODO

This TODO tracks the work needed to turn the in-app Species Dictionary Page into a durable public content layer for iOS and the future web frontend.

## Scope 1 — Canonical Species Identity

Status: iOS/Edge implemented; public web slugs still planned.

- [x] Keep `scientific_name` lookup backward compatible.
- [x] Allow `/species-dictionary` requests to use `species_id` as the canonical lookup key.
- [x] Teach iOS dictionary routes and `MerianNetworkClient` to prefer `species_id` when a similar-species payload provides one.
- [x] Include `species_id` in hydrated similar-species payloads from `/enrich-scan`, `/get-explore-post-detail`, and `/species-dictionary` when the entry is backed by `species_dictionary`.
- [ ] Add public web/deep-link slugs after the first web routing design lands.

Why it matters: scientific names can change, collide across stale caches, or be corrected after review. Stable dictionary IDs let the app route by identity while still displaying canonical names.

## Scope 2 — Normalize Reference Images

Status: planned.

- [ ] Add a `species_reference_images` table with `species_id`, `url`, `source`, `license`, `attribution`, `width`, `height`, `sort_order`, `created_at`, and `last_verified_at`.
- [ ] Backfill rows from comma-separated `species_dictionary.reference_image_url`.
- [ ] Update `/species-dictionary`, Explore detail, and scan enrichment to read from the normalized table.
- [ ] Keep the legacy comma-separated field as a compatibility cache until all readers are migrated.

Why it matters: reference media needs attribution, ordering, health checks, and licensing before the same data is exposed on the public web.

## Scope 3 — Shared Public Species Projection

Status: planned.

- [ ] Define one public species projection used by `/species-dictionary`, Explore detail similar species, and the future web frontend.
- [ ] Centralize common-name fallback, image source mapping, nullable taxonomy handling, and privacy filtering.
- [ ] Add contract tests proving scan-specific fields never leak into the public projection.

Why it matters: the same species data should not be reshaped in three subtly different ways across Edge Functions and SQL RPCs.

## Scope 4 — Provenance And Refresh Metadata

Status: planned.

- [ ] Track source and freshness for overview, habitat, taxonomy, GBIF key, images, common names, and lookalikes.
- [ ] Store whether a value came from GBIF, Wikipedia, user review, a model-generated enrichment pass, or manual curation.
- [ ] Add refresh workflows for stale or low-confidence species rows.

Why it matters: cached species content will age. Provenance lets Merian refresh data deliberately instead of overwriting fields blindly.

## Scope 5 — Stronger Lookalike Modeling

Status: planned.

- [ ] Extend `species_lookalikes` with relation metadata such as `reason`, `visual_traits`, `confidence`, `source`, `review_status`, `is_bidirectional`, and `sort_order`.
- [ ] Support explaining why two species are visually similar.
- [ ] Keep relation direction explicit; do not assume every lookalike relationship is symmetric.

Why it matters: a dictionary page should eventually explain the confusion, not only list names and photos.

## Scope 6 — Public API Versioning

Status: planned.

- [ ] Add a response `schema_version` or versioned endpoint before the web frontend depends on the contract.
- [ ] Document compatibility expectations for nullable fields and additive response keys.

Why it matters: iOS and web clients will update on different schedules.

## Scope 7 — Caching Strategy

Status: planned.

- [ ] Add safe HTTP cache headers for public dictionary responses.
- [ ] Add iOS client memoization for recently opened species pages.
- [ ] Track cache invalidation rules for refreshed species rows.

Why it matters: species dictionary data is public and slow-changing, so it should be cheap to reopen and cheap to serve.

## Scope 8 — Content Quality States

Status: planned.

- [ ] Classify species rows as `complete`, `sparse`, or `needs_enrichment`.
- [ ] Render sparse pages intentionally instead of making missing sections feel broken.
- [ ] Track not-found and sparse-load rates.

Why it matters: users will tap into incomplete species rows, especially early in the dictionary rollout.

## Scope 9 — Web-Safe Licensing

Status: planned.

- [ ] Store image licenses and attribution beside each reference image.
- [ ] Render attribution in iOS where appropriate and require it on web.
- [ ] Add tests or audits that prevent unattributed public web media.

Why it matters: Wikimedia and GBIF-backed imagery can have attribution obligations that become more important on a public website.

## Scope 10 — Analytics

Status: planned.

- [ ] Track dictionary opens by entry point: Insight, Explore detail, future search, web, and deep links.
- [ ] Track not-found, sparse-content, image-fallback, and retry rates.
- [ ] Use those metrics to prioritize enrichment backfills and reference-image cleanup.

Why it matters: the dictionary should improve where users actually encounter gaps.
