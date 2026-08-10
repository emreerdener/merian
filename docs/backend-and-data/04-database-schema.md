# Database Schema & Data Models

This document maps the expected shape of our persistence layers. AI Agents
should refer to this to bind TypeScript interfaces and Swift `Codable` structs
without guessing.

## Migration Execution and Exposed-Schema Contract

CI pins Supabase CLI `2.109.1`, which owns migration transaction and history
boundaries. New migrations at or after `20260727183356` must not contain
top-level `BEGIN`, `START TRANSACTION`, `COMMIT`, `END`, `ROLLBACK`, or `ABORT`;
an embedded boundary can split schema state from history. Top-level
`lock_timeout` and `statement_timeout` guards use session `SET` plus matching
`RESET`, not `SET LOCAL`, so they work during both normal apply and fresh
replay. Historical applied files with explicit controls remain immutable
compatibility artifacts and are not examples for future migrations.

No checked-in migration may execute concurrent index DDL. A large production
index is built through the deployment runbook's separately supervised owner
session and then recognized by the unchanged migration. Every table created in
the Data API's exposed `public` schema must have effective RLS enabled. Default
table and sequence ACLs for the `postgres` migration role are revoked globally
and in `public`; API access is explicitly granted and reviewed. See
[`13-server-credentials-and-database-release-safety.md`](./13-server-credentials-and-database-release-safety.md)
for the complete release contract.

## Supabase PostgreSQL Schema (`00001_initial_schema.sql`)

### Privileged routine ACL catalog

`internal.privileged_routine_grants` is the reviewed source of truth for API
role execution on public-schema `SECURITY DEFINER` functions. Its primary key is
`(role_name, routine_signature)`; `role_name` is limited to `authenticated` or
`service_role`, the signature must be a fully qualified public function
identity, and `purpose` records the approved caller. `PUBLIC`, `anon`,
`authenticated`, and `service_role` cannot read or mutate the table directly.

Migration `20260723144640_harden_privileged_routine_execution.sql` revokes all
historical API execution from public definer functions before resolving and
granting each catalog entry. It aborts if an entry is missing, resolves outside
`public`, is not `SECURITY DEFINER`, lacks its grant, or if any unlisted API
grant remains. It also enforces:

- no `PUBLIC` or `anon` execution;
- an empty fixed `search_path` for every public definer;
- caller-bound authorization in authenticated RPCs;
- `internal.require_service_role()` in every service-exposed RPC;
- no API-role `CREATE` privilege on `public`; and
- owner-only function defaults for the `postgres` migration role, globally and
  in `public`.

Migration `20260727010340_fix_service_role_authorization_guard.sql` updates the
defense-in-depth `internal.require_service_role()` body without changing that
allowlist. The helper recognizes a legacy service-role JWT through
`auth.role()`, PostgREST impersonation for an opaque secret key through the
protected standard `role` setting (`current_setting('role', true)`), or a
`postgres`/`service_role` session used for migration or incident repair. These
are server-side database signals: the helper does not read request headers,
compare API keys, or trust a caller-defined GUC. API roles cannot execute the
helper directly, and `authenticated` still has no grant on service-only public
routines.

Migration `20260727013416_future_proof_server_key_boundaries.sql` adds the
private `internal.server_api_request_headers(text)` policy for database `pg_net`
dispatch. It rewrites installed HTTP routines and persisted cron commands so
opaque `sb_secret_...` keys use `apikey` only and legacy service-role JWTs use
both supported headers. API roles cannot execute the helper. The same migration
makes `get_owned_explore_media_incidents(self_id)` choose its service branch
from server-side identity state, allowing both server-key formats while
retaining the exact `auth.uid() = self_id` check for ordinary callers. Migration
`20260727183356_restore_identity_first_media_incident_guard.sql` restores that
final identity-first body after a later migration accidentally reintroduced
role-first dispatch. Future migration coverage rejects the JWT-only pattern.

The schema name `public` means PostgREST may discover a function; it does not
mean a client can execute it. Trigger functions and internal helpers stay
unlisted. New privileged RPCs require an exact catalog entry, fully qualified
objects/types/operators, a caller check, a migration-contract update, and the
catalog pgTAP test. A public definer owned by any role other than `postgres`
fails the hosted audit because that role's future default privileges are a
separate security boundary.

### Species-count projection ledger

Migration `20260724222838_optimize_species_count_trigger.sql` replaces the
historical per-row `COUNT(DISTINCT species_id)` trigger with
`internal.user_species_scan_counts`:

- primary key `(user_id, species_id)`;
- positive `scan_count BIGINT`, representing every scan currently assigned to
  the pair;
- a cascading user foreign key and a deferred `NO ACTION` dictionary foreign
  key, allowing the scan's `ON DELETE SET NULL` transition to own the ledger
  decrement before referential integrity is checked;
- a reverse `(species_id, user_id)` index for the species foreign key; and
- RLS plus explicit denial of all direct API-role access.

Separate `AFTER INSERT`, `DELETE`, and `UPDATE` statement triggers consume
transition tables, aggregate the net delta for each pair, and call one private
empty-search-path definer helper. The update trigger compares complete OLD and
NEW statement sets because PostgreSQL does not permit `UPDATE OF` together with
transition relations. An unrelated update therefore builds no net delta and does
not touch the ledger or public total. Owner changes lock every affected
`public.users` row in UUID order before applying deltas, so concurrent writes
cannot lose a distinct-species boundary and multi-owner helper calls follow one
deterministic lock order. A negative delta that exceeds a still-live owner's
ledger state aborts with `user_species_scan_count_underflow` instead of hiding
corruption. A truncate trigger clears the ledger and projections.

This immutable historical migration opens an explicit transaction, takes a
`SHARE ROW EXCLUSIVE` lock on `public.scans`, backfills the ledger once, repairs
historical `users.total_species_discovered` drift, atomically swaps the
triggers, and commits only after the final trigger exists. PostgreSQL rejects
`LOCK TABLE` outside a transaction block; the explicit boundary is therefore
part of the historical file's compatibility contract, not syntax to copy into a
new migration. Ownerless tombstones are excluded because their user ID is null;
the historical all-zero owner guard remains as migration compatibility. The
ledger intentionally follows raw non-null `scans.species_id`; it does not change
public Explore's separate biological/confirmed-species counting contract.

The dictionary foreign key lives in the `internal` namespace. Any diagnostic or
test that forces its deferred check must use
`SET CONSTRAINTS internal.user_species_scan_counts_species_id_fkey IMMEDIATE`;
an unqualified name is not visible when `internal` is absent from `search_path`.

### Ghost-profile merge reference policy

Migration `20260801210102_make_ghost_merge_schema_aware.sql` adds the private
`internal.ghost_profile_merge_reference_policies` manifest. Each current
single-column foreign key to `public.users` or each non-Auth-internal foreign key
to `auth.users` is assigned reviewed merge semantics: direct `reparent`,
`handler_then_reparent`, source-owned `derived`, immutable `preserve`, the sole
source-profile `delete_source`, or fail-closed `blocked`. The manifest is not an
API or a dynamic handler registry: RLS is enabled, all API-role table access is
revoked, and `handler_key` is documentation checked against a fixed allowlist.

Runtime catalog discovery now verifies and resolves reviewed objects; it never
decides that an arbitrary foreign key represents transferable ownership. A
missing or stale policy, an unsupported composite reference, a blocked policy,
or any source row attached to immutable administrative/audit/moderator
attribution aborts before the first merge helper mutates data. A migration that
adds, removes, or retargets an eligible user foreign key must update this
manifest in the same forward change.

`public.scans.user_id` has execution order 100 and moves before ordinary owned
rows. Its statement trigger is the sole owner of corresponding OLD/NEW deltas in
`internal.user_species_scan_counts`; that derived relation is never reparented
directly. Before source deletion, a bounded invariant compares exact per-species
scan aggregates with ledger rows for both users.

The migration is not production-ready merely because policy coverage passes.
The completed handler contract must also provide these table-level guarantees:

- `internal.revenuecat_reconciliation_queue` always has a destination row after
  a merge, even when the anonymous source had no row. The destination lookup is
  its permanent uppercase UUID from
  `internal.canonical_revenuecat_app_user_id(...)`, `next_reconcile_at` is no
  later than the transaction time, and attempt, lease, and error fields are
  reset. Provider recovery therefore does not depend on a source queue row or
  on receiving a webhook.
- RevenueCat reconciliation locks `public.users` before its queue row, matching
  the merge's parent-before-child order. The queue lease is checked again under
  lock before any entitlement or watermark write.
- `internal.community_identification_activity_actors` collisions are combined
  with update/delete only. Non-colliding source rows are left for the manifest's
  reparent operation; the handler does not insert a target actor after locking
  actors and thereby invert the activity-group-before-actor order used by normal
  writers.

These are release-blocking requirements for the pending schema-aware change,
not guarantees supplied by the current migration draft. They must be added in a
new forward migration and proven through the
[deployment runbook](./06-supabase-deployment-runbook.md#ghost-account-merge-security-rollout)
before production deployment.

### Versioned Terms and third-party AI consent

Migrations `20260804020351_record_legal_consent_receipts.sql` and
`20260804033307_add_adult_and_analytics_consent.sql` add four exposed but
owner-scoped append-only tables. Forward migration
`20260806024844_enforce_causal_consent_streams.sql` replaces receipt-time
authority for the two mutable provider streams with an atomic causal protocol.
Forward migration
`20260806144105_authorize_consent_from_provider_stream_heads.sql` makes the
provider-wide greatest revision the mandatory first authorization decision:

- `public.user_adult_eligibility_receipts`: UUID primary key, `user_id`, adult
  policy version, device confirmation time, `self_attestation` method, exact
  displayed statement, platform, app version/build, and server-controlled
  `recorded_at`; no birth date or exact age;
- `public.user_terms_acceptance_receipts`: UUID primary key, `user_id`,
  `terms_version`, device `accepted_at`, exact `acceptance_text`, platform,
  app version/build, and server-controlled `recorded_at`;
- `public.user_ai_consent_events`: UUID primary key, `user_id`, constrained
  provider, `disclosure_version`, `event_kind` (`granted` or `revoked`), device
  `occurred_at`, exact disclosure/action text, platform, app version/build, and
  server-controlled `recorded_at`, server-only monotonic `consent_revision`,
  and the accepted event's `causal_parent_id`;
- `public.user_analytics_consent_events`: UUID primary key, `user_id`, PostHog
  disclosure version, `granted` / `revoked` event kind, device action time,
  exact disclosure/action text, platform, app version/build, and
  server-controlled `recorded_at`, server-only monotonic `consent_revision`,
  and the accepted event's `causal_parent_id`.

Authenticated users may select only their own rows under RLS. Adult and Terms
receipts retain narrow column-level insert ACLs. AI and analytics event tables
deny direct client insertion and sequence access; callers use
`append_user_ai_consent_event(...)` or
`append_user_analytics_consent_event(...)`. Each `SECURITY DEFINER` routine
authenticates with `auth.uid()`, locks the caller's `public.users` row
`FOR KEY SHARE` to serialize against ghost-profile merge, then takes a
transaction-scoped advisory lock for the caller/provider stream. Under that
lock, a grant whose supplied parent is not current returns `accepted = false`
with the authoritative head. A revocation always appends and stores that current
head as its accepted parent, so a stale device cannot preserve a grant. Every
accepted response returns the stored parent and the only authoritative server
revision. No table grants client insert, update, delete, or sequence access.
Reusing an event ID with different immutable content raises
`consent_event_id_conflict`. An exact revocation retry may repeat its originally
observed parent after server rebasing; the existing stored parent is returned.
Exact `(user_id, provider, consent_revision DESC)` stream-head indexes and
partial causal-parent indexes support authorization lookup and the self-foreign
keys. All four user foreign keys
are registered as conflict-free `reparent`
entries in the ghost-profile merge manifest so all evidence follows the
canonical signed-in account without deleting or combining rows.
`user_analytics_consent_events` is also added to the Supabase Realtime
publication so owner-scoped account changes can disable or enable capture on
other active devices. The iOS subscriber separately tracks requested and
confirmed channel ownership, generation-fences stale callbacks, retries bounded
failures for the same account, and repairs the subscription on foreground or
session adoption.

Database merge policies can reparent only rows already synchronized to
Supabase. After a confirmed server handoff, iOS now transforms the complete
local ledger in one verified write: ghost-synchronized evidence becomes
permanent-account synchronized evidence, while every other ghost-owned record
becomes pending for that permanent account. It preserves record IDs, exact
text, versions, client/server timestamps, platform, and app metadata, then
pushes and refetches. The final client merge independently rechecks
cancellation, observed user, the synchronous Supabase SDK session, and
synchronization generation before mutating or persisting evidence or applying
analytics; durable queue removal follows successful reconciliation. All tracked
client findings are closed in source. Production remains held until the same
candidate SHA passes **iOS Build and Test** and validation-only **Supabase
Candidate Validation**, including a fresh required-version catalog replay; see
the
[production consent readiness record](../legal/production-consent-readiness-2026-08-03.md).

`internal.require_current_ai_consent(uuid)` first selects the all-version
`google_gemini` provider head by `consent_revision DESC`. A missing head or a
head revocation under any disclosure version denies immediately, before rollout
configuration is read. Only a head grant proceeds to the rollout
matrix: the current bundle requires adult policy
`2026-08-03`, Terms `2026-08-03`, and Gemini disclosure `2026-08-04.1`; older
complete grants remain bounded by `enforcement_mode`. Unknown future versions
fail closed. Device time and `recorded_at` remain evidence, not authorization
clocks. Both
service-only `reserve_ai_quota` overloads call the helper before provider
admission and before entitlement or provider-counter reservation. Consequently,
`ai_consent_required` creates no quota reservation, included-Pro hold, or daily
Flash consumption and is not evidence that a new account has no scans left.
Clients must upload and freshly read the active account's evidence before its
first Identify request; locally persisted synchronization markers are not a
database proof. A policy copy or material-purpose change must update the Swift
policy and this database gate together and require a new user action. See the
[first-scan consent-policy incident](../incidents/2026-08-first-scan-consent-policy-retry-loop.md)
for the client failure mode and release closure gates.

### `users`

Tracks the global state of the anonymous/authenticated user.

- `id` (UUID): Maps to the `auth.users` GoTrue unique identifier, automatically
  generated via standard Supabase Ghost Sessions with IDFV fallback. This UUID
  is the PostHog distinct ID and, in uppercase RFC 4122 form, the case-sensitive
  RevenueCat App User ID; RevenueCat subscriber attributes also mirror auth
  email and public identity fields for support lookups.
- `subscription_tier` (ENUM): `'free'` | `'pro'`. This is the durable
  projection of authoritative RevenueCat-backed Pro state, not
  beta-membership data or an operator-controlled entitlement switch.
  Webhook/reconciliation is expected to overwrite a direct manual edit. Three
  introductory Pro scans are represented by the separate private entitlement
  ledger.
- `subscription_expires_at` (TIMESTAMPTZ, nullable): For recurring RevenueCat
  access, the later of entitlement expiration and grace-period expiration. It is
  also set for timed grants such as the detached `pro_week` non-renewing
  purchase. `NULL` is reserved for an explicitly non-expiring lifetime
  entitlement. The hourly `expire-subscription-passes` worker downgrades any
  expired timed access and clears this value, even when the final provider
  webhook never arrives.
- `entitlement_version` (BIGINT, default 1): Monotonic durable version advanced
  by `bump_user_entitlement_version` whenever `subscription_tier` or
  `subscription_expires_at` changes. Callers cannot increment it independently.
  AI reservations record the version they authorized so incident review can
  correlate a provider attempt with the exact entitlement generation.
- `default_geoprivacy` (ENUM): `'open'` | `'obscured'` | `'private'`. Dictates
  the privacy projection applied to scans. Current clients send this value on
  identify requests, and Edge insert helpers fall back to this column when the
  request omits or sends an invalid value. Updating this preference triggers a
  scan reprojection for that user: `private` clears public coordinates and
  public location labels, `obscured` rounds public coordinates with a 10 km
  uncertainty floor, and `open` restores exact public coordinates when exact GPS
  exists and species-safety rules allow it.
- `current_streak_count` (Int): Gamification metric.
- `total_species_discovered` (Int): Server-owned projection of the number of
  rows in `internal.user_species_scan_counts` for the user. Statement-level scan
  triggers increment or decrement it only when a non-null
  `(user_id, species_id)` ledger row is created or removed. Bulk writes are
  aggregated, owner transfers update both OLD and NEW owners, and unrelated scan
  updates leave it untouched. DO NOT MANUALLY UPDATE THIS FROM CLIENT CODE OR
  EDGE FUNCTIONS.
- `abuse_strikes` (INT, DEFAULT 0): Incremented by the shared identify
  moderation pipeline each time Gemini's safety ratings flag submitted media as
  `MEDIUM` or `HIGH` probability, or when `finishReason === "SAFETY"`. The
  active multimodal route awaits this pass; compatibility scan insertion may
  still run after its response. Never decremented automatically. See
  [Safety & Moderation](../development-guides/10-safety-and-moderation.md).
- `is_shadowbanned` (BOOLEAN, DEFAULT false): Set to `true` when `abuse_strikes`
  reaches 3. Public Explore, Community Identification, notification, and related
  projections exclude shadowbanned authors. The moderation helper does not use
  the flag as a blanket veto for every later safe private scan insert; the
  unsafe request itself is rejected, while later owner rows may persist without
  becoming publicly visible. Not currently read by the iOS client.
- `public_author_name` (TEXT, NOT NULL): Explore-facing public display label
  derived from auth metadata (`First L.`) when safe, otherwise from a stable
  alias fallback. For alias-source identities this now matches
  `public_username`, so default/ghost Explore authors render as handles such as
  `@juniper_trail_27` while logged-in display-name authors can still render
  labels such as `Emre E.`. Added in migration
  `20260425000000_add_explore_posts.sql`.
- `public_username` (TEXT, NOT NULL): Canonical public handle stored without
  `@`, unique across users, and used for profile handles and comment mentions.
  Validation requires lowercase ASCII letters, numbers, and
  underscores; 3 to 24 characters; a leading letter; a trailing letter or
  number; no repeated underscores; and no protected brand namespace,
  official/system role, or exact brand-role combination in either order. The
  policy is exact rather than prefix-based and carries no authorization
  semantics. Added in migration `20260526090000_add_public_usernames.sql` and
  expanded in `20260808144244_expand_reserved_public_username_policy.sql`.
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

Authenticated Data API clients may update only `default_geoprivacy` and
`marketing_opt_in`. They have no table/column privilege to insert or delete user
rows, or update tier, timed expiry, entitlement version, identity, moderation,
or gamification fields. Identity and billing mutations use reviewed
service-owned boundaries.

Auth signup normally derives the three required public-identity columns through
`handle_new_user()`. Owner-only repair scripts and transactional database tests
that insert `public.users` directly bypass that trigger and must first insert a
matching transactional `auth.users` fixture, then supply a valid unique
`public_username`, a non-empty `public_author_name`, and a CHECK-valid
`public_identity_source`. These columns have no direct-insert fallback defaults;
do not weaken their Auth foreign key, `NOT NULL`, validation, or uniqueness
constraints for fixture convenience.

Migration `20260728232000_ensure_scan_user_profile.sql` adds service-only
`public.ensure_scan_user_profile(user_id)` as the scan-ingestion prerequisite
for a real Auth identity whose public profile is absent. It takes the canonical
ghost-merge advisory lock, requires and key-share-locks the exact `auth.users`
row, refuses active account deletion, merged-source retirement, and claimed
ghost cleanup, and derives every mandatory identity/avatar field through the
same canonical helpers as signup. An existing profile is an idempotent no-op;
the only retry is a bounded proven `public_username` uniqueness race.

This routine replaces the obsolete partial direct upsert of only the `id` and
`subscription_tier` columns, which cannot satisfy the current mandatory public
identity schema. It is an empty-search-path `SECURITY DEFINER` with its own
`internal.require_service_role()` check. Execution is revoked from `PUBLIC`,
`anon`, and `authenticated`, explicitly granted only to `service_role`, and
registered by exact signature in `internal.privileged_routine_grants`.

Migration `20260725041308_ownerless_account_deletion_tombstones.sql` normalizes
the profile primary key as a validated `ON DELETE RESTRICT` foreign key to
`auth.users(id)`. Every public profile therefore represents a real Auth
identity, and Auth deletion cannot precede relational cleanup. Deletion
infrastructure must never manufacture an all-zero or other synthetic profile;
retained observations use ownerless tombstones instead.

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
profile surfaces and comment mentions.

`refresh_public_author_identity(uuid)` is an idempotent backend maintenance
function: once name, source, and avatar are converged, it performs no `UPDATE`.
`repair_explore_post_ownership_for_user(uuid)` aligns denormalized
`explore_posts.user_id` only for posts backed by scans owned by the target user.
Both are `SECURITY DEFINER` with an empty search path, fully schema-qualified,
and executable only by `service_role`; `PUBLIC`, `anon`, and `authenticated`
have no execute privilege. Auth triggers continue to execute the refresh as the
function owner. Edge read endpoints never call either function; write and
ghost-merge paths own maintenance.

### `beta_waitlist_signups` and `internal.beta_waitlist_rate_counters`

Migration `20260724192124_harden_json_endpoints_and_waitlist.sql` turns the
public web waitlist into a bounded service-owned write path.

`public.beta_waitlist_signups` stores only the canonical lowercase email,
bounded source, bounded sanitized user agent, and its existing timestamps. New
rows must satisfy:

- email length 3–254 characters of ASCII-shaped canonical input, local part at
  most 64 characters, domain labels at most 63 characters, and no whitespace,
  controls, consecutive dots, or leading/trailing label hyphens;
- `source = 'web_waitlist'` at the RPC boundary and database source length 1–64;
  and
- optional user-agent length 1–512 with no control characters.

The three check constraints are initially `NOT VALID` so unknown historical junk
cannot block the production migration; PostgreSQL still enforces them on every
new or updated row. Operators must audit historical rows and validate the
constraints after cleanup. Do not weaken the new-row boundary to accommodate
legacy data.

`internal.beta_waitlist_rate_counters` stores transactional pre-challenge and
verified 10-minute/daily IP counters plus the daily global growth counter. Its
IP key is a purpose-separated, daily-rotating HMAC; raw IP addresses, CAPTCHA
tokens, and submitted email values never enter this table. RLS is enabled and
all direct access is revoked from API roles and `service_role`. Request-path
retention work uses the `updated_at` index, deletes at most 500 expired rows,
and selects them with `FOR UPDATE SKIP LOCKED` so concurrent calls do not
serialize on maintenance.

`public.claim_beta_waitlist_challenge_attempt(ip_hash)` is the service-only
distributed gate before Cloudflare Siteverify. It permits 20 challenge attempts
per IP/10 minutes and 100/day, then rejects before provider work. It has the
same empty search path, in-function service-role check, explicit revocations,
and privileged-routine allowlist requirements as the insertion RPC.

`public.submit_beta_waitlist_signup(email, ip_hash, user_agent, source)` is the
only insertion boundary. It is a service-role-only `SECURITY DEFINER` routine
with an empty search path and `internal.require_service_role()`. One transaction
allows at most 5 verified attempts per IP/10 minutes, 20 per IP/day, and 2,000
new unique rows globally/day. Duplicate canonical emails consume the IP budget
but not the global growth budget, and return an indistinguishable
`already_joined` result. The Next.js route must verify Cloudflare Turnstile
before calling this RPC.

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
- `native_region` (Text): Legacy free-text origin marker. New identification
  upserts omit this column so they preserve curated values on conflict and use
  its `Unknown` database default only for a new row. Regional catalog queries
  use `species_country_occurrences`, not this text field, once country coverage
  exists.
- `habitat_description` (Text): Summarizes the expected ecosystem parameters for
  the species.
- ~~`global_distribution_regions`~~ (JSONB): Dropped in migration
  `20260327140000_drop_global_distribution_regions.sql`. Previously populated
  with Gemini Flash-generated ISO 3166-1/3166-2 region codes that proved
  inaccurate. Species pages communicate geographic density through the GBIF
  occurrence tile overlay (driven by `gbif_taxon_key`), while Index country
  catalogs use normalized GBIF occurrence facets.
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
  (`GET /v1/species/{key}/vernacularNames?language=eng&limit=30`) during primary
  external species resolution. The current multimodal route may await that
  bounded cache-miss resolution as part of durable finalization; compatibility
  routes may populate it in their background insertion path. English-only filter
  applied (`language: eng | en`), normalised to Title Case, and deduplicated.
  The primary `common_names.en` value is excluded from this array
  (case-insensitive). `NULL` when GBIF returned no additional names or the
  species has not yet been enriched. Has a GIN index for array containment
  queries. Added in migration `20260407000000_add_alternative_common_names.sql`.
  Served to the client as `alternative_common_names` in the `/identify` Cache
  Hit response and the public `/species-dictionary` response; stored in
  `LocalScanRecord.alternativeCommonNames` (SwiftData V34) for scan surfaces
  only.
- `inaturalist_taxon_id` (INTEGER, nullable): Stable public iNaturalist taxon ID
  used by `/species-observation-stats` for observation charts. Only the current
  fenced population owner may write it after resolving the canonical dictionary
  name exactly; observation queries require `taxon_id` and never fall back to a
  caller-controlled name. Constraint: `NULL OR > 0`. Added in migration
  `20260517190000_add_species_observation_stats.sql`; write ownership was
  hardened in `20260724170709_harden_species_observation_stats.sql`.

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
  attribution display and the public web species page. The current web mapper
  treats either missing value as an attribution audit failure and omits that
  image from both page content and metadata.
- `width` / `height` (INTEGER, nullable): Optional pixel dimensions.
- `sort_order` (INTEGER): Display order for galleries and thumbnails.
- `created_at` / `last_verified_at` (TIMESTAMPTZ): Creation and health-check
  timestamps.
- RLS: anyone can read; non-service writes are not exposed by policy.

Ordering uses `public.public_species_reference_image_source_rank(...)`: Merian
images first, then Wikipedia, then GBIF, with `sort_order`, `created_at`, and
`id` as tie-breakers.

### `species_country_occurrences`

Normalized country occurrence evidence for species dictionary browsing. Added
in migration `20260731151344_add_species_country_occurrence_index.sql`.

- `species_id` (UUID FK -> `species_dictionary.id`, CASCADE DELETE) and
  `country_code` (uppercase ISO 3166-1 alpha-2 text) form the primary key.
- `occurrence_count` (BIGINT, positive): Number returned by GBIF's country facet
  for georeferenced PRESENT records without geospatial issues.
- `gbif_taxon_key` (BIGINT, positive): Taxon identity used for the provider
  query. Readers require it to match the current dictionary taxon key so stale
  rematches cannot leak into a country catalog.
- `source`: Fixed to `gbif_occurrence`.
- `last_refreshed_at`, `created_at`, `updated_at`: Refresh and audit clocks.
- Index: `(country_code, occurrence_count DESC, species_id)` supports exact
  country catalogs, counts, and representative-species selection.
- RLS: enabled with no public policies. `anon` and `authenticated` have no table
  privileges; `service_role` is granted only the operations required by the
  Edge read and replacement boundaries.

`public.replace_species_country_occurrences(...)` validates at most 300 facet
rows, locks the current dictionary taxon identity against concurrent rematches,
and replaces one species' complete country set in a single database call.
`public.get_species_dictionary_country_summaries(...)` returns exact ISO-country
species counts plus a representative species UUID for overview imagery. Both
functions are revoked from public client roles. A GBIF taxon-key change purges
the old rows, marks their provenance due, and enqueues a durable replacement.
The rows mean that GBIF has recorded the species in a country; they do not
assert that it is native there.

### Current-scan exclusion projection

Migration `20260721033935_exclude_current_scan_reference_images.sql` adds
`public.public_species_reference_image_urls_excluding_media(...)`. The helper
accepts a species ID, the legacy comma-separated fallback, and an array of media
URLs owned by the current scan. It delegates source selection to
`public.public_species_reference_image_urls(...)`, then removes exact trimmed
URL matches while retaining the base projection's ordinality.

Because the helper wraps the existing projection, Merian-first/Wikipedia/GBIF
ordering, the blocked-image policy, and legacy fallback behavior remain
unchanged. An all-excluded result is `NULL`, which is the existing no-reference
contract. The helper does not mutate `species_reference_images`, remove another
scan's promoted source, or add persisted provenance columns.

`public.get_explore_post_detail(...)` passes the backing scan's
`image_storage_urls` to this helper. The exclusion is therefore scoped to the
post being read and keeps the RPC result shape compatible with existing iOS and
web clients.

Exact external-media suppression is a defense-in-depth exception to normal
ordering. Migration
`20260719023147_suppress_european_wildcat_roadkill_image.sql` removes every
normalized URL matching
`inaturalist-open-data.s3.amazonaws.com/photos/605615444/`, scrubs the same
media from the legacy comma-separated cache while preserving the order of the
remaining values, and filters the public first/all-image SQL helpers. A
`BEFORE INSERT OR UPDATE OF url` trigger returns `NULL` for that exact path so
service-role refresh and repair writes cannot restore it. The trigger function
is not executable by `PUBLIC`, `anon`, or `authenticated`; `service_role`
retains execution for the trusted write path. Other GBIF/iNaturalist images and
other reference images for the same species are unaffected.

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
- `taxonomy_import_runs`: Private service-role audit rows for bounded GBIF
  imports and on-demand search cache misses. Tracks source, scope, status,
  requested query, target taxonomy version, row counts, errors, and metadata.
  `PUBLIC`, `anon`, and `authenticated` have no table privileges. The
  `service_role` grant is limited to `SELECT`, `INSERT`, and `UPDATE`; this
  table must never be used as an authorization capability probe because an
  RLS-filtered empty read is still a successful read.
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

Migration `20260725045544_repair_complete_edge_database_contracts.sql` restores
that publication gate in the canonical media-backed
`explore_projected_post_cards` projection after a later media migration
overwrote it. It preserves the later reversible-moderation exclusion and keeps a
withdrawn request visible through its original observation. Species sightings
reuse this projection, so an unpublished resolved request cannot remain visible
through a species-specific read.

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

### Internal Community Identify activity projection

Migration
`20260731050009_add_community_identification_activity.sql` creates and backfills
this projection. Companion migration
`20260731063804_index_community_identification_activity_actor_user_fk.sql` adds
the reverse `user_id` lookup needed for actor foreign-key enforcement during
account deletion and identity maintenance. Migration
`20260801145720_use_usernames_for_community_identification_activity.sql`
switches read-time actor attribution from profile/display names to public
usernames.

`internal.community_identification_activity_groups` stores service-only
suggestion bursts, standalone consensus changes, and immutable resolution
milestones for each request generation.
`internal.community_identification_activity_actors` stores normalized per-burst
actor IDs, counts, and latest suggestion times; it stores no actor names.
Suggestions chain into one burst at intervals of up to and including 60
minutes. Consensus events caused by a suggestion enrich the associated burst,
while unrelated consensus changes and every resolution remain separate.

`trg_record_community_identification_suggestion_activity` projects
`explore_identifications` inserts.
`trg_record_community_consensus_activity` projects
`community_consensus_events` inserts. Both trigger functions are
`SECURITY INVOKER`; their internal maintenance helpers are revoked from client
roles and granted to `service_role`. Activity is historical: later suggestion
withdrawal does not rewrite an already emitted suggestion burst, while its
resulting consensus event may create or enrich the appropriate consensus
metadata.

Both tables have RLS enabled and no direct `PUBLIC`, `anon`, or
`authenticated` privileges. Only `service_role` can maintain or read the
projection. The service-only
`public.get_community_identification_activity(...)` RPC resolves visible actor
public usernames at read time, applies the request feed's visibility and shared
scope/taxonomy filters, and paginates deterministically on
`(activity_at, activity_id)`. Migration backfill includes only each request's
current `requested_at` generation; older withdrawn/reopened generations remain
available through request audit detail. The RPC joins projection rows back to
the request's current `requested_at` generation, so prior generations remain
stored for audit but cannot leak into the Activity feed after reopen.

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
  receives table grants. `/species-dictionary` uses the promoted row's unique
  `(species_id, image_url)` key, rather than depending on nullable
  `reference_image_id`, to resolve only the contributor's public user ID and
  current public username. Source scan/post IDs, confidence snapshots, and other
  provenance are not exposed.
- The repair migration keeps candidate upserts and stale-source disqualification
  disjoint, then links promoted rows and demotes valid unselected rows in
  sequential statements. A provenance row is never targeted by competing sibling
  mutations, so active links converge and unshared or otherwise ineligible media
  is deterministically marked disqualified.

### `species_observation_stats_cache`

Server-side cache for global public species observation chart payloads. Added in
migration `20260517190000_add_species_observation_stats.sql`.

- `species_id` (UUID FK -> `species_dictionary.id`, CASCADE DELETE): Owning
  species.
- `source` (TEXT): Provider key. The current contract supports only
  `inaturalist`.
- `scope` (TEXT): Public aggregation scope. The current contract supports only
  `global`.
- `scientific_name` (TEXT): Normalized species name used for display/debugging.
- `payload` (JSONB): Full public stats response payload stored as an object.
- `status` (TEXT): `fresh`, `stale`, `no_data`, `unavailable`, or `partial`.
- `provider_error` (TEXT, nullable): Joined provider error messages from the
  most recent refresh attempt.
- `fetched_at` (TIMESTAMPTZ): Provider/cache payload timestamp.
- `expires_at` (TIMESTAMPTZ): Status-aware freshness cutoff. V2 writes seven
  days for `fresh`, 24 hours for `no_data`, one hour for `partial`, and five
  minutes for `unavailable`.
- `created_at` / `updated_at` (TIMESTAMPTZ): Audit fields. `updated_at` is
  maintained by trigger.
- Primary key: `(species_id, source, scope)`.
- Index: `idx_species_observation_stats_cache_expires_at`.
- RLS: anyone can read; writes are service-role only.

The fenced finalizer has stale-if-error semantics. When a provider refresh
finishes as `unavailable`, a positive `fresh`/`partial`/`stale` row whose
original `fetched_at` is no more than 37 days old is retained. The finalizer
sets both row and payload status to `stale`, preserves the original payload and
`fetched_at`, records the latest bounded `provider_error`, and advances only
`expires_at` by five minutes as a retry backoff. Cold misses, `no_data` rows,
and positive rows outside that retention ceiling use the ordinary five-minute
`unavailable` negative cache.

The payload contains public iNaturalist aggregates only: seasonality, rolling
seven-year history, life-stage annotation series, sex annotation series, total
observations, most recent observation date, provider metadata, and provider
errors. It must not contain Merian user IDs, scan IDs, Explore post IDs, field
notes, local media, locations, or local observation counts.

### `internal.species_observation_stats_rate_counters`

Private fixed-window counters added in migration
`20260724170709_harden_species_observation_stats.sql`.

- Keys: `(scope_type, scope_key, bucket, window_start)`.
- Scopes: request user/IP and cold-population user/IP/global.
- `scope_key` contains a verified user UUID, a daily purpose-separated IP HMAC,
  or the fixed global key. Raw addresses are never persisted.
- `request_count` is incremented with a conditional UPSERT; crossing a limit
  fails the same transaction.
- No API role, including `service_role`, has direct table privileges. Reviewed
  `SECURITY DEFINER` RPCs own access.
- An hourly bounded cleanup removes rows older than two days.

### `internal.species_observation_stats_population_leases`

Private distributed cold-population ownership added in migration
`20260724170709_harden_species_observation_stats.sql`.

- `species_id` (UUID PK/FK): one active generation per dictionary species.
- `lease_token` (UUID): fencing token replaced on expired-lease recovery.
- `lease_started_at` / `lease_expires_at`: 90-second population window.
- `attempt_count`: counts recovered generations for operations.
- `claim_species_observation_stats_population(...)` serializes the short claim
  decision with a transaction advisory lock; the row lease owns work after the
  RPC connection closes.
- `finalize_species_observation_stats_population(...)` compares the token and
  atomically validates provider identity, stores an exact taxon ID, upserts the
  public cache, and removes the lease. A late generation returns `false`. An
  unavailable refresh also preserves any still-retained positive payload in the
  same fenced transaction, so a provider incident cannot replace chart data with
  an empty response.
- No API role has direct table privileges; only the four allowlisted
  service-role RPCs can preflight IP use, authorize, claim, or finalize.

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
  `reference_images`, `country_occurrences`, `lookalikes`, `group_tags`,
  `iucn_red_list_status`, and `hazard_type`.
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
the older provenance queue only as a fallback. That group also refreshes the
normalized GBIF country-occurrence index and its provenance clock.
`refresh-species-model-content`
claims `habitat`, `lookalikes`, and `group_tags` jobs and reuses the same
species-level primitives behind `enrich-scan`. New GBIF-backed species
materialized from Community ID publish enqueue all four content groups so
external refresh and model-heavy enrichment can proceed independently.
`20260707153931_species_dictionary_enrichment_queue_backfill.sql` adds an insert
trigger on `species_dictionary` so every future species row, regardless of
creator, queues only the enrichment groups it is missing. The same migration
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
- `last_imported_offset`: Most recent GBIF page offset that was successfully
  fetched and checkpointed for the target. It advances even when a raw
  nonempty page produces zero normalized taxa.
- `next_import_offset`: Machine cursor used by `sync-community-taxonomy-index`
  when `offset` is omitted. This is the preferred continuation pointer for
  operator scripts and cron.
- `last_successful_import_at`, `last_import_error`, `gbif_total_count`,
  `import_cursor_metadata`: Bounded-import health and cursor diagnostics,
  including the last GBIF count reported for the target and retry metadata.
- `last_computed_at`: Freshness marker for
  `refresh_taxonomy_coverage_targets()`.

The Birds target is populated by bounded `sync-community-taxonomy-index`
imports. Every successfully fetched live page checkpoints its raw next offset,
including pages whose results all normalize out; a later failure retains those
earlier checkpoints. Dry runs advance only a simulated response cursor and
write none of these fields. Individual GBIF upsert pages pass
`refresh_coverage = false`, and the worker calls
`refresh_taxonomy_coverage_targets()` once only when the completed run imported
at least one row and requested a refresh. Do not show gamified completion claims
until the target's `indexed_species_count` has been seeded from the bounded
import.

### `scans`

The transaction log for every successful identification.

- `id` (UUID)
- `user_id` (UUID - Foreign Key, nullable only for tombstones): Normally
  references `public.users(id)`. Account-deleted retained observations set it to
  `NULL`; validated `scans_ownerless_requires_tombstone_check` rejects every
  ownerless row whose `is_tombstoned` value is not true.
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
- `image_storage_urls` (Text Array): Canonical image/media URLs. The validated
  DwC-A source constraint permits at most 24 non-null elements of 4,096 UTF-8
  bytes each and rejects control characters.
- `ecological_interactions` (Text Array): Biotic interactions between subjects
  (e.g., predation, pollination, parasitism) derived by the AI. The validated
  DwC-A source constraint permits at most 10 non-null elements of 2,048 UTF-8
  bytes each and rejects control characters.
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
- `audio_storage_urls` (Text Array): Durable standalone-audio links. Extracted
  video companion audio is not stored here because the playback MP4 is the
  public artifact.
- `captured_media` (JSONB): Canonical captured-media timeline using the iOS
  `SerializedMediaItem` shape. Video entries attach the playback clip and poster
  thumbnail together so sampled inference frames do not hydrate as standalone
  Insight carousel images, and include an audio reference only when extracted
  video audio was actually persisted. Video rows should be present whenever
  `video_storage_urls` is present. Ready display/playback rows in
  `scan_media_assets` are refreshed from this manifest when present and fall
  back to legacy media arrays for older rows. The compatibility image array is
  therefore not itself the canonical display-image set for a video scan.
- `is_flagged` (Boolean): Managed via `00005_flagged_reviews.sql` for
  human-reported moderation flags.
- `is_tombstoned` (Boolean): Managed via `00006_apply_user_tombstone.sql` and
  the ownerless forward migrations for account deletion. Retained rows have no
  owner and clear media, semantic/public location labels, device context,
  custom tags, and free-form intervention notes. Exact coordinates, elevation,
  time, taxonomy, identification, environmental, quality, and provenance facts
  remain unchanged as mandatory Scientific Data. Tombstones are available only
  to reviewed backend scientific paths and are excluded from the broad
  anonymous scans policy.
  See the
  [canonical retention contract](./17-scientific-observation-retention.md) for
  the complete retained-versus-cleared boundary and required change procedure.
- `custom_tags` (Text Array): User-defined plain-text labels for personal
  categorization. The database allows at most 50 non-null/control-free elements
  of at most 256 UTF-8 bytes each; iOS additionally limits visible tag length to
  64 characters. Current clients call
  `update_owned_scan_custom_tags(scan_id, tags)`, which derives ownership from
  `auth.uid()` and updates no other column. Added in
  `20260328221000_add_custom_tags_to_scans.sql` and hardened in
  `20260728035237_harden_dwca_downloads_and_scan_finalization.sql`.
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
  captured before migration `20260330000000_add_candidates_to_scans.sql`. Shape:
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
  `20260330120000_add_user_identification_override.sql`. The database caps it at
  1,024 UTF-8 bytes. Current clients synchronize the complete coherent review
  through `update_owned_scan_identification_review(...)`; that routine derives
  the owner from `auth.uid()`, validates typed state/nullability, and updates
  all related review fields atomically.
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
  owner-derived review RPC as the related legacy override columns.

Migration `20260728035237_harden_dwca_downloads_and_scan_finalization.sql`
revokes scan INSERT/DELETE and broad UPDATE from `PUBLIC`, `anon`, and
`authenticated`. It grants only the two owner-derived RPCs to `authenticated`.
For rolling compatibility with already-installed iOS versions, a temporary
column-level UPDATE grant remains for `custom_tags` and the four identification
review columns; RLS still requires the authenticated owner. No API role can
write scan identity, ownership, media, privacy, ingestion, or model-result
columns. Remove the compatibility grant only after the minimum supported app
version contains both RPC call sites.

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
scientific names and candidates, and do not trigger
`is_new_to_merian_dictionary`.

### `collections` and `collection_scans`

`collections` stores cloud-backed custom albums; `collection_scans` is their
many-to-many membership table. They were introduced by
`20260322161804_collections_sync.sql` and hardened by
`20260803180211_harden_collection_ownership_and_memberships.sql`, with
`20260803215309_fix_collection_owner_upsert_ordinality.sql` and
`20260803215310_grant_collection_sync_invoker_privileges.sql`, then
`20260804002819_fix_collection_membership_conflict_ambiguity.sql`, providing
its forward execution, invoker-privilege, and PL/pgSQL conflict-resolution
repairs.

- `collections.id` (UUID): client-stable primary key.
- `collections.user_id` (UUID FK -> `auth.users.id`, cascade delete): immutable
  owner under normal table access. Ownership may be reparented only by the
  existing reviewed Ghost merge function.
- `collections.name` (TEXT) and `created_at` (TIMESTAMPTZ): the only mutable
  fields accepted by the synchronization upsert.
- `collection_scans.collection_id` (UUID FK -> `collections.id`, cascade
  delete) and `scan_id` (UUID FK -> `scans.id`, cascade delete): composite
  primary key. Every valid row must join parents with the same non-null owner.

The hardening migration removes historical rows whose two parent owners
provably differ, then installs `enforce_collection_scan_owner_match` before
insert or parent-ID update. The trigger is `SECURITY INVOKER`, has an empty
search path, and rejects missing or differently owned parents with SQLSTATE
`23514`. It protects direct service access in addition to RLS.

Authenticated `collection_scans` policies are operation-specific:

- select and delete require the parent collection owner to equal
  `(SELECT auth.uid())`;
- insert requires both the parent collection and parent scan owners to equal
  `(SELECT auth.uid())`; and
- update has no policy and is unsupported.

The route uses two service-only invoker RPCs rather than a privileged
SELECT-then-upsert preflight:

- `public.upsert_owned_collections(p_user_id UUID, p_collections JSONB)` accepts
  at most 200 rows and performs one atomic `INSERT ... ON CONFLICT ... DO
  UPDATE`. It updates only `name` and `created_at` when the existing owner
  matches, and returns `(collection_id, accepted)` for every deduplicated input.
  A foreign or concurrent UUID collision is rejected without mutation.
- `public.insert_owned_collection_scans(p_user_id UUID, p_rows JSONB)` accepts
  at most 1,000 rows, joins both parents to `p_user_id`, inserts the admitted
  deduplicated pairs, and returns inserted pairs. Missing or foreign parents are
  skipped for later offline ordering.

Both functions use empty search paths and schema-qualified objects. Execute is
revoked from `PUBLIC`, `anon`, and `authenticated`, then granted explicitly to
`service_role`. `service_role` has no table-level UPDATE on `collections`; its
direct column-level UPDATE grant is limited to `name` and `created_at`. RPC
errors remain failures and must never be interpreted as an empty accepted set.

### `insight_chat_conversations`, `insight_chat_messages`, `insight_chat_message_feedback`, `insight_chat_feature_feedback`

Private saved follow-up chat for completed biological Insight sheets. Chat
conversations/messages were added in migration
`20260626120000_add_insight_chat.sql`; answer feedback was added in
`20260628120000_add_insight_chat_feedback.sql`; sheet-level feature feedback was
added in `20260629100000_add_insight_chat_feature_feedback.sql`.

- `insight_chat_conversations.id` (UUID): Primary key.
- `scan_id` (UUID FK -> `scans.id`, cascade delete): The owned scan this chat is
  attached to. `scan_id` and `user_id` are unique together so each user has one
  saved Field chat per scan. A deferred composite foreign key requires every
  retained conversation to match the exact scan owner before commit.
- `user_id` (UUID FK -> `users.id`, cascade delete): Owner. RLS allows users to
  access only rows where `auth.uid() = user_id` if a future reviewed grant
  exposes the table. Direct `anon` and `authenticated` table privileges are
  revoked; current app access is exclusively through the authenticated Edge
  Function.
- `created_at`, `updated_at`: Conversation timestamps; `updated_at` is
  maintained by the shared timestamp trigger.
- `insight_chat_messages.id` (UUID): Primary key.
- `conversation_id` (UUID FK -> `insight_chat_conversations.id`, cascade
  delete): Parent conversation. Deleting a scan deletes its conversation and
  messages.
- `scan_id`, `user_id`: Denormalized owner bounds for indexes, RLS, analytics,
  and daily send limits. A deferred composite foreign key requires
  `(conversation_id, scan_id, user_id)` to match the exact parent conversation
  before commit.
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
  deletes with the assistant message, conversation, scan, or user. A deferred
  composite foreign key requires all four copied identities to match the rated
  message.
- `rating`: CHECK-constrained to `helpful`, `not_helpful`, `wrong`, `unsafe`, or
  `other`.
- `note`: Optional short private feedback note, capped at 1000 characters.
- `created_at`, `updated_at`: Feedback timestamps maintained by trigger.
- `insight_chat_feature_feedback.id` (UUID): Primary key for private feedback on
  the Field chat experience itself.
- `conversation_id` (UUID FK -> `insight_chat_conversations.id`, set null):
  Optional chat thread context. The row remains useful if the thread is deleted;
  while present, a deferred composite foreign key requires its conversation,
  scan, and owner identities to agree.
- `scan_id`, `user_id`: Owner bounds. A deferred composite foreign key binds
  feature feedback to the exact scan owner even without conversation context.
  Feedback deletes with the scan or user and is RLS owner-only.
- `sentiment`: Optional CHECK-constrained `positive` / `negative` rating from
  the sheet-level feedback modal.
- `note`: Optional short private feature-feedback note, capped at 1000
  characters. Feature feedback requires either `sentiment` or `note`.
- `created_at`: Submission timestamp.

These tables are private scan data. They are not read by Explore, public species
dictionary endpoints, public web pages, or Darwin Core exports.

### `explore_post_chat_conversations`, `explore_post_chat_messages`, `explore_post_chat_message_feedback`

Private per-viewer Field chat for any active Explore post visible to the viewer,
including their own, added in `20260721141655_add_explore_post_chat.sql`.

- `explore_post_chat_conversations` is unique on `(post_id, user_id)`, so each
  viewer has one thread per post. `user_id` is the conversation owner and may
  also be the post author's ID.
- `species_dictionary_id` records the public species context used by the thread.
  A context change causes the Edge Function to replace the stale conversation.
- `explore_post_chat_messages` stores owner-bound user and assistant messages,
  optional idempotent `client_message_id` values, refusal metadata, and Gemini
  token telemetry. A deferred composite foreign key binds every row to its exact
  `(conversation_id, post_id, user_id)`.
- `explore_post_chat_message_feedback` stores one private rating per viewer and
  assistant message, with an optional note capped at 500 characters. Its copied
  message/conversation/post/viewer identity is a deferred composite child of the
  exact rated row.
- All three tables enable RLS with `auth.uid() = user_id` ownership checks and
  revoke direct `anon` and `authenticated` table privileges. Only the
  authenticated Edge Function uses service-role access. No other viewer can load
  the conversation.
- Foreign-key cascades remove messages and feedback with their conversation. An
  `explore_posts.unshared_at` trigger deletes every viewer conversation when the
  source post is unpublished.

These rows are private conversation data, not Explore comments, notifications,
public profile content, web post data, or Species Dictionary contributions.

Migration `20260729163616_reserve_field_chat_sends_atomically.sql` joins
admission for both chat families in service-only
`reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)`. Every new user row is
created in the same short transaction that takes the cross-table per-user lock,
then the per-conversation lock, verifies exact subject ownership, rejects a
different unanswered request, reserves two of the 30 conversation rows, and
enforces the 20-send UTC-day cap across Insight and Explore. Exact same-key/text
replays return the original user row without consuming either cap; contradictory
same-key text is rejected. The migration explicitly reconstructs least-privilege
service-role table ACLs and removes direct browser-role access, so app clients
cannot bypass the serialized boundary.

The same migration adds service-only
`recover_stale_field_chat_quota(uuid,text,uuid,uuid,uuid)`. It may transition
only a ten-minute-stale committed `insight_chat_reply` or
`explore_post_chat_reply` reservation to `failed`, and only after proving the
exact subject-bound user row exists and its UUID-bound assistant does not. This
closes the otherwise permanent crash window after quota commit while preserving
the generic quota ledger's fail-closed semantics and charging any subsequent
provider attempt as a new metered attempt.

Migration `20260730180000_bind_field_chat_rows_to_subjects.sql` removes
impossible historical cross-owner Insight conversations and cross-bound
message/feedback rows before validating the composite identity constraints
described above. Every retained Insight conversation is structurally bound to
its exact scan owner, and each child remains bound to that exact conversation.
Conversation-optional feature feedback is independently bound to its exact scan
owner; the migration deletes only impossible cross-owner feedback and clears
only an unprovable optional conversation reference from otherwise valid scan
feedback. It also removes direct `anon` and `authenticated` privileges from all
private Field Chat feedback tables and grants the backend only the
select/insert/update operations its routes use. Exact relationship-based RLS
policies remain as defense in depth.

### `flagged_reviews`

Captures user feedback disputing an identification or inference. It is not the
moderation queue for reports about public Explore post content.

- `id` (UUID): Primary key.
- `scan_id` (UUID - Foreign Key): References `scans`.
- `user_id` (UUID - Foreign Key): References `public.users(id)` for the user
  requesting identification review.
- `flag_reason` (Text): e.g. "Incorrect Species" or "Inappropriate Content".
- `user_suggestion` (Text): Optional custom text feedback.
- `status` (Text): Defaults to `PENDING_REVIEW`.

### `explore_post_reports`

Service-role-only moderation queue for complaints about public Explore post
content.

- `id` (UUID): Primary key.
- `post_id` (UUID - Foreign Key): References `explore_posts(id)` and cascades
  when the post is deleted.
- `reporter_user_id` (UUID - Foreign Key): References `public.users(id)` for the
  authenticated reporter.
- `post_author_user_id` (UUID - Foreign Key): Snapshots the reported post owner
  for moderation lookup and cascades with the user.
- `reason` (Text): CHECK-constrained to `Spam`, `Harassment`,
  `Inappropriate content`, or `Other`.
- `details` (Text): Optional context; the Edge Function trims and caps input at
  500 characters.
- `status` (Text): `PENDING_REVIEW`, `DISMISSED`, or `ACTIONED`.
- `created_at`, `updated_at` (Timestamptz): Queue timestamps.

`(post_id, reporter_user_id)` is unique so repeat submissions update one queue
item. RLS is enabled with no public policies; the authenticated
`/report-explore-post` Edge Function performs validated service-role writes. New
rows default to `PENDING_REVIEW`; repeat submissions preserve an existing
`DISMISSED` or `ACTIONED` status. This table never changes `scans.is_flagged`.

### `internal.dwca_export_release_control`

Private singleton installed by
`20260728133835_disable_dwca_exports_for_launch.sql`. It contains `singleton`,
the canonical `enabled` Boolean, and `updated_at`. The row defaults to disabled;
missing state is also interpreted as disabled. RLS is enabled and
`PUBLIC`/`anon`/`authenticated`/`service_role` have no table privileges.

`internal.enforce_dwca_export_intake_gate()` runs from the alphabetically first
BEFORE INSERT trigger on `public.export_jobs`, before any expensive snapshot or
webhook trigger. It rejects every insertion with stable SQLSTATE `55000` and
`dwca_exports_disabled` while off, including inserts from an old Edge bundle or
an unexpected direct service-role path.

`public.get_dwca_export_release_state()` and
`public.request_dwca_export_job(uuid,text,boolean)` are allowlisted only for
`service_role`; both call `internal.require_service_role()` and use empty fixed
search paths. The request routine takes a transaction advisory lock keyed by
user, then atomically evaluates the release state, rolling 24-hour
successful/nonterminal window, and insertion. Only the exact pending-job unique
index maps to `already_pending`; unrelated uniqueness failures are rethrown. The
launch migration unschedules continuation, terminalizes pending/processing jobs,
revokes capabilities, queues known archives, and clears terminal work
manifests/leases. Archive-cleanup cron remains active.

### `export_jobs`

Stateful queueing table for asynchronous Darwin Core Archive (DwC-A) exports.

- `id` (UUID): Primary key.
- `user_id` (UUID - Foreign Key): References `auth.users`. Rate-limited to one
  successful/nonterminal request per rolling 24 hours inside the atomic
  service-only request RPC.
- `status` (ENUM): `'pending'` | `'processing'` | `'completed'` | `'failed'`.
- `export_scope` (Text): Default `'personal'`. Accepted values: `'personal'` |
  `'global'`. Validated at the Edge layer — values outside this set are rejected
  with `HTTP 400`. Defines whether to export only the requesting user's captures
  (`'personal'`) or all globally open data (`'global'`).
- `include_precise_coordinates` (Boolean): Access control flag.
- `pseudonym_key_version` (Smallint): Immutable key version pinned when the job
  is inserted. Version `n` selects `DWCA_PSEUDONYM_HMAC_KEY_V{n}`.
- `max_export_rows` (Integer): Immutable canonical budget, default 5,000 and
  constrained to 1...20,000.
- `max_archive_bytes` (Bigint): Immutable final archive budget, default 8 MiB
  and constrained to 1...16 MiB.
- `archive_object_key` (Text): Attempt-fenced R2 object key staged by the
  current worker before delivery.
- `archive_ready_at` (TIMESTAMPTZ): Time the archive and reusable application
  download capability were durably staged.
- `file_url` (Text): Owner-visible, 24-hour application capability URL. It
  points to `/functions/v1/download-dwca`, not directly to R2. A new transition
  to `completed` requires this and both archive fields.
- `failure_code` (Text): Stable machine-readable failure classification.
- `error_message` (Text): Public-safe failure copy, capped at 500 characters.
- `created_at`, `completed_at` (TIMESTAMPTZ): Lifecycle tracking metrics.

The request fields, budgets, and creation time are immutable after insert.
Direct `anon`/`authenticated` insertion is revoked; when the canonical release
gate is enabled, `request-export-dwca` queues only personal exports through the
atomic service-only request RPC. Global rows can be created only by a reviewed
internal administrative workflow. While the initial-launch gate is off, the
BEFORE INSERT trigger rejects both paths. A partial unique index permits at most
one pending/processing job per user, while the rolling-window predicate excludes
failures. Both the request RPC and legacy-insert trigger retain a shared lock on
the private singleton until transaction end; reviewed state changes take the
conflicting row lock and therefore cannot interleave with intake.

`internal.export_job_claims` stores the private claim UUID, short lease,
heartbeat, and bounded attempt count. It has RLS, no API-role table grants, and
is accessible only through service-authorized, empty-search-path definer RPCs.
Every worker state mutation checks the current unexpired token. The webhook
therefore treats only the opaque job UUID as authoritative; canonical user,
scope, precision, key version, budgets, and durable phase are loaded
transactionally by `claim_export_job_step(...)`.

`internal.export_worker_protocol` is a private singleton with the finite
`legacy_payload_until` deadline. Pre-existing nonterminal jobs and jobs created
in the first two hours after the migration are the finite compatibility cohort;
newly queued cohort jobs may carry canonical row-derived user/scope/precision
hints for the previous bundle and may finish without the new archive columns.
Jobs created after that deadline receive `job_id` only and the transition
trigger requires a private claim before `processing`. The hardened bundle
ignores rollout hints in all cases. Failure transitions always replace
caller-supplied text with a stable owner-safe message, including failures
written by the previous bundle. Once a hardened claim exists, a rollout-era
worker cannot fail that attempt or replace its staged archive; its redundant
`processing` write is rejected too. The new worker does not recover an unclaimed
cohort row that is already `processing`; the watchdog owns that 30-minute
failure path. Result fields become immutable at a terminal status. The
pre-existing atomic ghost-profile merge marker is normalized to `owner_changed`
so an identity merge can still terminate colliding active jobs. The protocol
table has RLS and no API-role table grants.

**Export jobs watchdog cron** (lease-aware definition in
`20260724230849_harden_dwca_export_jobs.sql`): A `pg_cron` job
(`expire-stuck-export-jobs`) runs every 5 minutes and tombstones any job stuck
pending beyond 30 minutes or processing without a live claim. It writes a stable
failure code/message so the user can request a new job. The watchdog is a plain
SQL function (`public.expire_stuck_export_jobs()`) run by the existing cron
schedule; no additional Edge Function is required.

Migration `20260725052339_bound_dwca_export_work.sql` adds two private tables:

- `internal.export_job_work`: one row per job containing phase (`occurrence`,
  `multimedia`, `assembling`, `delivering`, or `completed`), separate UUID
  keyset cursors, cumulative row/CSV-byte counts, chunk sequence, next-attempt
  time, and bounded retries.
- `internal.export_job_chunks`: an ordered manifest keyed by
  `(job_id, phase, sequence)` with a claim-token-fenced R2 object key and byte
  count plus an unsigned, range-constrained CRC-32 for each CSV page.

Each claim still owns exactly one phase. Data phases read at most 100 scans and
commit at most a 512 KiB chunk, cursor, manifest row, and cumulative budgets
transactionally. The expected object key includes the active claim token,
preventing a lease-expired writer from overwriting a replacement's chunk. A
minute-level cron calls the worker with an empty body; that invocation
sequentially drains five-job oldest-due waves until a 40-second soft cutoff or
40-step ceiling. `next_step_at` plus the partial `export_job_work_due_idx` makes
each successful job rotate behind older due work. The updated watchdog fails
only work with no live claim and no phase progress for two hours.

Migration `20260726235158_amortize_dwca_archive_crc.sql` makes the chunk CRC
non-null and bounded to `0...4294967295`, adds it to the fenced atomic advance
RPC and manifest result, and updates the service-role routine allowlist. Ordered
chunk CRCs are mathematically composable, so final ZIP assembly derives each
entry CRC from manifest metadata without rescanning the complete CSV in
JavaScript. Rollout fences and restarts only nonterminal preparation/assembly
work whose legacy manifest lacks CRCs; delivering jobs are unaffected. Canonical
job rows are locked in UUID order before manifest DDL so deployment cannot
invert the job→work→chunk lock order used by worker routines. A worker already
inside a database routine may commit before the fence; the migration then
re-evaluates that committed phase. A worker in an affected phase still
performing R2 I/O blocks on the canonical row and loses its obsolete claim at
migration commit, so it cannot append to the replacement manifest.

Migration `20260726230837_scale_dwca_export_continuations.sql` adds
`idx_export_jobs_nonterminal_created` for outstanding-job diagnosis and the
service-only `get_dwca_export_queue_health()` definer RPC. It returns aggregate
backlog, due-job, active/expired-claim, and oldest-due-age fields. The routine
uses an empty search path, calls `internal.require_service_role()`, is
explicitly revoked from `PUBLIC`/`anon`/`authenticated`, and is the only catalog
boundary used by dispatcher and scheduled queue-health alerts.

The backlog count includes all nonterminal work, including rows in bounded
backoff or under a live lease. Due count and oldest-due age include only rows
whose `next_step_at` has arrived and which have no unexpired claim. A zero due
count therefore means there is no currently claimable work; it does not imply
that the nonterminal backlog is empty.

Ordered migrations `20260725175312_bound_dwca_export_source_bytes.sql` and
`20260725180321_validate_dwca_export_source_bounds.sql` install and validate
three source-shape constraints, then initially add private
`internal.dwca_export_occurrence_source` and
`internal.dwca_export_multimedia_source` projections plus
`public.get_dwca_export_scan_batch(...)`. The definer RPC is allowlisted only
for `service_role`, verifies the active job claim and exact phase cursor, and
applies both a 100-row ceiling and a 256 KiB cumulative serialized-source
ceiling before returning payloads to Edge. API roles have no direct read grant
on either source projection.

Migration `20260726025103_snapshot_dwca_export_sources.sql` initially replaced
those two live phase projections with compact membership fingerprints. Migration
`20260727233841_add_public_web_explore_boundary_and_immutable_dwca_rows.sql`
replaces that representation with source snapshot version 2:

- `internal.export_job_source_state`: one private row recording snapshot
  version/time, the exact eligible scan count (or the canonical row budget plus
  one when known too large), exact projected-source byte count, immutable source
  budget, terminal purge time, and the early-too-large flag. Version 2 source
  bytes are capped at four times `max_archive_bytes`, never above 64 MiB.
- `internal.export_job_source_rows`: the immutable `(job_id, scan_id)` set, one
  32-byte scope-aware eligibility hash, bounded occurrence/multimedia JSON DTOs,
  and the exact UTF-8 byte count of each DTO. Each projection is limited to 256
  KiB. Exact GPS fields exist only in an opted-in, unprotected personal
  occurrence DTO; global and non-precise personal rows omit those keys. The
  table has RLS and no API-role grants.
- `internal.dwca_export_snapshot_source`: a private projection used once to
  create the DTOs and later only to recompute live eligibility. Its taxonomy
  join uses `COALESCE(confirmed_species_id, species_id)`.

An insertion trigger materializes membership, both immutable DTOs, source
statistics, and eligibility hashes in one MVCC statement before the webhook can
run. The repaired routine first counts only UUIDs through the row-budget
lookahead, then projects, measures, and inserts one row at a time through a
parameterized lateral cursor. It stops at the first per-row or cumulative byte
violation and removes partial rows. The aggregate ceiling therefore bounds JSON
DTO memory and temporary-sort amplification during an oversized rejection.

There is intentionally no `scan_id` foreign key: deleting a scan should revoke
delivery rather than silently remove it from a later phase. The page RPC
keyset-paginates the source-row primary key and returns the stored phase DTO
after checking post-cursor scope-aware eligibility. A shared full-member
predicate separately checks snapshot version, exact count, durable invalidation,
current eligibility, and every hash before assembly, staging, email, completion,
and download. Scan/taxonomy triggers durably invalidate affected nonterminal
jobs. The additional monotonic trigger path does not filter by the job status
visible to the privacy statement, closing a statement-snapshot race with
concurrent delivery; it revokes any grant already present and enqueues the
current archive. Deletion, tombstoning, owner/live/ecology changes, global
geoprivacy changes, taxonomy identity changes, or protected-species policy
changes become terminal `source_snapshot_changed`.

`internal.export_job_work.delivery_file_url` holds the nullable constrained
application capability while processing. It is inaccessible to API roles.
Completion copies it to `public.export_jobs.file_url` and changes status in one
final-fence transaction, so no session can observe an owner-readable processing
URL. Pre-upgrade nonterminal jobs are fenced and restarted with prior manifests
discarded. Failed transitions delete DTO rows and retain only nonsensitive
source-state metadata with `purged_at`; completed DTOs remain only until grant
cleanup. Exact-SHA verification is tracked in
[`14-dwca-and-public-web-release-hold-2026-07-27.md`](./14-dwca-and-public-web-release-hold-2026-07-27.md).

Migration `20260728035237_harden_dwca_downloads_and_scan_finalization.sql` adds
three no-API-grant, RLS-enabled private tables:

- `internal.export_download_grants`: one grant per job with a unique SHA-256
  token index, expiry, revocation reason/time, and verified cleanup time. The
  random token is distributed through the owner/email capability URL; the grant
  authorization index stores only its hash.
- `internal.export_download_rate_windows`: distributed five-minute counters by
  daily/purpose-separated client-address HMAC.
- `internal.export_archive_cleanup_jobs`: unique archive-object deletion outbox
  with oldest-due scheduling, UUID claim token, bounded lease, attempt/backoff
  metadata, and completion time. Partial indexes support due claims and expired
  lease repair. Completion is fenced to the job's exact current
  `archive_object_key`; cleanup of an older attempt cannot revoke a replacement
  grant or purge source rows. Source DTOs are purged only for exact-current
  terminal cleanup.

`authorize_dwca_archive_download(...)` is service-only. It rate-limits first,
loads a capability by hash, and reruns the complete source-membership privacy
predicate on every click. Success returns only the canonical object key to the
Edge route, which creates a no-store read signature valid for at most 30
seconds. Any expired/revoked/privacy-invalid grant is terminally revoked and
enqueued for cleanup. Scan/species privacy triggers monotonically invalidate
unpurged snapshots and revoke any already-visible grant, while click
authorization repeats the full predicate as a fail-closed backstop.
Claim/complete/release/health cleanup RPCs are likewise service-only and use
empty search paths. The cleanup worker purges retained completed DTOs only after
exact-current R2 deletion (or idempotent `404`) succeeds.

All runtime transitions that combine the canonical export job with source state,
a grant, or cleanup outbox row call `internal.lock_dwca_export_generation(...)`.
The invariant is parent export-job row `FOR UPDATE` first, transaction advisory
generation lock second, and child rows afterward. Privacy triggers visit
affected jobs in UUID order. Delivery, privacy invalidation, job deletion, and
delayed cleanup therefore cannot invert locks or cross an archive/grant
generation.

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
- `quota_reservation_id` (UUID, nullable): Exact quota reservation identity for
  structured post-result recovery evidence.
- `quota_request_id` (UUID, nullable): Exact normal/replay request identity for
  structured post-result recovery evidence.
- `failure_kind` (TEXT, nullable): For structured recovery evidence, exactly
  `post_result_scan_durability_failure`.
- `provider_result_validated` (BOOLEAN, nullable): `TRUE` only after provider
  finish-reason and response-schema validation.
- `identify_safety_evaluation_completed` (BOOLEAN, nullable): Whether required
  Identify media safety evaluation completed. Automatic recovery requires
  `TRUE`.

The five structured fields are either all absent (legacy/operational history) or
all present with the constrained failure kind and validated-provider flag.

**Context**: Older background ingestion originally wrote this row only after
`insertScan()` failed (FK violation, DB timeout, network partition) even though
the iOS client had already received a `200` with the AI result.
`/identify-multimodal` now treats insertion as part of its success boundary and
returns retryable `scan_persistence_failed` instead of delivering a new
local-only observation. Current scan-producing paths write `scan_ingestion_jobs`
plus sanitized `scan_ingestion_intents`; `/identify-multimodal` does this
natively and the compatibility endpoints (`/identify`, `/identify-describe`,
`/audio-spec`) use the shared compatibility ledger. `failed_scan_ingestions`
remains as legacy ops evidence and detailed insert-failure history, not the
primary recovery surface. Field Chat availability checks and Insight-originated
Explore or Ask the Community actions can still repair an already-affected
observation by recreating a validated minimal owned `public.scans` row from the
local record before media restore. A row in this table is never sufficient
authority by itself: media-abandonment recovery evaluates all deterministic
normal/replay quota keys, requires the dead letter to be no earlier than the
latest charged authority, rejects active reservations or invalid timestamp
lineage, and rejects both moderation-rejected and moderation-pipeline-failed
capture lifecycles. Pre-rollout unstructured rows are bounded by a private
database cutoff, the audited multimodal post-safety error lineage, and narrow
quota lineage; post-rollout rows must bind exact quota identity and completed
safety evaluation.

**Ops workflow**: Query by `user_id` and `failed_at` to identify affected users.
Prefer `scan_ingestion_jobs` plus `scan_ingestion_intents` for current rows and
let `replay-scan-ingestion` re-invoke `identify-multimodal` with the same
`client_scan_id` when the intent is resumable. Inline-media compatibility rows
are intentionally non-resumable because raw media bytes are redacted. The
`ignoreDuplicates: true` guard plus owner-scoped read-back in `insertScan` makes
replay safe without turning a no-op/cross-owner collision into success.
Compatibility recovery additionally evaluates the owner ingestion state,
duplicate-safe owner-row write, and complete recovery-ledger write in one
transaction serialized against ingestion claim creation. Row Level Security is
enabled; the table is never read by the client SDK—only the Edge Function
service role writes to it and ops queries it through restricted tooling.

**Indexes**: `idx_failed_scan_ingestions_user_id` on `(user_id, failed_at DESC)`
for per-user lookups; `idx_failed_scan_ingestions_failed_at` on
`(failed_at DESC)` for chronological monitoring sweeps; and
`failed_scan_ingestions_recovery_proof_idx` on
`(user_id, scan_id, failed_at DESC)` for both owner/scan compatibility lookups
and chronological proof evaluation. The hardened migration drops the redundant
two-column `failed_scan_ingestions_user_scan_idx` introduced by the immediately
preceding compatibility migration.

### `internal.scan_recovery_evidence_control`

Private singleton rollout boundary added by migration
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql`.

- `singleton` (BOOLEAN, PRIMARY KEY, constrained `TRUE`): Enforces one control
  row.
- `legacy_unstructured_before` (TIMESTAMPTZ): Additional transaction-time
  cutoff. An unstructured dead letter at or after this value never authorizes
  automatic owner-row recovery, but an earlier timestamp is not sufficient
  authority by itself.
- `created_at` (TIMESTAMPTZ): Control-row creation time.

RLS is enabled and all table privileges are revoked from `PUBLIC`, `anon`,
`authenticated`, and `service_role`. Only the owner-executing private proof
routine reads it. `ON CONFLICT DO NOTHING` preserves the original cutoff and
prevents a later replay from expanding the paired legacy row snapshot.

### `internal.scan_recovery_legacy_dead_letters`

Private immutable row-identity snapshot added by migration
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql`.

- `failed_scan_ingestion_id` (UUID, PRIMARY KEY, FK): Exact
  `failed_scan_ingestions.id` visible when the hardening migration first
  installed its control row. Deleting the dead letter cascades and removes its
  recovery authority.
- `captured_at` (TIMESTAMPTZ): The immutable rollout boundary returned by that
  same first control-row insert.

The migration already holds the failed-ingestion table lock when it captures
these IDs. An older producer insert blocked behind that lock is therefore not in
the snapshot after it resumes, even if its historical `failed_at DEFAULT now()`
uses a transaction-start timestamp earlier than the cutoff. Legacy proof
requires both snapshot membership and the timestamp bound. RLS is enabled and
all table privileges are revoked from `PUBLIC`, `anon`, `authenticated`, and
`service_role`; only owner-executing private proof code reads it.

### `scan_ingestion_jobs`

Durable server-side lifecycle ledger for accepted scan ingestion requests. Added
in migration `20260705120000_add_scan_ingestion_jobs.sql`.

- `scan_id` (TEXT): The client-generated scan id used for idempotent scan
  insertion and status polling. TEXT keeps failure rows representable even when
  a malformed legacy id never becomes a `public.scans.id`. Quota pruning keeps
  its UUID cast inside the same regex-guarded conditional expression, so one
  malformed historical row cannot abort hourly cleanup.
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
- `terminal_reason_code` (TEXT): Stable bounded machine outcome for terminal
  jobs. Current values include policy rejection, replay exhaustion, media
  reconciliation abandonment, and owner deletion. Compatibility recovery fails
  closed unless this is exactly `replay_exhausted`, or exact
  `media_reconciliation_abandoned` is paired with matching composite
  dead-letter/quota/media-lifecycle proof. `user_deleted` is permanently
  nonrecoverable.
- `response_envelope` (JSONB, added by
  `20260728220000_persist_idempotent_scan_responses.sql`): At most 256 KiB of
  validated canonical Identify success data for this exact `scan_id`. It stores
  no raw media bytes and lets an ambiguous/concurrent retry return success
  without a second AI provider call. Completed rows created before this value
  was populated are reconstructed from the exact owner scan and species rows
  through the executable Identify wire contract.

`identify-multimodal` claims the row after request/media validation and updates
it through AI inference, moderation, media promotion, scan insert, and failure
paths. `/check-scan-status` keeps returning `status: "found" | "not_found"` for
client compatibility, and includes optional `job_status`, `job_stage`,
`job_attempt_count`, `retry_after`, and failed-job `last_error` fields when a
scan row is not yet complete. It also exposes additive owner-scoped
`complimentary_state` (`held`, `consumed`, `released`, or null) through one
bulk service RPC. RLS allows owners to read their own job rows;
service-role writers own mutation, and the claim RPC is executable only by
`service_role`.

Migration `20260715153946_reduce_identification_latency_round_trips.sql` adds
`public.begin_scan_ingestion(...)`. It performs upload-session lookup, job
claim, sanitized intent upsert, and the `ai_inference_started` stage transition
in one transaction. All four current scan-producing routes call it before
provider dispatch. Migration
`20260728035237_harden_dwca_downloads_and_scan_finalization.sql` makes it take a
transaction-scoped advisory lock derived from the scan UUID; atomic owner-row
recovery and the compatibility `claim_scan_ingestion_job(...)` routine take the
same lock. The compatibility claim is retained for rolling-deployment callers;
current compatibility routes do not split the job and intent writes. Scan UUID
text is normalized before storage and leases are bounded to one hour. After
resolving upload sessions, it canonicalizes the manifest and sanitized-payload
checksums against the exact stored JSON and returns those checksums with the
recovered upload-session ids, stage, and `already_complete`. The TypeScript
boundary validates every returned UUID, SHA-256 value, stage, and completion
flag. A malformed/error response fails closed before provider work and the route
refunds unused quota. The function validates and casts the text scan id to UUID
before querying UUID-backed media rows. Execute is revoked from `PUBLIC`,
`anon`, and `authenticated`; only `service_role` may call it.

Migration `20260728220000_persist_idempotent_scan_responses.sql` adds
`complete_scan_ingestion_finalization_with_response(...)`. The service-only
wrapper calls the existing scan/media finalizer and immutably stores the
validated envelope in the same transaction only after the owner row and complete
ledger boundary exist. The old finalizer remains available for rolling Edge
deployment compatibility. Owner deletion intake clears the response immediately
through a trigger on `internal.scan_deletion_tombstones`; owner change or final
row deletion clears it defensively through a separate `public.scans` trigger.

Migration `20260728230000_recover_inline_scan_ingestion_completions.sql` adds
service-only `recover_inline_scan_ingestion_completion(scan_id, user_id)`. It
repairs only an already-owned post-insert generation stranded by a historical
inline filename hint. Under the canonical scan-generation lock, it proves the
exact owner/job/intent/redaction/asset/upload-session/canonical-URL topology.
Redacted inline counts distinguish an unused hint from a genuine queued source:
an inline hint must have no capture row, while every real staged
image/audio/video key must have exactly one compatible owner row and
filename-matched canonical URL. Only rows already marked
`superseded_staging_registration` may be ignored. The routine recomputes both
checksummed ledgers and invokes the unchanged canonical finalizer atomically; it
does not dispatch a provider, alter committed quota, or weaken media
completeness.

Migration `20260728233000_recover_identity_merge_interrupted_scans.sql` installs
a pre-reparent scan fence in the current catalog definition of
`internal.perform_ghost_profile_merge(...)`. Private
`prepare_scan_ingestions_for_identity_merge(source, target)` visits unfinished
source generations deterministically, retires ambiguous source staging, refunds
only an unused reservation, preserves committed provider usage as failed, and
records `identity_merge_interrupted` before policy-driven ownership transfer can
delete the source profile. The migration aborts if it cannot install that call
at the exact expected catalog marker.

The same migration adds service-only
`recover_stranded_scan_ingestion_attempt(scan_id, user_id)`. It can make a
scanless retry coherent only when the exact target owner, completed merge
handoff, endpoint/quota operation, reservation, job, lease, tombstone, existing
scan, and staged-media topology agree. Its bounded outcomes are used internally
to distinguish already durable state, fresh media restaging, quota retry, and
not-applicable/deleted state; it never returns source identity through the
status API or reopens committed provider usage.

Migration `20260729012153_fix_video_scan_canonical_finalization.sql` adds
private `internal.scan_canonical_media_projection_complete(scan_id UUID)`. It is
a stable `SECURITY INVOKER` SQL validator with an empty search path and no
API-role execute grant. It projects the exact canonical media set refreshed for
the scan:

- valid image/playback references in nonempty structured `captured_media`, or
  the legacy standalone image prefix plus every video URL when no structured
  visual is usable;
- legacy standalone image count is
  `max(clean image URLs - clean video URLs × 5, 0)` for video rows and every
  clean image URL for image-only rows; and
- standalone audio references from both structured media and the compatibility
  audio array.

The function requires projected image/video counts to equal the exact job's
endpoint-normalized standalone-image count and validated `video_count`. Native
`identify-multimodal` counts already exclude video frames; the three
compatibility endpoints include them in `image_count`, so the validator
subtracts their separately validated `video_inference_frame_count`. Unknown
endpoint and malformed or impossible counts fail closed. It then returns true
only when every projected tuple has a `scan_media_assets` row matching scan id,
scan owner, kind, URL, and `status = ready`; a missing scan/job returns false.
The service-only finalizer calls it after `refresh_scan_media_assets`. Its
previous all-image-array check was incorrect for inference-only video frames.

The migration also adds private
`internal.scan_media_reference_is_video_inference_frame(scan_id UUID, user_id
UUID, url TEXT)`.
It permits a promoted image capture to omit a standalone ready image only when
the exact owner/job row declares a positive numeric video-frame count, its
endpoint-normalized image count equals the projected standalone-image count, the
complete classified-frame set has exactly the declared count, the URL occurs in
the scan's compatibility image array, and the URL is outside the structured
canonical image set for a proven video or inside the exact legacy frame suffix.
Both validators are stable security invokers with empty search paths and no
API-role execute grants.

The forward migration rewrites exactly two catalog fragments and leaves the
finalizer's manifest proof, captured-promotion requirement for every non-frame
item, completion fence, and complete-last invariants intact.

Migration `20260728035237_harden_dwca_downloads_and_scan_finalization.sql` also
adds `recover_missing_owned_scan(...)`, which validates the bounded non-media
DTO and writes the owner scan plus a `client_recovery_complete` ledger in one
locked transaction. Existing active, retryable, policy, unknown, and legacy
terminal states return `deferred`; explicit `replay_exhausted` is recoverable.
Forward migration `20260729173000_recover_media_abandoned_owned_scans.sql` also
admits exact `media_reconciliation_abandoned` as a candidate when an
owner/scan-matching `failed_scan_ingestions` row proves the service reached
post-result finalization. Follow-up migration
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql` additionally
requires a dead letter no earlier than the latest charged exact normal/replay
attempt, no reserved attempt or invalid timestamp lineage, and no
moderation-rejected or moderation-pipeline-failed capture row. Modern evidence
must bind exact quota identity, validated provider output, and completed safety
evaluation. Legacy unstructured evidence must belong to the immutable exact-ID
snapshot taken by the migration, predate the private rollout cutoff, and either
follow a failed latest authority or match the vulnerable producer’s first
committed normal attempt with no charged replay. It must also match the audited
multimodal post-safety error lineage, excluding the known pre-safety
user-prerequisite and moderation failure messages. The exact-ID snapshot
prevents a lock-blocked post-migration insert from gaining legacy authority
through its backdated transaction timestamp. The chronological indexes keep
this proof bounded as dead-letter history grows. Unproven abandonment remains
deferred. A recovery-first winner makes the next ingestion claim return
`already_complete` before a provider call.

`internal.scan_deletion_tombstones` closes the opposite lifecycle boundary.
`request_scan_deletion(...)` writes this private, content-free owner/UUID fence
before R2 erasure and terminal-marks noncomplete ingestion. Scan mutation,
claim, finalization, replay, and recovery reject a tombstoned UUID;
`complete_scan_deletion(...)` removes the owner row only after storage cleanup
and records completion without deleting the tombstone. Pending rows carry
bounded lease/retry state (`attempt_count`, `next_attempt_at`, `claim_token`,
`lease_expires_at`, and `last_error_code`) for the independent
`reconcile-scan-deletions` worker. `claim_scan_deletion_jobs(...)` uses
oldest-due `FOR UPDATE SKIP LOCKED` leases; `release_scan_deletion_job(...)`
compare-before-releases a failed generation; and `get_scan_deletion_health()`
returns only aggregate SLA/backlog state. Successful completion immediately
nulls the owner UUID, retaining no observation content or user linkage. Account
detachment applies the same unlink-and-complete transition to any interrupted
individual deletion. Thus a completed ledger cannot be used by a stale device to
recreate a deliberately deleted scan.

`complete_scan_ingestion_finalization(...)` is the canonical completion
boundary. It locks the ledger and scan, verifies that the submitted dispositions
belong to the claimed object-key manifest, permits deletion only for claimed
audio, transitions staged capture rows idempotently, rebuilds canonical media,
and proves every promoted capture URL has a matching ready image/video/audio
row. It then writes `media_finalization_complete` last. `identify-multimodal`,
server replay, media reconciliation, and all three compatibility scan-producing
routes cannot directly mark a nonterminal ledger complete. Storage deletion
dispositions are submitted only after R2 confirms 2xx or idempotent 404; every
other response preserves noncomplete state. Compatibility finalization failures
are explicitly moved to `failed_retryable / media_finalization_failed` and
propagated through the required task. A fresh provider-owning multimodal
invocation returns retryable 503 when this boundary fails. Its later same-UUID
retry may return a marked reconstructed response from the exact owner scan while
the ledger remains noncomplete; canonical reconciliation still finishes through
this finalizer without another provider call. A compatibility orchestrator may
also return its validated result immediately after a finalizer failure, but only
when the exact owner scan row has already committed.

Catalog trigger `enforce_scan_ingestion_completion_fence` makes completion-last
a database invariant rather than an Edge convention. The recovery and
finalization routines set a transaction-local value containing the exact owner
UUID and normalized scan UUID immediately before their `complete` write. Direct
service-key completion, reopening a completed row, or changing its scan identity
raises SQLSTATE `55000`. A completed owner may change only inside the atomic
ghost-profile merge transaction when its existing exact source, target, and
enabled reparent markers all match `OLD.user_id` and `NEW.user_id`; this
preserves catalog-driven foreign-key reparenting without creating a general
authorization bypass.

The media reconciliation worker also feeds back into this ledger. If a stale
capture-upload row still belongs to an active or future-retry job, the worker
leaves the media pending. If a surviving staged playback video repairs an
existing scan and satisfies the job's required video count, the job is marked
`complete` only through the same locked finalization verifier. If media is
abandoned after the TTL without a scan row, the job is marked `failed_terminal`
with a reconciliation stage for operator review.

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
- `payload_checksum` (TEXT): SHA-256 checksum of the exact sanitized replay
  payload after server-side upload-session resolution, used to detect
  request-intent drift separately from the media manifest.
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

### Identification dictionary hydration RPC

Migration `20260715153946_reduce_identification_latency_round_trips.sql` also
adds `public.hydrate_identification_dictionary(...)`. One service-role call
returns a JSON object containing:

- `primary`: the cached primary `species_dictionary` row, or `null`.
- `candidate_common_names`: a scientific-name-to-English-common-name object for
  cached candidate rows.

Blank primary names and empty candidate arrays are valid. Like the ingestion
setup RPC, execute is revoked from `PUBLIC`, `anon`, and `authenticated` and
granted only to `service_role`. Cache-miss external enrichment is not performed
inside this SQL function.

### `scan_deferred_context_updates`

Owner-scoped staging for WeatherKit/geocoding data that arrives after inference
has started but before `public.scans` is inserted. Added in migration
`20260715153946_reduce_identification_latency_round_trips.sql`.

- `user_id` (UUID) and `scan_id` (UUID): Composite primary key. `user_id`
  intentionally has no foreign key to `public.users`, because a first anonymous
  scan can be claimed before background ghost-user creation completes.
- `context` (JSONB): JSON object populated by the Edge endpoint with normalized
  deferred fields accepted by `/update-scan-context`: `gps_elevation`,
  `weather_temperature_f`, `weather_condition`, and `semantic_location`.
- `created_at` / `updated_at` (TIMESTAMPTZ): Initial and most recent staged
  update. `idx_scan_deferred_context_updates_created` supports bounded stale row
  inspection or cleanup.

RLS is enabled with no client policy, and direct table privileges are revoked
from `PUBLIC`, `anon`, and `authenticated`. `service_role` receives only the
table access required by the Edge RPC.

`public.apply_or_stage_scan_context(p_scan_id, p_user_id, p_context)` updates
the matching owner scan when it already exists. Otherwise it requires a matching
owner `scan_ingestion_jobs` row and upserts the staged context. The
service-role- only function returns `true` for an immediate scan update and
`false` for a staged update. A `BEFORE INSERT` trigger on `public.scans` merges
any staged context into the new owner row and deletes the staging record in the
same transaction. Late context never initiates AI inference or changes ingestion
job ownership.

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
- `moderated_at` (TIMESTAMPTZ, nullable): Reversible internal-admin hide marker.
  Every public feed, map, profile, detail, notification, and web projection
  requires this value to be `NULL`.
- `moderated_by_user_id` (UUID FK → `auth.users.id`, nullable): Admin Auth user
  who most recently hid the post. Restore clears this together with
  `moderated_at`.
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
- `media_health_status` (TEXT): System-owned aggregate: `healthy`, `degraded`,
  or `quarantined`. It never overwrites `unshared_at` or `moderated_at`.
- `missing_media_count` / `total_media_count` (INT): Trigger-maintained media
  health counts.
- `media_health_updated_at` / `media_quarantined_at` / `media_last_recovered_at`
  (TIMESTAMPTZ, nullable where applicable): Incident and automatic-recovery
  audit timestamps.

**Post media rule**: Explore no longer reads media directly from
`scans.image_storage_urls` at response time. Sharing snapshots safe public image
and video URLs into `explore_post_media`, while `hero_image_url` remains the
backward-compatible cover thumbnail on `explore_posts`. If the scan is
tombstoned, unshared, auto-purged, or moderated unsafe, existing lifecycle rules
remove or hide it. Unexpected object loss does not delete or unpublish it:
confirmed-missing items are omitted and an all-missing post is reversibly
quarantined while engagement remains. Scan geoprivacy no longer hides the post
itself; post-level `location_sharing` controls public location output.
Share-state reads also require at least one usable `explore_post_media` row
before returning a post as feed-visible. Migration
`20260729024157_atomic_explore_scan_publication.sql` goes further for initial
publication: service-role-only invoker RPC
`publish_scan_to_explore_atomically(...)` revalidates and locks the exact owner
scan, then commits the post metadata, complete media snapshot, hashtags, and
resolved-community publication state together. An existing community request is
locked before its scan, matching the helper’s request-to-scan order and
preventing a publication/consensus deadlock cycle. An omitted post privacy
choice is resolved from the scan after that lock, so a concurrent geoprivacy
change cannot leave a stale default. Any late failure restores the previous post
and media snapshot rather than relying on read-time hiding of a partial write.

Ask the Community creation uses the companion forward migration
`20260729033000_atomic_community_identification_requests.sql`. Its service-only
invoker RPC calls the validated publication boundary and creates or reopens the
`needs_id` request in the same PostgreSQL transaction, so failed taxonomy,
projection, or request state cannot leave a normal post visible. A
`BEFORE UPDATE OF shared_at` trigger rechecks committed `needs_id` state at the
actual post write and closes the absent-request concurrency race.

Because these two RPCs are `SECURITY INVOKER`, their execution allowlist alone
is not enough under the hardened public-schema defaults. Migration
`20260729044500_grant_atomic_explore_service_privileges.sql` grants
`service_role` only the operation classes actually used on `scans`,
`taxon_nodes`, `species_dictionary`, `explore_posts`,
`explore_community_requests`, `explore_post_media`, `explore_post_hashtags`,
`explore_identifications`, and `community_consensus_jobs`. It grants no
browser-role writes and no `ALL`, `TRUNCATE`, `REFERENCES`, `TRIGGER`, or
`MAINTAIN` capability.

### `scan_media_assets`

Normalized scan media lifecycle assets. Added in migration
`20260705100000_add_scan_media_assets.sql`. Migration
`20260706100000_allow_staged_scan_media_without_scan_id.sql` repairs early
deployed tables by dropping any lingering `NOT NULL` requirement from `scan_id`.
Migration `20260707020956_allow_staged_scan_media_without_url.sql` does the same
for `url`, because staged upload rows exist before a public media URL is
available. Migration
`20260706193954_fix_scan_media_refresh_image_url_ambiguity.sql` replaces the
refresh helper after an early deployment exposed an ambiguous PL/pgSQL
`image_url` reference in the legacy-array fallback path. Migration
`20260707041259_fix_video_has_audio_metadata.sql` corrects video `has_audio`
derivation so generated media rows and Explore snapshots only mark audio when a
captured-media video audio reference exists. Migration
`20260710120000_add_explore_audio_moderation.sql` adds durable standalone-audio
URLs and permits approved audio snapshots in Explore post media. Migration
`20260711055524_add_explore_audio_moderation_attestations.sql` adds the
service-only `explore_audio_moderation_attestations` cache. Its composite key is
`(checksum_sha256, policy_version, model)`, so unchanged bytes can reuse a
decision while policy/model upgrades automatically require re-moderation. It
stores no transcript, URL, filename, user identity, or media bytes; RLS is
enabled and client roles have no table grants. Migration
`20260711143348_repair_scan_media_assets_audio_constraints.sql` repairs early
production tables whose existing `kind`, `role`, kind/role, ready URL, and
ready-order index definitions predated standalone audio. This explicit
replacement is required because the original `CREATE TABLE IF NOT EXISTS`
migration cannot alter constraints on an already-existing table. Migration
`20260720230648_repair_scan_media_asset_uniqueness.sql` removes an early global
`UNIQUE (scan_id, order_index)` constraint that prevented promoted
capture-upload lifecycle rows from coexisting with generated ready rows. It
restores the intended partial unique indexes: generated rows are unique by
`(scan_id, source, role, order_index)` within `scan_refresh`/`backfill`, and
staged upload rows are unique by `(upload_session_id, order_index)` when the
session exists.

Migration `20260728231000_make_staged_scan_media_registration_idempotent.sql`
repairs signing-response retry duplicates without deleting their audit evidence.
For each owner/client-scan/storage-key lifecycle identity it keeps one canonical
row and marks extras failed with
`failure_reason = superseded_staging_registration` plus bounded prior-state
metadata. Partial unique index `idx_scan_media_assets_active_staging_key_unique`
then permits at most one active staged `capture_upload` row for that identity.

Identical-key uniqueness alone cannot constrain two concurrent signing requests
that add different keys to the same scan. BEFORE INSERT/UPDATE trigger
`enforce_staged_scan_media_budget` therefore takes an owner-scoped transaction
advisory lock and rejects a seventh active staged source with SQLSTATE `54000`.
Requested signing subsets remain composable with existing unrequested rows, but
their combined active staged capture-key set cannot exceed six. Historical
promoted rows remain audit evidence and do not consume this trigger budget.

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
- `kind` (TEXT): `image`, `video`, or `audio`. Standalone audio can be durable
  user media; extracted `video_audio` remains inference-only.
- `role` (TEXT): Lifecycle role. Current user-visible rows use `display` for
  still images, `playback` for playable video clips, and `audio` for standalone
  clips; reserved roles include `thumbnail` and `inference_frame`.
- `status` (TEXT): Lifecycle state: `staged`, `promoted`, `processing`, `ready`,
  `failed`, or `deleted`. Explore/composer/status readers only surface `ready`
  rows whose role is `display`, `playback`, or `audio`.
- `source` (TEXT): Writer that created the row, such as `scan_refresh`,
  `capture_upload`, `repair`, `backfill`, or `manual`.
- `url` (TEXT, nullable): Current public CDN URL. Required for ready
  display/playback rows; staged and failed rows may only have `storage_key` or
  diagnostics.
- `storage_key` (TEXT, nullable): Durable storage object key when known.
  Legacy/backfilled rows may only have a public URL.
- `thumbnail_url` (TEXT, nullable): Public image thumbnail for compact previews,
  video poster frames, and reusable standalone-audio spectrogram artwork.
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
`media_images.raw_image_url` and `media_videos.raw_video_url`; avoid unqualified
names that match PL/pgSQL variables, because scan inserts execute this helper
through the `scans` trigger. A trigger keeps generated rows synchronized after
scan media inserts, updates, and deletes; Edge write paths also make best-effort
refresh RPC calls after critical scan inserts and video-repair updates, but
existing manifest/array fallbacks remain available if refresh fails. RLS lets
owners read their lifecycle rows; public open-scan reads are limited to ready
display/playback rows so staged/failed diagnostics stay private. The refresh
helpers are service-role-only RPC surfaces; app roles should read
`scan_media_assets`, not call refresh functions directly.

`/generate-upload-urls` creates `capture_upload` rows with `status = 'staged'`
when structured scan uploads include `clientScanId` and `mediaRole`.
Capture-upload rows must keep a client scan id and storage key; promoted
capture-upload rows must also have a final `scan_id` and public URL.
`identify-multimodal` links those rows to `scan_id` during finalization:
promoted image/video/standalone-audio rows become durable media, while extracted
video-audio rows become `deleted`; failed moderation/promotion/insert paths mark
remaining staged rows as `failed`. The scheduled `reconcile-scan-media-assets`
worker revisits old staged rows: existing scan rows can be repaired from
surviving staged playback videos, while abandoned upload sessions are failed and
garbage collected after their TTL. A generated row and its promoted
capture-upload audit row may share the same scan position; consumers should
select by lifecycle source/status rather than assuming `(scan_id, order_index)`
identifies one row.

Migration `20260726041338_repair_owned_scan_image_references.sql` adds
service-only
`public.repair_owned_scan_image_reference(user_id, source_url,
replacement_url)`.
After the Edge layer verifies R2 state, one transaction replaces only the exact
missing URL across:

- active owned `scans.image_storage_urls`;
- recursively nested string values in `scans.captured_media`;
- owner-scoped `scan_media_assets.url` and `thumbnail_url`, including the new
  durable `storage_key` and repair metadata; and
- `explore_post_media.url` and `thumbnail_url` for posts owned by the same user.

The RPC rejects invalid/non-canonical URLs, replacement keys outside the owner's
durable free/Pro prefixes, and sources with no owned scan or Explore reference.
It calls `internal.require_service_role()`, has an empty search path, and grants
execution only through the central service-role routine allowlist. The
owner-authenticated `/repair-scan-image` function is the only app-facing caller;
clients cannot invoke this RPC directly.

The Edge persistence adapter treats the RPC response as remote evidence, not
transaction truth. If the response is lost or malformed it rereads exact active
owner references for source and replacement. Source-absent plus
replacement-present proves commit. Deletion of the promoted replacement is
authorized only by a returned rejection plus source-present and
replacement-absent evidence. An unreadable or contradictory topology preserves
the object and returns retryable `scan_image_repair_persistence_unknown`.

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
- `kind` (TEXT): `image`, `video`, or `audio`.
- `url` (TEXT): Public CDN URL for the image, playback video, or standalone
  audio object.
- `thumbnail_url` (TEXT, nullable): Public image thumbnail for video playback,
  compact previews, or a standalone-audio spectrogram. Video posts require a
  thumbnail when shared. Approved WAV shares generate a deterministic PNG in the
  recording's durable `public_uploads/{tier}/{userId}/` directory and copy that
  URL into both the post snapshot and matching scan media asset.
- `order_index` (INT): Stable carousel ordering within the post.
- `duration_seconds` (DOUBLE PRECISION, nullable): Reserved for video playback
  or audio metadata.
- `has_audio` (BOOLEAN): Whether the video has a persisted audio companion.
  Public playback starts muted; audio requires explicit viewer action. Snapshot
  writers copy this from ready media rows or from the `captured_media` video
  audio reference; legacy URL-array video sources default false.
- `health_status` (TEXT): `healthy`, `suspected_missing`, or `missing`.
  `missing` requires two service-recorded direct R2-origin `404` observations at
  least five minutes apart.
- `health_checked_at`, `missing_first_observed_at`, `missing_confirmed_at`,
  `recovered_at` (TIMESTAMPTZ, nullable): Origin-check lifecycle evidence.
- `consecutive_missing_checks` (INT): Bounded non-negative observation count.
- `next_health_check_at` (TIMESTAMPTZ): Indexed due time for the service lease
  queue.
- `last_health_http_status` / `last_thumbnail_health_http_status` (INT,
  nullable): Last direct primary and auxiliary-object response. A thumbnail
  `404` removes the poster from public JSON but does not hide a playable primary
  media object.
- `created_at` / `updated_at` (TIMESTAMPTZ): Snapshot lifecycle timestamps.

`public.explore_post_media_items(post_id)` returns ordered media JSON for feed,
detail, author, hashtag, map, and Community ID read paths, excluding only
confirmed-missing primary objects and confirmed-missing auxiliary thumbnails.
Map, widget, profile grid, and compact surfaces normally use `hero_image_url`.
The author-post RPC also projects `reference_thumbnail_url` from
normalized/legacy species imagery; iOS profile and other compact Explore grids
prefer it for audio-backed posts and add a waveform badge. Feed/detail playback
remains media-item-driven. In-app compact previews add a play indicator for
video, while Home Screen widgets intentionally show clean still thumbnails
without a video badge. Scan media source resolution prefers ready
display/playback/audio `scan_media_assets` rows, then `captured_media`, and
finally legacy URL arrays so playback video URLs and poster thumbnails remain
paired. Audio approval is checked before the Explore post/media write, so the
database contains no pending audio post. The final post/media/hashtag write is
one owner-checked transaction, so successful rows are normal shared posts and
rejected/failed attempts restore prior public state. Spectrogram generation is
deliberately non-blocking after approval: unsupported legacy codecs or thumbnail
failures keep the audio post playable with its existing fallback instead of
weakening moderation or blocking publication.
`backfill-explore-audio-spectrograms` repairs blank historical WAV thumbnails in
bounded service-role-only batches.

Generated spectrogram objects remain scan-owned lifecycle media even though the
post snapshot also references them. `delete-scan` reads thumbnail URLs from both
`scan_media_assets` and linked `explore_post_media` before cascade deletion,
deduplicates them with source media, and deletes only approved
`public_uploads/free/` or `public_uploads/pro/` R2 keys. This prevents a partial
thumbnail-row update from orphaning the deterministic PNG.

### Explore media-health internals and reconciliation audit

Migration `20260726144754_implement_explore_media_quarantine_state_machine.sql`
adds:

- `internal.explore_media_health_check_claims`: private short leases keyed by
  media row and UUID claim token. API roles have no direct table privileges.
- `internal.explore_media_health_history`: private continuity rows keyed by
  `(post_id, kind, url)`. Before-delete and before-insert triggers preserve
  health when `refresh_explore_post_media` rebuilds a snapshot.
- `public.explore_media_health_reconciliation_runs`: service-written audit rows
  with run status, claimed/healthy/missing/retryable/error counts, timestamps,
  and bounded structured errors.

Service-only RPCs:

- `claim_explore_media_health_checks(limit, lease_seconds)` leases due media
  from active posts with `FOR UPDATE SKIP LOCKED`.
- `record_explore_media_health_check(media_id, claim_token, outcome, ...)`
  validates the live lease and applies the health state machine.
- `expedite_explore_media_health_checks(object_keys)` accepts authenticated R2
  event hints and makes matching rows due without treating the event as proof.

`get_owned_explore_media_incidents(self_id)` is executable by authenticated and
service roles, but its definer body requires `auth.uid() = self_id` for ordinary
callers. It returns only the owner's active degraded/quarantined posts. The Edge
boundary derives `self_id` from the verified JWT.

Migration `20260726174555_align_explore_author_publication_contract.sql` adds:

- `get_owned_explore_publication_summary(self_id)`: owner-only preserved
  publication intent, canonical visible count, and active degraded/quarantined
  recovery totals; and
- `get_explore_publication_health_summary()`: service-only aggregate active,
  healthy, degraded, quarantined, affected-author, and missing-item totals
  without owner identifiers or object keys.

The same migration moves the author-profile visible count onto
`explore_projected_post_cards(self_id)`, matching preview and grid visibility.

Migration `20260729120000_align_explore_share_state_media_health.sql` aligns
`get_scan_explore_share_state(self_id, target_scan_id)` with that canonical
projection. It preserves the active post UUID and share timestamp for owner
recovery while returning `is_explore_feed_visible = false` for moderated,
quarantined, or all-missing-media posts. A degraded post remains visible when at
least one non-missing item survives. The routine remains owner-scoped,
`SECURITY INVOKER`, and service-role-only; `PUBLIC`, `anon`, and `authenticated`
cannot invoke it with a substituted `self_id`. The JWT-authenticated Edge
wrapper supplies the owner identity. The read does not change publication,
moderation, health, or engagement state.

`internal.refresh_explore_post_media_health` maintains aggregate post state. Its
triggers create one `media_missing` notification when an incident begins,
replace it with `media_restored` after full recovery, and preserve author,
moderation, and engagement state.

The full visibility, recovery, security, and operations contract is
[Explore Media Health and Quarantine](./12-explore-media-health-and-quarantine.md).

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

### `explore_comment_mentions`

Durable identity edges for resolved `@username` tokens in Explore comment and
reply bodies. Added in migration
`20260615100000_add_explore_comment_mentions.sql`; the snapshot constraint is
separated from the current profile policy by
`20260808144244_expand_reserved_public_username_policy.sql`.

- `comment_id` (UUID FK → `explore_post_comments.id`, CASCADE DELETE): The
  immutable plain-text body containing the token.
- `mentioned_user_id` (UUID FK → `users.id`, CASCADE DELETE): Durable profile
  and notification target.
- `mention_username` (TEXT): Historical lowercase token copied from the
  mentioned user's valid current handle when the comment is created. It remains
  unchanged if that user later renames their handle or the token later becomes
  reserved.
- `created_at` (TIMESTAMPTZ): Resolution time.
- Composite primary key: `(comment_id, mentioned_user_id)` deduplicates repeated
  tokens for the same user in one comment.

`explore_comment_mentions_username_valid_check` is intentionally structural:
the token must be 3–24 lowercase ASCII username characters, start with a letter,
end with an alphanumeric character, and contain no repeated underscore. It does
not call `is_valid_public_username(...)`, because that function includes the
current reservation list and PostgreSQL does not rewrite the immutable comment
body when policy changes. Current profile handles remain policy-aware through
`users_public_username_valid_check`, so the resolver cannot create a new mention
for a currently reserved handle.

The table has RLS enabled and its direct SELECT policy is deny-all. Comment
creation resolves eligible current handles through
`insert_explore_comment_mentions_from_body(...)`; comment/reply projections
return `mention_username` for span matching, `mentioned_user_id` for routing,
and the current public display name/avatar from `users`. A username-policy
migration must never rewrite only `mention_username`, because that would
desynchronize tappable metadata from the plain-text `@token` in `body`.

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
- Migration `20260727190637_secure_explore_comment_reactions_and_defaults.sql`
  enables RLS with no direct client policy, revokes every table privilege from
  `PUBLIC`, `anon`, `authenticated`, and `service_role`, then grants
  `service_role` only `SELECT`, `INSERT`, and `DELETE`. Authenticated clients
  mutate reactions only through the ownership-validating Edge action's
  privileged SDK client.
- The same corrective migration removes unsafe global and `public`-schema
  default table/sequence privileges for the `postgres` migration role, including
  PostgreSQL 17 `MAINTAIN`. Future objects require an explicit, reviewed grant.

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
- Partial unique indexes on `(user_id, post_id, type)` for `media_missing` and
  `media_restored` guarantee one lifecycle row per owner/post/type.
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
  increased. It dispatches `media_missing` on incident insertion and
  intentionally skips `type IN ('follow', 'media_restored')`.

### `user_push_devices`

Remote push device registry for Explore activity delivery. Added in migration
`20260427010002_add_explore_push_delivery.sql`.

- `id` (UUID): Primary key.
- `user_id` (UUID FK → `users.id`, CASCADE DELETE): Owning Merian user.
- `device_token` (TEXT): Lowercase APNs token, unique per
  `(device_token, platform, environment)`. Migration
  `20260720174209_fix_push_device_token_constraint.sql` validates the 32...512
  character length separately from the hex-only regex. Do not combine that range
  into a PostgreSQL `{32,512}` regex bound: PostgreSQL rejects repetition bounds
  above 255 and registration fails before the row is written. The active
  validated constraints are `user_push_devices_device_token_format_check` and
  `user_push_devices_device_token_length_check`.
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
  rows with public author identity, canonical `hero_image_url`, the compact
  `reference_thumbnail_url`, ordered `media_items`, coarse location, optional
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
- `public.get_explore_feed_nearby(self_id UUID, viewer_latitude DOUBLE PRECISION, viewer_longitude DOUBLE PRECISION, max_limit INTEGER, before_shared_at TIMESTAMPTZ, before_post_id UUID, nearby_radius_miles DOUBLE PRECISION, requested_species_categories TEXT[], requested_media_types TEXT[], shared_since TIMESTAMPTZ)`:
  The shipped `nearby` feed projection. It reads `explore_posts.public_latitude`
  / `public_longitude`, which are populated only from the post's saved
  `location_sharing` and the protected-species / uncertainty safety rules.
  Non-owned posts therefore need post-level `location_sharing = 'open'` and a
  stored public coordinate to match the radius query; `obscured` and `private`
  posts remain visible in non-spatial Explore feeds but cannot be discovered by
  Nearby. The RPC filters matches to the requested 1–100-mile radius (50 miles
  by default), then sorts surviving rows by `(shared_at DESC, post_id DESC)`.
  Species, media, and shared-date filters run before ordering and `LIMIT`, as
  they do in the other three feed RPCs. This keeps the client feed feeling like
  Explore rather than a pure nearest-neighbor list while preserving the same
  coordinate boundary used by the map.
- `public.get_explore_post(self_id UUID, target_post_id UUID)`: Returns the same
  public card projection for a single post, including canonical ordered
  `media_items`. This is used by native routing so video/audio playback does not
  query private scan tables or depend on an already-loaded feed row.
- `public.get_explore_post_detail(self_id UUID, target_post_id UUID)`: Returns a
  single public species-detail projection for the Explore detail page. Fields
  currently include `field_notes`, `species_dictionary_id`,
  `alternative_common_names`, taxonomy ranks (`kingdom`, `phylum`, `class`,
  `order`, `family`, `genus`), public `ai_reasoning` unless the user has
  overridden the AI identification (report flags do not suppress it),
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
- `public.get_public_web_explore_posts(target_post_id UUID, max_limit INTEGER)`:
  Service-only, fixed-anonymous web projection over
  `explore_projected_post_cards(NULL)`. It returns one post or a
  reverse-chronological page of at most 48 cards, includes copied public
  username/Pro state, and forces engagement counts to zero plus viewer/ownership
  flags to false. It is revoked from `PUBLIC`, `anon`, and `authenticated`.
- `public.get_public_web_explore_post_detail(target_post_id UUID)`:
  Service-only, fixed-anonymous wrapper over
  `get_explore_post_detail(NULL, target_post_id)` that independently inner-joins
  `explore_projected_post_cards(NULL)`. It returns no detail unless canonical
  anonymous moderation/publication/media-health visibility also exists.
- `public.get_public_web_explore_post_page(target_post_id UUID)`: Service-only
  atomic page projection returning canonical `post_payload` and independently
  gated `detail_payload` from one statement/MVCC snapshot. It is the only
  Explore database read used for a Next.js detail page; browser roles remain
  denied and receive no source-relation grants.
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
- `public.publish_scan_to_explore_atomically(p_scan_id UUID, p_user_id UUID, p_species_common_name TEXT, p_field_notes TEXT, p_location_sharing TEXT, p_media_rows JSONB, p_hashtags TEXT[])`:
  Service-role-only `SECURITY INVOKER` final-publication boundary. It locks an
  existing community request before its exact owned, non-tombstoned biological
  scan; validates bounded media, contiguous order, hashtags, and source-array
  membership; resolves an omitted location choice from the locked scan; then
  replaces post metadata, media, hashtags, and resolved-community publication
  state in one statement transaction. `PUBLIC`, `anon`, and `authenticated`
  cannot execute it. Any error rolls the prior complete post snapshot back.
- `public.request_community_identification_atomically(p_scan_id UUID, p_user_id UUID, p_note TEXT, p_location_sharing TEXT, p_species_common_name TEXT, p_media_rows JSONB, p_initial_taxon_node_id UUID, p_taxonomy_version_id UUID)`:
  Service-role-only `SECURITY INVOKER` Ask the Community boundary. It preserves
  request-before-scan lock order, verifies the initial taxon belongs to the
  locked owner scan and pinned version, commits one complete Explore media
  snapshot and `needs_id` request, and returns the authoritative request row.
  Reopening withdrawn state clears stale publication/consensus/worker state and
  withdraws old active votes without deleting their audit rows. Forward
  migration `20260729044500_grant_atomic_explore_service_privileges.sql`
  supplies the narrow relational privileges needed by this routine and the
  companion publication routine without changing either to definer rights.
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
  only profile-visible accounts can be followed. Automatic profile-visible
  Backyard Safari enrollment means a known account ID normally passes this
  gate until the unfinished starter is stopped or reset; no endpoint enumerates
  account IDs.
- `public.get_user_follow_state(self_id UUID, target_author_user_id UUID)`:
  Returns `author_user_id`, aggregate `follower_count`, aggregate
  `following_count`, and requester-specific `viewer_is_following`. Counts ignore
  shadowbanned counterpart users and do not expose identities.
- `public.get_explore_author_profile(self_id UUID, target_author_user_id UUID, preview_limit INTEGER)`:
  Returns another author's public profile row only when the target has at least
  one currently visible Explore post or visible Field trip profile surface for
  the requester. The owner may retrieve their own row with zero visible posts so
  recovery status can be presented. It emits public author identity, species
  count, current streak, 52-week heatmap JSON, achievement-progress JSON,
  canonical visible published post count, follower/following counts, requester
  follow state, up to `preview_limit` preview posts, and Field trip summaries.
  Aggregate scan stats are computed from all non-tombstoned scans; follow counts
  are computed from `user_follows`; count and preview both use
  `explore_projected_post_cards(self_id)` and never include unshared,
  tombstoned, media-less, system-quarantined, or non-species-backed posts.
  Backing-scan geoprivacy does not hide an explicitly shared post; the
  post-owned location setting controls public location output. Active Field trip
  summaries include checklist status only and never return scan IDs, media URLs,
  field notes, exact coordinates, public location labels, or private evidence.
  Achievement progress never returns qualifying scan IDs.
- `public.get_explore_author_posts(self_id UUID, target_author_user_id UUID, max_limit INTEGER, before_shared_at TIMESTAMPTZ, before_post_id UUID)`:
  Returns the author's currently visible published Explore posts for the full
  profile library. Rows share the same card projection as the feed, use the same
  visibility filters as `get_explore_author_profile.preview_posts`, and page
  stably on `(shared_at DESC, post_id DESC)`. Each row additionally includes
  nullable `reference_thumbnail_url`, resolved through
  `public_species_first_reference_image_url`, for nonvisual-media thumbnails.
- `public.get_owned_explore_publication_summary(self_id UUID)`: Owner-only
  totals separating active publication intent from canonical visible posts and
  active media recovery. Ordinary callers must have `auth.uid() = self_id`; the
  Edge function derives this ID from the verified session.
- `public.get_explore_publication_health_summary()`: Service-only aggregate
  publication/media-health scope used by deploy smoke tests and monitoring. It
  returns no owner identity or object key.
- `public.field_trip_templates`: Curated Field trip definitions with slug,
  title, region/season/habitat tags, difficulty, Pro/rotating-free access flags,
  active state, optional cover image, estimated duration, and curated guide
  sections.
- `public.field_trip_levels`: Sequential levels for a template. Levels unlock in
  `level_number` order.
- `public.field_trip_checklist_items`: Curated checklist prompts for each level.
  Items support species, scientific-name, taxonomy/group,
  taxonomy-with-one-excluded-family, taxonomy combined with
  ecology/habitat/semantic evidence, habitat/ecology, prompt-text matching, and
  optional curated item-level tips. `taxonomy_excluding_family` treats
  `taxonomy_family` as the excluded family while the remaining populated
  taxonomy ranks stay positive constraints. It was introduced to reject
  `Formicidae` (ants) from Park Pollinators before the active goal was narrowed
  further. `taxonomy_and_signal` requires at least one taxonomy rank, at least
  one ecology/habitat/semantic signal, and all populated constraints to match. A
  compound semantic signal can contain `|`-separated accepted alternatives;
  **Bee or wasp** uses `bee|wasp` together with order `Hymenoptera`. Structured
  guides may provide Where to look, Best conditions, What to notice, and Scan
  safely sections.
- `public.user_field_trips`: Per-user progress rows with start time, current
  level, profile visibility, completion time, and denormalized progress counts.
  Every account receives an active Backyard Safari Level 1 row at profile
  creation; the rollout backfills only accounts without prior state. The
  enrollment row uses the existing profile-visible status, so it can appear in
  the status-only public Field trip summary and satisfy author-profile
  visibility without exposing its private evidence.
- `public.user_field_trip_item_completions`: Idempotent item completion rows
  linking a Field trip item to the saved scan that completed it. Rows are
  written only for caller-owned scans whose capture timestamp belongs to an
  eligible persisted activity period. A unique
  `(user_field_trip_id, scan_id)` index limits the scan to one credit in that
  outing, while a scan-first `(scan_id, user_field_trip_id)` index supports
  Insight lookup. The same scan
  may still link to one item in several outings.
- `public.field_trip_scan_goal_preferences`: Private scan-keyed live-Capture
  preference with owner, standard outing, and checklist item IDs. It contains no
  media, coordinates, notes, or public evidence. RLS is enabled, all access is
  revoked from `PUBLIC`, `anon`, and `authenticated`, and only `service_role`
  may read or mutate it.
- `public.field_trip_scan_progress_receipts`: Private scan-keyed idempotency
  receipt for the last processed identification revision. It retains the
  validated preference IDs and the complete atomic progress/achievement result
  so post-ingestion retries can recover the original unlock payload after client
  termination. RLS is enabled and only `service_role` may access it.
- `public.field_trip_publications`: Published Field trip snapshot headers with
  user-editable title, optional description, optional AI summary, counts,
  author/template linkage, and optional profile pin position metadata capped at
  3 per author.
- `public.field_trip_publication_items`: Snapshot item rows for published pages.
  These can include species/taxonomy labels and selected snapshot media, but
  they do not make the underlying scans Explore posts.
- `public.field_trip_publication_likes`: Field trip publication likes, separate
  from `explore_post_likes`.
- `public.field_trip_publication_comments`: Field trip publication comments and
  one-level replies, separate from `explore_post_comments`.
- `public.field_trip_activity_notifications`: Field trip-only in-app activity
  rows for publication comments, replies, and followed-author publications.
  These rows are separate from `explore_post_notifications` and never trigger
  APNs, widgets, feed cards, map rows, or `explore_posts`. `type` is checked
  text (`field_trip_comment`, `field_trip_reply`, or
  `field_trip_followed_publication`) rather than a new
  `explore_notification_type` enum value, so the migration can deploy in one
  transaction while keeping Field trip activity separate from push-backed
  Explore notifications.
- `public.field_trip_challenges`: Curated/admin-created seasonal challenge
  definitions linked to a Field trip template. Rows store title, description,
  cover image, start/end timestamps, region/season/habitat tags, normalized
  suggested hashtags, access flags, active state, and sort order.
- `public.field_trip_challenge_participants`: Explicit per-user challenge joins
  with `joined_at`, linked `user_field_trip_id`, current level, completion time,
  badge timestamp, and private/profile visibility flags.
- `public.field_trip_challenge_item_completions`: Challenge-specific item
  completions keyed by participation and checklist item. Rows link to
  caller-owned scans made after `joined_at` and before the challenge `ends_at`;
  they do not retroactively satisfy normal Field trip progress. A unique
  `(participation_id, scan_id)` index limits the scan to one Event credit, with
  a scan-first lookup index for Insight contributions.
- `public.field_trip_challenge_badges`: Completion badge rows for
  non-competitive challenges. Profile-visible badges expose no scan IDs, media,
  exact locations, notes, or private evidence.
- `public.field_trip_challenge_entries`: Published challenge completion
  snapshots. These are distinct from `field_trip_publications` so repeat
  seasonal challenges on the same template do not overwrite normal Field trip
  publication history.
- `public.field_trip_challenge_entry_items`: Snapshot item rows for challenge
  entries, including species/taxonomy labels and selected snapshot media without
  creating Explore posts.
- `public.field_trip_challenge_entry_likes`: Challenge entry likes, separate
  from Explore post likes and normal Field trip publication likes.
- `public.field_trip_challenge_entry_comments`: Challenge entry comments and
  one-level replies, separate from Explore post comments and normal Field trip
  publication comments.
- `public.get_field_trip_catalog(self_id UUID, user_region TEXT, max_limit INTEGER)`:
  Returns active templates with access state, levels, checklist items, and the
  requester's progress. Completed items include their exact private
  `completed_scan_id`; incomplete items return a null evidence link. The
  response includes no media URL.
- `public.get_field_trip_template_detail(self_id UUID, target_template_id UUID, target_slug TEXT)`:
  Returns one catalog-shaped template payload with guide fields, item tips,
  access state, viewer progress, and the same private completion scan link. The
  detail-only progress object also returns the requesting owner's active,
  non-deleted publication ID/timestamp so iOS can distinguish **Private** from
  **Published** without inferring from completion or Community results. Both
  catalog/detail functions are restricted to `service_role`; authenticated
  callers reach them through `/field-trips`, which supplies the verified user
  ID. `20260718043218_expose_field_trip_completion_scan_ids.sql` defines this
  evidence-link contract;
  `20260718051748_expose_field_trip_publication_status.sql` adds the detail-only
  publication status while preserving the same role grants.
- `public.get_field_trip_capture_context(self_id UUID)`: Private service-role
  read model for the visual Scan indicator. Returns only accessible active,
  incomplete, non-hidden standard field trips and unfinished targets from each
  current unlocked level. Field trips order by latest start or item completion,
  and targets use curated checklist order. It reads standard Field trip
  completions only; Seasonal labels and challenge-specific completions are
  excluded, but joining a challenge does not hide the shared underlying standard
  field trip. The payload contains aggregate progress and prompt metadata
  only—never scan IDs, media, location, notes, completed species labels, or
  evidence. Execute is revoked from `PUBLIC`, `anon`, and `authenticated` and
  granted only to `service_role`; the authenticated `/field-trips` Edge action
  supplies the verified user ID. The function uses an empty search path with
  fully qualified objects. Its functional-Pro gate is the private
  `internal.user_has_effective_pro(uuid)` definer. Because the public projection
  remains `SECURITY INVOKER`, migration
  `20260808215410_restore_field_trip_capture_entitlement_helper_access.sql`
  grants that one transitive helper only to `service_role`; `PUBLIC`, `anon`,
  and `authenticated` remain denied. Migration
  `20260808230028_restore_field_trip_capture_context_source_reads.sql` grants
  the same invoker `SELECT` on only its six source relations: `users`,
  `user_field_trips`, `field_trip_templates`, `field_trip_levels`,
  `user_field_trip_item_completions`, and `field_trip_checklist_items`. It adds
  no mutation privilege. The response behavior is defined by
  `20260717213641_preserve_standard_outings_in_capture_context.sql`.
  `20260717224544_retire_forest_edges_outing.sql` deactivates the placeholder
  Forest Edges template, so this read model and other active-template RPCs omit
  it without deleting historical user rows.
- `public.start_field_trip(self_id UUID, target_template_id UUID)`: Explicitly
  starts or unhides the caller's progress row for an accessible Field trip
  template. Backyard Safari is already started for a new account; this routine
  starts other outings and resumes stopped/reset state.
- `internal.auto_enroll_backyard_safari_level_one()`: Deny-by-default
  `public.users` insert trigger that creates Backyard Safari Level 1 and its
  initial private activity period for future signed-in and ghost accounts. It
  is `SECURITY DEFINER` with an empty search path; execute is revoked from
  `PUBLIC`, `anon`, `authenticated`, and `service_role`. The migration preflight
  requires an active accessible Level 1 with at least one checklist item, then
  backfills only users missing a Backyard Safari row. The trigger is named
  `auto_enroll_backyard_safari_level_one_on_user_insert`, and it safely no-ops
  if the curated starter is retired later. Existing stopped, reset, and
  completed rows are never updated or resumed.
- `public.get_field_trip_community_publications(self_id UUID, mode TEXT, target_template_id UUID, user_region TEXT, viewer_habitat_tags TEXT[], viewer_season_tags TEXT[], max_limit INTEGER, before_rank_bucket INTEGER, before_published_at TIMESTAMPTZ, before_publication_id UUID)`:
  Returns visible published completed trips for the Field trips `Community`
  surface. `smart` ranks by followed-author and coarse region/habitat/season or
  template relevance buckets, `following` filters to `user_follows`, and
  `recent` orders reverse chronologically. Pagination is stable on
  `(rank_bucket ASC, published_at DESC, publication_id DESC)`.
- `public.get_recent_field_trip_publications(self_id UUID, user_region TEXT, viewer_habitat_tags TEXT[], max_limit INTEGER, before_published_at TIMESTAMPTZ, before_publication_id UUID)`:
  Compatibility wrapper for `get_field_trip_community_publications(...)` with
  `mode = 'recent'`.
- `public.field_trip_item_matches_scan(...)`: Internal matcher used by progress
  application. It checks species, scientific-name, positive taxonomy/group
  constraints, optional excluded taxonomy family, conjunctive
  taxonomy-plus-signal rules, habitat/ecology, and prompt-text signals against
  the saved scan. An excluded-family match requires a populated scan family so
  missing lineage cannot produce a false positive. A conjunctive match fails
  closed unless it has both kinds of configured evidence and every configured
  constraint matches.
- `public.apply_field_trip_scan_progress_v2(self_id UUID, target_scan_id UUID, preferred_user_field_trip_id UUID, preferred_item_id UUID)`:
  Applies server-authoritative progress for one caller-owned saved biological
  scan. Standard outings must already exist and the scan timestamp must belong
  to an activity period; joined Events use `joined_at` through `ends_at`. An
  unreviewed AI identification must meet its inference tier's Possible-match
  boundary (`Flash >= 0.75`, `Pro >= 0.65`), while an explicit confirmation or
  confirmed correction/resolution overrides the original model score. Exactly
  one current-level match can be credited per outing/Event. A valid visible
  Capture preference wins inside its own standard outing. Otherwise the matcher
  ranks exact species, scientific name, taxonomy from genus through kingdom
  (including excluded-family and taxonomy-plus-signal variants), semantic tag,
  ecology, habitat, curated checklist order, then item ID. The exact active
  objective criteria are maintained in the
  [Field Trips matching contract](../features-and-hardware/25-field-trips.md#active-objective-matching-contract).
  The same scan may still advance several eligible experiences. Reapplication is
  idempotent. While an experience remains unfinished, identification correction
  can move or remove credit in the original credited level and recompute the
  earliest incomplete level; completed experiences are immutable for normal
  identification corrections. Evidence-policy invalidation is the exception.
  Migration
  `20260722195453_exclude_ants_from_bee_wasp_goal.sql` performs a one-time
  correction of ant-backed **Bee or wasp** completions, reopens affected
  standard/Event progress, clears derived receipts/preferences and badges, and
  hides any now-invalid completion publication until the goal is legitimately
  completed again. `20260722211636_tighten_field_trip_goal_matching.sql`
  performs the equivalent repair for other corrected active goals, including
  Butterfly, Spider, flowering/fruiting plants, animal ecology goals, wild
  plants, and Meadow plant.
  `20260730023042_gate_field_trip_progress_by_confidence.sql` removes prior
  weak-unreviewed credit and repairs its derived progress/publication state
  while retaining selected-goal preferences for later confirmation. Future
  confidence, inference-tier, or confirmation downgrades run the same repair
  even after completion: affected standard/Event progress reopens, Event badges
  are cleared, and completion publications/entries are soft-deleted. Its
  migration-time repair is bounded by a ten-second lock timeout and five-minute
  statement timeout. Responses preserve current and credited-level counts and
  may add `removed_item_ids`.
- `public.field_trip_scan_identification_is_eligible(ai_confidence_score DOUBLE PRECISION, inference_tier TEXT, confirmed_species_id UUID, user_confirmed_identification BOOLEAN)`:
  Internal immutable evidence-policy helper. It accepts a resolved or explicitly
  confirmed identification, Flash confidence at or above `0.75`, or Pro
  confidence at or above `0.65`; a missing/unknown tier uses the stricter Flash
  boundary. Null and out-of-range scores fail unless confirmation overrides
  them. Execute is denied to `PUBLIC`, `anon`, `authenticated`, and
  `service_role`.
- `public.remove_ineligible_field_trip_scan_progress(self_id UUID, target_scan_id UUID)`
  and
  `public.remove_ineligible_field_trip_challenge_scan_progress(self_id UUID, target_scan_id UUID)`:
  Internal reconciliation helpers called only from the database-owned progress
  wrappers. They delete ineligible completion rows, reopen the earliest
  incomplete level, and withdraw completion-derived publication/Event
  artifacts. Execute is denied to every API role, including `service_role`.
- `public.apply_field_trip_scan_progress(self_id UUID, target_scan_id UUID)`:
  Compatibility wrapper that calls V2 without a preference, preserving older
  Edge/client behavior.
- `public.apply_field_trip_scan_progress_atomic(self_id UUID, target_scan_id UUID, preferred_user_field_trip_id UUID, preferred_item_id UUID)`:
  Transactional Edge-owned entry point. It locks the caller-owned scan, returns
  a matching scan-revision receipt when available, otherwise applies standard
  outing and joined Event progress, persists the validated preference, evaluates
  the first Field trip achievement, and writes the receipt in the same
  transaction. Confidence, inference tier, and explicit confirmation are part
  of the scan revision. Any error rolls back every component. Scan-ingestion and
  evidence-changing correction triggers call this function; the Edge progress
  action calls it again to retrieve the response for notifications.
- `public.get_first_field_trip_achievement_progress(self_id UUID)`: Private
  `SECURITY INVOKER` achievement projection executable only by `service_role`.
  The repair migration adds that role's missing read access to
  `user_field_trips`, `field_trip_templates`, and
  `field_trip_challenge_participants`, the three source tables required by this
  function. Existing client-table access remains governed by each table's
  original grants and RLS policies; API roles cannot execute this projection.
- `public.get_field_trip_scan_contributions(self_id UUID, target_scan_id UUID)`:
  Private service-role-only read model returning every standard outing/Event
  credit owned by one saved biological scan. Rows contain source and routing
  IDs, labels, credited item/level counts, completion state, and artwork inputs;
  they exclude media, storage URLs, coordinates, place labels, and notes.
  Execute is revoked from `PUBLIC`, `anon`, and `authenticated`.
- `public.get_field_trip_profile_summaries(self_id UUID, target_author_user_id UUID, max_limit INTEGER)`:
  Returns active status-only, pinned published, and general published Field trip
  summaries visible to the requester. Pinned publications are omitted from the
  general published list.
- `public.set_field_trip_pinned_publications(self_id UUID, publication_ids UUID[])`:
  Replaces the caller's pinned published Field trips, preserving supplied order
  and rejecting more than 3 publication IDs.
- `public.can_view_field_trip_publication(self_id UUID, target_publication_id UUID)`:
  Returns whether the requester may view a published Field trip after
  publication state, shadowban, and block checks.
- `public.publish_field_trip(self_id UUID, target_user_field_trip_id UUID, title TEXT, description TEXT, ai_summary TEXT)`:
  Publishes a completed trip into Field trip publication tables without writing
  `explore_posts`, map points, APNs, widgets, or normal Explore post
  notifications. Publication item materialization uses the ID returned by the
  publication upsert. V3 followed-author publication activity is stored only in
  `field_trip_activity_notifications`.
- `public.get_field_trip_publication_detail(self_id UUID, target_publication_id UUID)`:
  Returns a visible Field trip publication detail payload.
- `public.get_field_trip_comments(self_id UUID, target_publication_id UUID, max_limit INTEGER, after_created_at TIMESTAMPTZ, after_comment_id UUID)`:
  Returns paginated Field trip comments using the Explore comment-shaped client
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
  Field trip, and creates/returns the separate participant row.
- `public.apply_field_trip_challenge_scan_progress(self_id UUID, target_scan_id UUID)`:
  Applies challenge progress for a caller-owned scan when the user joined the
  live challenge before the scan and the scan falls before the challenge ends.
  It returns `challenge_updates` payloads for V4 clients and the same optional
  credited-level/count fields as standard progress. Its signature, security
  context, and execute permissions remain unchanged by the credited-progress
  migrations.
- `public.get_field_trip_challenge_hashtags_for_scan(self_id UUID, target_scan_id UUID)`:
  Returns normalized suggested hashtags for challenge items completed by a scan,
  for optional Explore composer suggestions only.
- `public.get_field_trip_challenge_publications(self_id UUID, target_challenge_id UUID, max_limit INTEGER, before_published_at TIMESTAMPTZ, before_entry_id UUID)`:
  Returns visible published challenge entries with stable
  `(published_at DESC, entry_id DESC)` pagination and Field trip block/shadowban
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

All public-schema `SECURITY DEFINER` functions whose names contain `field_trip`
or `challenge` are Edge-owned. Execute is revoked from `PUBLIC`, `anon`, and
`authenticated` and granted only to `service_role`; the Edge handler derives
`self_id` from its verified session rather than accepting client-owned identity.
Trigger functions use the same least-privilege ACL and are invoked by
PostgreSQL, not direct RPC callers.

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
  informational only; Field trip rows have `field_trip_publication_id` and route
  to Field trip publication detail. Paging is stable on
  `(updated_at DESC, notification_id DESC)` so new activity does not cause
  duplicates while the sheet paginates.
- `public.get_unread_explore_notification_count(self_id UUID)`: Returns the
  unread bell badge count for visible Explore notifications and Field trip
  in-app activity rows.
- `public.mark_explore_notifications_read(self_id UUID)`: Marks all of the
  viewer's Explore notification and Field trip activity rows as read. The iOS
  client calls this only after a successful notifications fetch.
- `public.get_explore_push_notification_payload(target_notification_id UUID)`:
  Internal push-delivery projection used by `send-push-notification`. It filters
  hidden/unshared/blocked activity the same way the in-app feed does and returns
  APNs-safe actor names plus comment body text or Community request/taxon
  display fields for one pushable notification row. Follow notifications are
  skipped before push dispatch and have no post payload.
- `public.reparent_user_follows(ghost_id UUID, target_user_id UUID)`: Legacy
  service-role-only helper retained for deployment compatibility. Authenticated
  execution is revoked; the atomic Ghost merge now resolves follow conflicts
  inside its private transaction.
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
node at 03:00 UTC, authenticating with the effective server key from
`vault.decrypted_secrets`. Migration
`20260727013416_future_proof_server_key_boundaries.sql` upgrades the persisted
job to key-format-aware headers: current opaque keys use `apikey` only and
legacy service-role JWTs use matching `apikey` and Bearer transport. The job
invokes the bounded retention selector. The selector generation-locks and
revalidates expired `is_biological_subject = false` rows before inserting
private permanent deletion fences; the independent five-minute
`reconcile-scan-deletions` worker owns all Cloudflare R2 and row erasure.
`public.request_nonbiological_scan_retention_deletions(integer)` is a
fixed-empty-search-path `SECURITY DEFINER` routine executable only by
`service_role`; it performs its own service-role authorization and has no API
role grant.

### `20260513070000_add_species_content_refresh_worker_schedule.sql`

Adds `public.replace_species_reference_images(...)` and schedules the
`refresh_species_content_hourly` `pg_cron` job. The job posts to
`/functions/v1/refresh-species-content` at minute 17 every hour using the
effective server key from the compatibility-named Vault/current-setting slot and
a small `{ "limit": 25 }` body. The Edge worker consumes
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

### `20260719023147_suppress_european_wildcat_roadkill_image.sql`

Suppresses iNaturalist media `605615444`, surfaced through GBIF occurrence
`5938154750`, without removing the European wildcat species row. The migration:

- deletes matching `species_reference_images` rows;
- removes matching entries from `species_dictionary.reference_image_url` while
  preserving permitted source order;
- replaces `public.public_species_reference_image_urls(...)` and
  `public.public_species_first_reference_image_url(...)` with filtered versions
  so normalized and legacy projections promote the next permitted image; and
- installs `public.suppress_blocked_species_reference_image()` plus its
  normalized-table trigger to silently reject future exact-path writes.

The Edge and iOS helpers intentionally mirror this migration. This is not a
general media classifier or a taxon-wide block. A future outlier requires a new
forward migration and matching server/iOS policy tests; never edit this applied
migration to add another ID.

## Internal administration, reporting, and AI usage

Migration `20260719161112_add_internal_admin_foundation.sql` introduces a
private, non-exposed `internal` schema plus two service-owned public tables.
`PUBLIC`, `anon`, and `authenticated` have no direct access to the internal
schema, `user_reports`, or `ai_usage_events`. Browser access is limited to the
explicitly granted admin RPC wrappers documented in
[`05-api-contracts.md`](./05-api-contracts.md).

### `user_reports`

One intake row is retained per reporter/target pair:

- `id UUID PRIMARY KEY`
- `reporter_user_id UUID NOT NULL` → `public.users(id)` with cascade delete
- `reported_user_id UUID NOT NULL` → `public.users(id)` with cascade delete
- `reason TEXT NOT NULL`: `Spam`, `Harassment`, `Impersonation`,
  `Inappropriate profile`, or `Other`
- `details TEXT`: optional, at most 1,000 characters
- `status TEXT NOT NULL`: `PENDING_REVIEW`, `DISMISSED`, or `ACTIONED`
- `created_at`, `updated_at TIMESTAMPTZ NOT NULL`

The table rejects self-reports and has a unique constraint on
`(reporter_user_id, reported_user_id)`. `/report-user` upserts evidence without
writing `status`, preserving terminal moderation state. An insert trigger
attaches the row to a grouped private `user` review case.

### `ai_usage_events`

Append-only source of truth for internal AI analytics:

- Identity/time: `id`, `occurred_at`, nullable `user_id`, `created_at`
- Classification: `operation`, `model`, `effective_plan`, `input_modality`,
  `outcome`
- Tokens: `prompt_tokens`, `cached_tokens`, `candidate_tokens`,
  `thinking_tokens`, `tool_tokens`, `total_tokens`
- Modality detail: `prompt_tokens_by_modality JSONB`
- Durable linkage: nullable `scan_id`, `conversation_id`, `message_id`,
  `source_type`, and `source_id`
- Coverage: `is_backfilled`, `coverage_scope` (`complete`, `primary_only`, or
  `partial`)
- Estimate: `estimated_cost_microusd`, `pricing_version`
- Non-content extension data: `metadata JSONB`

`effective_plan` is `free`, `pro_paid`, `pro_complimentary`, historical
`pro_trial`, or `unknown`;
`input_modality` is `text`, `image`, `audio`, `video`, `mixed`, or `unknown`;
`outcome` is `success`, `refusal`, or `error`. Token/cost values are nullable
but cannot be negative.

Despite its legacy column name, `prompt_tokens_by_modality` stores the complete
normalized modality breakdown:

```json
{
  "prompt": { "text": 120, "image": 258 },
  "cached": { "text": 40 },
  "candidates": { "text": 80 },
  "tool": {}
}
```

Missing Gemini detail arrays normalize to empty objects; no prompt or response
content belongs in this field.

The unique key `(source_type, source_id, operation)` makes durable retries and
backfills idempotent. Indexes cover event time, operation/time, scan, and
user/time. An append-only trigger rejects arbitrary updates/deletes; the account
deletion trigger may clear identifying linkage while preserving anonymous
aggregates. Ghost-profile merge is the other narrowly authorized ownership
rewrite: transaction-local source/target settings permit changing only
`user_id`, and the migration updates this ledger explicitly. The table
intentionally has no `auth.users` foreign key; an `ON DELETE SET NULL` action
would reach the append-only trigger outside the account-deletion trigger's
authorized anonymization context.

### `internal.ai_quota_policies`, counters, and reservations

Migration `20260723160229_enforce_server_ai_quotas.sql` adds four private
tables. `PUBLIC`, `anon`, `authenticated`, and `service_role` have no direct
table privileges; Edge code reaches them only through the two reviewed
service-role definer RPCs.

- `internal.ai_quota_policies`: one row per `(operation, effective_plan)`.
  Stores enabled/allowed state, allowlisted model, policy version, daily bucket
  and limit, plus shared per-user and per-IP rate bucket/window/limit.
- `internal.ai_quota_counters`: atomic counter keyed by scope, HMAC/user key,
  logical bucket, and fixed window start. Conditional UPSERT prevents a
  read-then-increment race at the limit.
- `internal.ai_quota_reservations`: one idempotent row per
  `(user_id, operation, request_id)`. Captures `reserved`, `committed`,
  `failed`, or `refunded` state; attempt/refund/stale-recovery counts;
  `lease_token` and `lease_expires_at`; effective/raw tier; entitlement and
  policy versions; selected model; and daily remaining after reservation.
  The complimentary extension adds nullable `original_analysis_id`, nullable
  `complimentary_client_scan_id`, nullable `client_protocol`, and
  `flash_fallback_used`. A complimentary link must equal the original analysis
  UUID; Flash fallback is valid only for a free primary scan operation.
- `internal.ai_quota_reservation_counters`: temporary links from a live
  reservation to each counter it consumed. Refund locks the reservation,
  decrements these counters once in the same daily/user/IP lock order used by
  reservation, removes zero rows, then removes the links.

Migration `20260809155517_add_scan_admission_preview.sql` exposes one narrow
authenticated RPC, `public.get_my_scan_admission_preview(boolean)`, over this
private state. It binds the lookup to `auth.uid()`, resolves the prospective
paid → complimentary → Flash plan, and returns `allowed`,
`daily_quota_exhausted`, or `pro_required` plus the applicable daily limit and
remaining count. It is intentionally read-only and does not create a hold,
counter increment, or reservation. Only `authenticated` has execute privilege;
the later service-only reservation remains authoritative.

`reserve_ai_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)` locks the
user before quota or ledger rows, serializes an identical request key, resolves
paid Pro → complimentary Pro → free under the rollout fence, and consumes all
applicable counters atomically. The final boolean is true only for
authenticated internal replay; it bypasses the public protocol fence but does
not bypass ownership, analysis linkage, entitlement, quota, or settlement.
`finalize_ai_quota_reservation(...)` requires the
current per-attempt fencing token and performs an idempotent commit/fail/refund
transition. Committed provider failures retain their consumed counters but may
be reserved as a newly metered retry; stale callbacks with an older token are
rejected. Both public RPCs use `SECURITY DEFINER SET search_path = ''`, call
`internal.require_service_role()`, and are allowlisted only to `service_role`.
`internal.refund_expired_ai_quota_reservations()` uses `FOR UPDATE SKIP LOCKED`
every five minutes to refund abandoned `reserved` attempts after their
ten-minute lease without racing an active finalizer.
`internal.prune_ai_quota_state()` runs hourly and uses cleanup indexes on
terminal reservation update time and counter window start to delete bounded
batches of old state and unreferenced counters; it never drops a live
reservation without first releasing its counters. Migration
`20260729200000_harden_media_abandoned_scan_recovery_proof.sql` exempts only
exact failed/committed normal and replay scan-identification reservations while
their owner/scan job remains unresolved
`failed_terminal / media_reconciliation_abandoned`. These rows are durable
chronological recovery/security authority for older library items: the latest
row can support or veto recovery according to matching dead-letter lineage.
Refunded attempts and unrelated terminal reservations retain the ordinary 30-day
limit; recovery or explicit operator resolution also returns the exact authority
rows to normal pruning.

### Complimentary entitlement rollout and lifetime usage

Migrations `20260802235833_three_complimentary_pro_scans.sql` and
`20260803181936_add_reservation_safe_entitlement_protocol.sql` add the following
current entitlement state:

- `public.users.complimentary_entitlement_epoch`: protected mutation epoch.
  Hold, settlement, and merge routines increment it; the existing trigger then
  advances the account's monotonic `entitlement_version`. Browser roles cannot
  update it.
- `internal.entitlement_rollout_config`: one owner-only `current` row containing
  `legacy_trial`/protocol `0` or `complimentary`/protocol `2` or `3`, fixed grant
  `3`, and monotonic `mode_version`. Protocol 2 is the dual-mode rollout state;
  protocol 3 requires reservation-safe clients. The migration inserts legacy
  mode so schema deployment alone cannot strand older clients.
- `internal.complimentary_scan_usage`: private ledger keyed by
  `(user_id, client_scan_id)`, with `held`, `consumed`, or `released` state;
  hold/settlement times; validated `settlement_reason`; and reacquisition count.
  A partial `(held_at, user_id, client_scan_id)` index supports stale-hold
  operations; a partial state/reason/time index supports aggregate telemetry.

No balance is stored. The fixed grant minus consumed rows is
`scans_remaining`; subtracting held rows also produces
`scans_available_to_start`; held rows produce `in_flight_count`. Paid accounts
retain their derived balance, but paid scans do not create or settle ledger
rows.

`public.get_my_entitlement()` is the sole authenticated own-account read and
derives identity from `auth.uid()`. Service-only reads use
`get_user_entitlement_service(uuid)` and
`get_entitlement_rollout_service()`. Completion and terminal settlement use
`complete_scan_ingestion_with_entitlement(...)` and
`fail_scan_ingestion_terminal(...)`; both acquire the user lock before existing
ingestion/scan/media locks. Completion/terminal trigger fences prevent direct
lower-level state transitions after cutover.

All rollout and ledger tables have RLS enabled and revoke direct access from
`PUBLIC`, `anon`, `authenticated`, and `service_role`. Definer RPCs use empty
search paths, in-body role checks where applicable, explicit minimum grants,
and privileged-routine catalog entries. The full state machine and merge cap
are normative in
[`18-complimentary-pro-scans.md`](./18-complimentary-pro-scans.md).

### `internal.revenuecat_webhook_events` and customer state

Migration `20260723201500_secure_revenuecat_webhook_delivery.sql` adds the
private RevenueCat synchronization ledger:

- `internal.revenuecat_webhook_events`: one row per provider `event_id`,
  enforced by the primary key. It stores provider event metadata, raw-payload
  SHA-256 digest, signature timestamp, aggregate `applied` / `stale` / `mixed` /
  `ignored` outcome and counts, and receipt time. Raw webhook JSON and
  RevenueCat secret values are not stored.
- `internal.revenuecat_webhook_event_subjects`: zero to two rows per event. Each
  row stores a resolved Merian user,
  customer/transfer-source/transfer-destination kind, authoritative snapshot
  timestamp, projected tier/expiry, per-user outcome, and entitlement version.
  Separating event identity from subjects allows one `TRANSFER` event to own
  both sides of the move.
- `internal.revenuecat_customer_state`: one row per Merian user containing the
  last accepted event ID, provider event timestamp, authoritative CustomerInfo
  timestamp, and update time.

All three tables have RLS enabled and revoke all direct access from `PUBLIC`,
`anon`, `authenticated`, and `service_role`. Edge code can mutate them only
through `public.apply_revenuecat_customer_state(...)`, a service-role
allowlisted `SECURITY DEFINER` routine with an empty search path and an
in-function caller check. The identically protected
`public.get_revenuecat_webhook_event_result(...)` returns an existing committed
receipt without granting direct ledger access, avoiding another RevenueCat API
call for ordinary at-least-once retries.

The routine requires each RevenueCat identity group to resolve to exactly one
existing `public.users` row; it never creates one and rejects multiple live UUID
matches as ambiguous. It takes all affected user locks in sorted UUID order, so
a transfer cannot deadlock another transfer or commit only one side. The event
can omit a transfer source that has already been deleted, because no Merian
entitlement remains to revoke; a missing normal or destination profile remains
retryable. The event primary key makes repeated delivery idempotent. Migration
`20260725052338_reconcile_revenuecat_subscribers.sql` makes authoritative
CustomerInfo snapshot time the primary per-user version; provider event
timestamp and event ID break only exact snapshot ties. A newer version updates
tier/expiry, its subject row, and the watermark in the same transaction. A
duplicate returns aggregate counts without another write; an older version is
retained as `stale`. Reusing an event ID with a different timestamp, type, or
payload digest raises a unique-conflict error. Normal events can contain at most
one `customer` subject; transfers can contain at most one source and one
destination, enforced in both the RPC and a per-event subject-kind uniqueness
constraint. Indexes cover event receipt time, subject user foreign keys, and the
watermark's event foreign key so account deletion and operational joins do not
scan the private tables.

`internal.revenuecat_reconciliation_queue` holds one durable repair row per
linked Merian user. It stores the RevenueCat lookup ID, next due time, bounded
attempt/backoff state, a two-minute claim token/lease, last provider snapshot,
and last successful reconciliation. The 15-minute cron invokes the service-only
worker, which repeatedly claims six-row `FOR UPDATE SKIP LOCKED` waves until
empty or its runtime start-work cutoff and limits CustomerInfo concurrency to
three. The due-row partial index supports unclaimed selection; a second partial
index led by `claim_expires_at` supports expired-lease cleanup without scanning
future or unclaimed rows. Pro users are rescheduled for six hours and free users
for 24 hours. Only a snapshot newer than `internal.revenuecat_customer_state`
can change access. Webhook processing schedules affected subjects
transactionally. Background reconciliation never newly grants a historical
seven-day pass. Database-generated lookups use
`internal.canonical_revenuecat_app_user_id(...)`; webhook-provided aliases stay
byte-for-byte unchanged. Because RevenueCat subscriber GET is get-or-create,
this case contract prevents a lowercase UUID customer from being manufactured
beside the uppercase iOS customer. The GET can successfully return `200` for an
existing customer or `201` for a newly created empty customer. Either status is
transport success; only parsed CustomerInfo determines entitlement.

The canonicalization migration makes repaired UUID queue rows immediately due.
That is desirable for ordinary repair but creates a release-order boundary when
the same users need beta promotions: the named reconciler must not run between
the migration and approved grants. The supervised hold, explicit cohort, and
schedule-restoration evidence are defined in the
[RevenueCat customer identity incident](../incidents/2026-08-revenuecat-customer-identity-drift.md).

`public.get_revenuecat_reconciliation_health()` is a service-role-only
`SECURITY DEFINER` routine with an empty search path and an in-body caller
check. It reports due/expired counts and oldest due age through the two partial
indexes; API roles retain no direct queue access.

### Guarded empty-Ghost deletion intake

Migration `20260810034953_guard_empty_ghost_account_cleanup.sql` adds a narrow
operator intake into the ordinary account-deletion state machine. It does not
add an Auth-delete shortcut.

`internal.empty_ghost_cleanup_blockers(uuid,integer)` requires an old anonymous
Auth identity with no email, phone, non-anonymous provider, or recent Auth
session; a free, expiry-free default public profile; and no active merge or
deletion. It first asserts complete coverage of
`internal.ghost_profile_merge_reference_policies`, then treats every reviewed
current or future user foreign key as a blocker except `public.users.id`, the
provider reconciliation queue/ordering watermark, and the exact automatically
created untouched Backyard Safari Level 1 trip. The free public projection and
recent live provider proof govern the watermark exception; webhook subject
history still blocks. It separately checks logical references without foreign
keys. Any changed trip/period, application activity, legal receipt, custom
identity, provider event history, or schema-policy drift preserves the account.

The service-only RPCs are:

- `inspect_empty_ghost_cleanup_candidate(uuid,integer)`, a read of the exact
  live blocker function; and
- `request_empty_ghost_account_deletion(uuid,uuid,integer,text,text,timestamptz,integer)`,
  which requires a live Ghost-cleanup reservation, reviewed plan SHA-256,
  RevenueCat project, verification no more than ten minutes old, and bounded
  checked-customer count.

The intake takes the Ghost-merge advisory lock, locks Auth/profile rows, reruns
all blockers, creates and claims the durable account-deletion job, and completes
the relational phase in the same transaction. Success must be
`storage_pending`; Auth is intentionally retained for delayed R2 verification.
`internal.empty_ghost_account_deletion_receipts` stores only the deletion job,
plan hash, provider project, verification timestamp, checked count, and request
time. It has RLS and no direct API-role access. A merge-handoff trigger rejects
new prepared/merged handoffs while deletion is active.

### `internal.account_deletion_jobs`

Migration `20260725030308_durable_account_deletion.sql` adds durable intake;
migration `20260725052337_enforce_account_storage_erasure.sql` completes the
private account-deletion state machine. Migration
`20260806203700_durable_apple_provider_revocation.sql` adds the provider
revocation substage required for Sign in with Apple. The job table has RLS
enabled and revokes direct table access from `PUBLIC`, `anon`, `authenticated`,
and `service_role`.

Important columns and invariants:

- `status`: `pending`, `storage_pending`, `auth_pending`, or `completed`
- nullable `user_id`, with one active job per UUID; terminal completion sets it
  to `NULL` for data minimization
- `cleanup_completed_at`, `storage_completed_at`, `auth_deleted_at`, and
  `completed_at`, constrained to match the state
- `provider_revocation_status`: `pending`, `completed`, `manual_required`, or
  `not_required`; its resolved timestamp and
  `manual_provider_revocation_required` boolean are constrained as one coherent
  disposition
- `claim_token`, `claimed_at`, and `claim_expires_at`, which are either all
  present or all absent
- `attempt_count`, `next_attempt_at`, and a bounded `last_error_code`

Partial indexes cover due active work and expired claims. The service-only state
transitions are:

- `request_account_deletion(uuid)` — idempotent durable intake returning the
  job ID/status and legacy manual-provider disposition
- `claim_account_deletion_jobs(integer,uuid)` — bounded `SKIP LOCKED` leasing;
  the optional UUID is only for the initiating authenticated route's fast path
- `complete_account_deletion_cleanup(uuid,uuid)` — claim-fenced storage-job
  insert, idempotent tombstone, and relational verification; returns
  `storage_pending` until delayed storage verification permits `auth_pending`,
  then returns `provider_revocation_pending` when a stored credential remains
- `get_account_deletion_provider_token(uuid,uuid)` — reads the Vault token only
  for the active, unexpired `auth_pending` claim
- `complete_account_deletion_provider_revocation(uuid,uuid)` — deletes the
  private mapping, idempotency receipts, and Vault secret before committing
  provider success
- `finish_account_deletion_attempt(uuid,uuid,boolean,text)` — terminal Auth
  receipt or database-calculated retry; success verifies completed storage,
  resolved provider state, and credential absence again

### Apple revocation credential tables

`internal.apple_sign_in_revocation_credentials` maps one Auth user to one
`vault.secrets` UUID. Both foreign keys use `ON DELETE RESTRICT`; the Auth edge
prevents an Admin deletion from bypassing provider revocation, while the Vault
edge prevents orphaning the mapping. The table has RLS enabled and no direct
API-role privileges, including `service_role`.

`internal.apple_sign_in_credential_registrations` stores token-free,
client-generated registration UUID receipts for response-loss idempotency. Its
Auth foreign key cascades only when the user is legitimately deleted, and
successful provider completion removes the user's receipts first. Receipts
older than 24 hours are pruned on later successful registration.

`apple_revocation_registration_exists(uuid,uuid)` checks a receipt before the
one-use code is exchanged. `store_apple_revocation_credential(uuid,uuid,text,text)`
locks the permanent Auth user, rejects active deletion, binds the Apple subject
to `auth.identities`, and creates or updates the Vault secret atomically. Both
routines, plus the two claimed deletion routines above, are empty-search-path,
in-body-authorized, service-role-only entries in
`internal.privileged_routine_grants`.
See the
[Sign in with Apple account-deletion contract](./20-sign-in-with-apple-account-deletion.md)
for runtime ordering, secrets, legacy fallback, and rollout evidence.

The separate service-only storage transitions are
`claim_pending_storage_deletions(integer)`,
`advance_pending_storage_deletion(uuid,uuid,text,boolean)`, and
`fail_pending_storage_deletion(uuid,uuid,text)`. They lease and advance one
bounded R2 prefix page under a UUID claim token.

Migration `20260726041109_fence_storage_erasure_claims.sql` makes the private
account job—not the public outbox row—the authority for every destructive
storage claim. `claim_pending_storage_deletions` now inner-joins the same
owner's job at `storage_pending`, requires non-null `cleanup_completed_at` and
null `storage_completed_at`, and rejects candidates while any matching
`public.users` row or owned `public.scans` row exists. An orphaned, old, reset,
or manually due outbox row is inert. This fence is a required invariant, not an
optional worker-side preflight.

Migration `20260727001630_monitor_account_deletion_health.sql` adds partial
indexes led by active request/create time, active retry-error update time, and
active storage claim expiry. Service-only `public.get_account_deletion_health()`
uses those boundaries to return one aggregate row containing:

- account phase, due, retry-error, active-lease, and expired-lease counts;
- oldest active and oldest claimable account timestamps and ages;
- storage backlog, due, retry-error, verification-wait, lease, and orphan counts
  plus oldest active/due ages; and
- booleans for the named five-minute reaper cron and the URL/service credential
  configuration it requires.

The routine calls `internal.require_service_role()`, has an empty search path,
is allowlisted only for `service_role`, and deliberately omits UUIDs and raw
error values. It is a read-only health surface; it does not claim or repair
work. `reaper_credentials_configured` applies the same Vault-first, NULL-only
selection as the cron and then requires both effective values to be nonblank. A
blank Vault row therefore does not fall through to an app setting. The field is
configuration readiness, not credential validation: it does not prove that the
URL resolves, the key matches the Edge secret, or a reconciler request succeeds.

Migration `20260727190804_index_user_foreign_keys_for_identity_lifecycle.sql`
additionally catalogs every owned single-column foreign key in `public` and
`internal` that references `public.users` or `auth.users`. It reuses only a
valid, ready, non-partial, non-expression index led by that FK column. Missing
indexes are created inline only on relations no larger than 32 MiB. Larger
relations abort with SQLSTATE `55000` and a supervised concurrent command;
partitioned parents require valid leaf indexes plus a reviewed metadata-only
parent operation. This bounds identity updates and account deletion without
turning a forgotten production preflight into an unbounded write lock.

`trg_reject_account_deletion_profile_recreation` runs before inserts on
`public.users` and rejects the original UUID while an active job exists. This
prevents Auth metadata triggers or backend upserts from recreating the profile
between verified cleanup and Auth deletion.

Every RPC is a public-schema discovery name with `SECURITY DEFINER`,
`search_path = ''`, an `internal.require_service_role()` caller check, and an
explicit `service_role` allowlist entry. Client API roles have no execution
grant.

### `internal.ghost_profile_merge_handoffs`

Private source-issued proofs and durable receipts for anonymous-to-existing
account upgrades. The schema is not exposed through the Data API, has RLS
enabled, and grants direct access only to `service_role`.

Important columns:

- `ghost_user_id`, nullable `target_user_id`
- `expected_provider` (`apple` or `google`) and exact provider subject
- unique SHA-256 `secret_hash`; the bearer secret is never stored server-side
- `status`: `prepared`, `merged`, `superseded`, or `expired`
- `expires_at`, `merged_at`, and `auth_deleted_at`
- cleanup attempts, bounded last error code, lease token, and lease timestamp

Partial indexes enforce at most one prepared and one merged receipt per source.
Additional indexes cover expiry maintenance and merged receipts awaiting Auth
cleanup. A prepared handoff expires after 30 days.

The public-schema RPC names are Data API entrypoints, not public permissions:

- `issue_ghost_profile_merge_handoff(text,text,text)` and
  `consume_ghost_profile_merge_handoff(uuid,text)` are executable only by
  `authenticated`. Both derive authority from `auth.uid()`; callers cannot
  supply source or destination UUIDs.
- `record_ghost_profile_merge_auth_cleanup(uuid,boolean,text)`,
  `claim_ghost_profile_merge_auth_cleanups(integer)`, and
  `finish_ghost_profile_merge_auth_cleanup(uuid,uuid,boolean,text)` are
  service-role-only. Claims use `FOR UPDATE SKIP LOCKED`, random lease tokens,
  bounded batches, stale-lease recovery, and retry backoff.
- All merge implementation helpers live in `internal`, use fixed empty search
  paths, and revoke `PUBLIC` execution.

`internal.perform_ghost_profile_merge` resolves known unique-key conflicts,
executes only manifest-reviewed ownership moves, verifies no transferable source
reference remains, preserves customized public identity, and deletes the source
`public.users` row in one transaction. Unsupported composite ownership, stale
policy, or schema drift fails closed. The handler-level lock and destination
repair invariants in the
[Ghost-profile merge reference policy](#ghost-profile-merge-reference-policy)
are part of the same release contract. The obsolete anonymous `auth.users` row
is deleted only after commit by Edge Auth Admin, with the scheduled
reconciliation worker as durable recovery.

`internal.ghost_user_cleanup_reservations` is the companion safety boundary for
the manual old-empty-ghost cleanup script. A service-role RPC creates a
5–60-minute lease under the same per-source advisory lock used by handoff
issuance. Reservation fails if a prepared handoff or merged receipt awaiting
Auth cleanup exists; handoff issuance fails retryably while a reservation is
active. A token-bound finish RPC records success or releases a failed lease.
This prevents an audit snapshot from becoming unsafe when an upgrade begins
between audit and Auth deletion.

### `internal.admin_memberships`

- `user_id UUID PRIMARY KEY` → `auth.users(id)`
- `role TEXT NOT NULL`: `owner`, `moderator`, or `analyst`
- `is_active BOOLEAN NOT NULL`
- `created_by UUID`, `created_at`, `updated_at`

The first row is created only by `internal.bootstrap_first_admin_owner`; later
changes use the owner RPC. Direct database enforcement prevents disabling or
demoting the final active owner.

### `internal.admin_sessions`

- `session_id UUID PRIMARY KEY`: Supabase JWT/Auth session ID
- `user_id UUID NOT NULL`
- `created_at`, `last_seen_at`, `expires_at`
- nullable `revoked_at`

An active session requires no revocation, an absolute expiry in the future, a
`last_seen_at` within 30 minutes, and a matching live `auth.sessions` row.

### `internal.admin_audit_log`

- identity: generated `id`, `actor_user_id`, `actor_role`
- action/target: `action`, nullable `target_type`, nullable `target_id`
- correlation: `request_id UUID NOT NULL`
- change record: nullable `before_state`, `after_state`, and bounded `reason`
- `created_at`

The table is immutable after insert; a trigger rejects update/delete. Indexes
support descending history and actor/time queries.

### `internal.review_cases` and `review_case_sources`

`review_cases` stores one row per `(case_type, subject_id)`:

- `case_type`: `identification`, `post`, `comment`, or `user`
- `status`: `open`, `in_review`, `resolved`, or `dismissed`
- `priority`: `low`, `normal`, `high`, or `urgent`
- nullable `subject_user_id`, active moderator/owner `assigned_to`,
  `resolution_code`, and `resolved_at`
- independent-reporter `report_count`
- `created_at`, `updated_at`

`review_case_sources` maps immutable intake source rows to a case and records
the reporter/time. Source types are `flagged_review`, `explore_post_report`,
`explore_comment_report`, and `user_report`. The source primary key is
`(source_type, source_id)`.

An independent new reporter increments `report_count` and reopens terminal
state; another source from an already attached reporter neither increments the
count nor reopens the case. Advisory transaction locks serialize grouping.

### `internal.feedback_state` and `admin_notes`

`feedback_state` overlays immutable source feedback with:

- composite key `(source_type, source_id)` where source type is `community`,
  `survey`, `chat_message`, or `chat_feature`
- status `new`, `reviewed`, `planned`, or `closed`
- nullable active admin `assigned_to`
- `tags TEXT[]` and `updated_at`

`admin_notes` stores append-only, 1–4,000 character notes for `review_case` or
`feedback` parents with author and timestamp. A trigger rejects note
update/delete.

### `internal.ai_model_pricing` and `admin_aggregate_cache`

`ai_model_pricing` stores exact model/modality Standard prices per million
input, cached, and output tokens with `effective_from`, optional `effective_to`,
and a version label. Overlapping ranges are prohibited operationally; pricing
changes must close the old row and insert a new version in one migration.

`admin_aggregate_cache` stores a private JSON payload by cache key and
`created_at`. Overview and AI summary RPCs accept cache entries only for five
minutes after authorization. Raw review/feedback/user/audit results never use
this cache.

### Moderation and durable usage columns

`explore_posts` adds nullable `moderated_at` and `moderated_by_user_id`. Visible
public-post indexes and every public Explore projection require
`moderated_at IS NULL` as well as the prior visibility rules. Existing
reversible comment moderation columns are reused.

`scans` and `insight_chat_messages` add non-null
`llm_usage_metadata JSONB DEFAULT '{}'`. Durable insert triggers normalize these
values into `ai_usage_events` transactionally.

For authorization, review behavior, anonymization, retention boundaries, and
pricing semantics, see [`10-internal-admin.md`](./10-internal-admin.md).

## SwiftData Schema (Local Offline Queue)

_Note: The iOS persistence layer is enforced via `ModelContainer` in
`MerianApp.swift`. If a store open fails during a production app update, the
application first uses store metadata to choose the narrowest safe migration
strategy, attempts corruption-specific quarantine and retry only for verified
store corruption, archives non-corrupt legacy migration failures under
`store-rescue/` before opening a fresh persistent store, then falls back to an
in-memory safe-mode container if recovery fails, and finally shows a
startup-blocked recovery surface if no container can be created. It must not
silently wipe `URL.documentsDirectory`, and it must not hard-crash from
bootstrap with `fatalError`. To prevent schema failures as the app evolves,
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
each new row into the migration `ModelContext` before assigning the
relationship; relationship assignment alone is not a durable insert path while
SwiftData is inside staged store migration.

The current active schema is `MerianSchemaV50`. Recent milestones:

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
  V42→V49 or V43→V49 so unknown older stores do not force SwiftData to validate
  the duplicate-prone recent representatives. V47 keeps local-scan,
  captured-media, and collection entities frozen inside V47, and keeps its
  queued scan model scalar-only. V44, V45, and V46 stores skip V47 and jump
  directly to V49 from source-isolated V44→V49, V45→V49, and V46→V49 plans so
  SwiftData never migrates unchanged entities across duplicate-prone recent
  representatives. App startup reads store metadata before creating
  `ModelContainer`: fresh/current stores open without a migration plan, known
  recent stores use the source-isolated V48/V47/V46/V45/V44/V43/V42 plans, and
  only unknown older stores use the full historical plan. The V42 and V43 recent
  plans jump directly to V49 to avoid validating older full-historical custom
  stages and to keep V42 off the older V42→V43 bridge that still failed on real
  TestFlight stores, while V45 and V46 deliberately use one matching source
  representative each before the V49 repair target. Stores that still hit
  SwiftData's duplicate-checksum validator during plan construction retry with
  the same source-isolated recent plans before legacy rescue or safe mode.
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
- V50 adds the scan-keyed `OfflineQueuedScanGoalHint` companion through a
  lightweight V49→V50 migration. The released V49 `OfflineQueuedScan` model is
  reused unchanged. Every source-isolated recent recovery plan reaches V49 first
  and then applies the same lightweight V50 stage.

**Edge DTO Layer** (`apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift`): The
marked Identify `EdgeResponseWrapper` / `EdgeResponse` graph is generated from
the executable server contract and owns explicit coding keys and decoders.
`EnrichScanResponse` (the `/enrich-scan` response) remains a separate
hand-written contract. `EnrichScanResponse` contains nested `EnrichData` (maps
`habitat_description`, `gbif_taxon_key`, `taxonomy`, and
`similar_species: [SimilarSpeciesEntry]?`) and `SimilarSpeciesEntry` (maps
`scientific_name`, `common_name`, `reference_image_url`, `iucn_red_list_status`,
plus optional lookalike relation metadata such as `reason`, `visual_traits`,
`confidence`, `source`, `review_status`, `is_bidirectional`, and `sort_order`)
structs. `EdgeResponse` also contains a nested `IdentificationCandidate` struct
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
  versus ordered video frames. Still-photo entries may also carry the transient
  accepted `focusRegion`; this reuses the existing JSON attribute and does not
  require a schema migration.)
- `queueAttemptCount`: Int (Added in `MerianSchemaV48`. Persisted retry count
  for the queued scan. Replaces the older process-local `uploadRetryCount`
  authority and feeds the automatic retry budget. Scan-ingestion control mirrors
  this value on `OfflineJobRecord.attemptCount`; reads and mutations use their
  nonnegative monotonic maximum.)
- `queueLastAttemptAt`, `queueNextRetryAt`: Date? (Added in V48. Used by
  `OfflineQueueRetryPolicy` and the scheduler to survive app relaunch without
  losing backoff state.)
- `queueLastErrorCode`, `queueLastErrorMessage`: String? (Added in V48.
  User/support-facing last local retry, completed-server-result recovery marker,
  or terminal error. `server_result_local_recovery_pending` durably fences a
  known owner result from provider redispatch; the matching `_exhausted` code
  pauses that recovery for explicit user retry. High-authority completion and
  `server_retryable_failure` state is mirrored on the scan-ingestion job;
  serialized transitions reconcile both copies before mutation, with completion
  taking precedence.)
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

The V48→V49 migrations snapshot queued scans before recreating V49 rows and
normalize queued-scan retry metadata. Known-good V48 stores migrate directly to
V49. The accidental optional-queue V48 TestFlight source has its own
`MerianSchemaV48OptionalQueue` and recovery plan; it snapshots optional queue
fields in `willMigrate`, deletes the source rows, and recreates V49 queued scans
with non-optional defaults (`queueAttemptCount = 0`, `queueUpdatedAt = now`,
`queueNeedsAttention = false`) when the optional source stored `nil`.

### `OfflineQueuedScanGoalHint`

Added in `MerianSchemaV50`. This optional companion exists only for a queued
scan submitted from an eligible live Capture goal selection.

- `scanId`: String, unique and equal to the queued scan ID.
- `userFieldTripId`: String identifying the selected standard outing.
- `itemId`: String identifying the selected current checklist goal.

Foreground and background completion fetch this row by scan ID and send it both
with scan ingestion and the post-persistence Field trip acknowledgement call.
Successful queue finalization deliberately preserves the companion: after the
queue row is gone it becomes a small durable progress outbox. Online scheduler
runs replay those orphaned hints after relaunch, and only a successful/terminal
server progress resolution removes the row. Explicit user cancellation and
orphan repair for scans that will never exist may still delete it. It is not
related to `OfflineQueuedScan` through a SwiftData relationship, does not
contain media or inference input, and is not a cache for Insight contribution
cards.

### `OfflineJobRecord`

Added in `MerianSchemaV48` and carried forward unchanged through V50.
Scheduler/control-plane row for media-agnostic offline work. Current `kindRaw`
values are `scanIngestion`, `cloudDeletion`, `collectionSync`,
`speciesPreferenceSync`, and `future`; current `statusRaw` values are `pending`,
`running`, `waiting`, `needsAttention`, `complete`, and `cancelled`.

- `id`: String (unique stable job id such as `scan-ingestion:{scanId}`,
  `cloud-deletion:{scanId}`, or `collection-sync`.)
- `kindRaw`, `statusRaw`: String enum raw values.
- `subjectId`: String? (Scan id or other domain id, when applicable.)
- `priority`: Int
- `createdAt`, `updatedAt`: Date
- `lastAttemptAt`, `nextRunAt`: Date?
- `attemptCount`: Int Tracks bounded automatic retry attempts for ordinary
  durable jobs. Scan ingestion and collection sync pause at `needsAttention`
  after `OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts` automatic
  failures. Cloud deletion uses the same capped value only as a bounded backoff
  exponent; a still-present `PendingCloudDeletionTask` retries without
  expiration and repairs an older paused or contradictory terminal job state.
  For scan ingestion this is the redundant scheduler copy of
  `OfflineQueuedScan.queueAttemptCount`; fresh reads consult both and use their
  monotonic maximum.
- `lastErrorCode`, `lastErrorMessage`: String? For scan ingestion,
  `server_retryable_failure` and completed-result recovery codes mirror the
  queued-scan authority. Either surviving copy repairs the other before a
  serialized queue transition; completed-result recovery wins over retry.
- `lastHTTPStatus`: Int?
- `serverStatus`, `serverStage`, `serverRetryAfter`: server ingestion status
  mirrors for scan jobs.
- `requiresUnconstrainedNetwork`, `allowsCellular`: Bool policy hints.
- `approximateBytes`: Int64 redacted local footprint estimate.
- `metadataJSON`: String? object for non-media scheduler metadata. Scan-ingestion
  jobs may carry `inference_generation` and `funding_reservation` at the same
  time. `funding_reservation` encodes account ID, stable scan ID, source
  (`paid_pro`, `complimentary_pro`, `immediate_flash`, or `deferred_flash`),
  earlier blocker scan IDs, and creation time. Generation and funding helpers
  remove only the property they own. A proven pre-dispatch local failure removes
  the reservation and durably sets `funding_reservation_released: true` while
  preserving all other metadata. A fresh claim removes that marker. Relaunch
  restores nonterminal reservations; a pre-protocol-3 job lacking funding is a
  conservative potential complimentary blocker unless the durable release
  marker proves otherwise.

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
  visual payload was previously copied into local Documents storage. This local
  presentation flag is unrelated to `store-rescue` directories and does not mean
  an R2 object was moved to an archive tier).
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
  `fetchExternalEnrichment` via a REST call to `api.gbif.org/v1/species/match`.
  Current multimodal cache misses may perform that resolution during awaited
  durable finalization; compatibility routes may perform it in background
  insertion. It is not AI-generated—this is GBIF's deterministic taxonomy ID.
  Forwarded to the client at the top-level of the `/identify` response for **all
  tiers** on Cache Hit, and via `/enrich-scan` for all users on the enrichment
  path. Used by `GBIFHeatmapMapView` in `HabitatAndDistributionCard` to fetch
  occurrence density tile overlays from
  `api.gbif.org/v2/map/occurrence/density`, visible to free and Pro users alike.
  `nil` when the model response predates or omits the later dictionary result,
  when external resolution failed to find a match, or for scans captured before
  V18.)
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

**`pending_storage_deletions` — cleanup indexes**: Migration `20260405000002`
added composite index `idx_pending_storage_deletions_status_user` on
`(status, target_user_id, created_at)` for background sweeps. Migration
`20260725030308` deduplicates historical rows and adds unique index
`pending_storage_deletions_target_user_unique_idx` on `target_user_id`, making
account-deletion outbox retries idempotent.

Migration `20260725052337_enforce_account_storage_erasure.sql` converts the
outbox marker into a resumable R2-erasure job. It stores exactly five canonical
prefixes (free uploads, Pro uploads, staging, avatars, and exports), sweep or
verification phase, current prefix index, monotonic `start_after_key`, delayed
`verification_not_before`, due/retry state, and a five-minute UUID claim. The
worker lists at most 50 keys per claim, deletes with concurrency eight, and
persists progress before releasing ownership. After the first full sweep it
waits at least 25 hours and repeats every prefix from the beginning. Only an
empty delayed verification pass sets `status = 'completed'` and wakes the
corresponding account job. Existing unconsumed markers are reset to the new
sweep contract during migration.

That historical reset is why claim authorization must not be inferred from
outbox state. Migration `20260726041109_fence_storage_erasure_claims.sql`
requires the matching tombstoned `storage_pending` private job and adds live
profile/owned-scan vetoes to the SQL claim itself. See the
[July 2026 incident report](../incidents/2026-07-account-scoped-r2-image-loss.md)
for the failure mode that established this invariant.

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
