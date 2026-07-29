# Species Observation Stats

Returns public, global iNaturalist observation aggregates for one canonical
Merian dictionary species. The Insight Sheet and Species Dictionary use this
endpoint for public observation charts. Local Merian scan history stays on the
device and must never enter this route or its cache.

## Request

Preferred transport is an authenticated `GET` from the first-party app:

```text
/functions/v1/species-observation-stats?species_id=1cf79982-e5ee-4e3d-8d65-274527e6ae01&scientific_name=Danaus%20plexippus
```

`POST` JSON remains supported for compatibility:

```json
{
  "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
  "scientific_name": "Danaus plexippus"
}
```

POST bodies are stream-bounded to 4 KiB before JSON decoding. Both fields are
required:

- `species_id` must be a canonical Merian `species_dictionary.id` UUID using an
  RFC variant and UUID version 1...8. PostgreSQL generates UUIDv4 dictionary
  rows today; accepting UUIDv7 keeps the boundary compatible with newer
  identifier sources instead of rejecting them before database ownership/name
  verification.
- `scientific_name` is trimmed, internal whitespace is collapsed, and the result
  must be 1...160 characters.
- The database compares the normalized name with the canonical name belonging to
  `species_id`. Unknown IDs and mismatched names return `404`.
- A caller-controlled name is never used directly in an observation query.
- The first-party iOS client rejects a malformed UUID, an empty/overlong name,
  or a response whose schema/identity does not match the request before writing
  its in-memory cache.

The database returns the canonical name and stored iNaturalist taxon ID. When
the provider ID is not stored, the lease owner may perform one exact `/v1/taxa`
lookup using that database-owned name. Observation and histogram requests run
only with a positive `taxon_id`; there is no `taxon_name` fallback.

## Authentication and Rate Limits

`config.toml` intentionally keeps `verify_jwt = false` because the response is
public species-level data. That does not make provider work unbounded:

- no Authorization header or the project publishable/anon key: IP limits apply;
- a valid user JWT: both user and IP limits apply;
- a malformed, expired, or otherwise invalid supplied user token: `401`;
- raw addresses are HMACed inside the isolate with a server-only Supabase key, a
  species-stats-specific purpose, and a daily rotation. Raw addresses are never
  stored.

The hosted Supabase gateway is the trusted source of `x-real-ip`,
`cf-connecting-ip`, and `x-forwarded-for`. A self-hosted or custom proxy must
overwrite those headers instead of forwarding caller-supplied values. If no
trusted address is present, requests share a conservative `unavailable` bucket
rather than bypassing the IP limit.

`preflight_species_observation_stats_request(...)` atomically consumes the IP
budget before the function attempts optional user-token validation. This keeps
malformed-token floods from turning the public endpoint into an Auth request
amplifier. A verified user is then charged by the authorization RPC.

Database-owned fixed-window policies:

| Boundary                                |      Limit |
| --------------------------------------- | ---------: |
| All requests per authenticated user     |  60/minute |
| All requests per IP hash                | 120/minute |
| Cold populations per authenticated user |  12/minute |
| Cold populations per IP hash            |  30/minute |
| Cold populations across the service     |   4/minute |

Limits are enforced atomically by
`preflight_species_observation_stats_request(...)`,
`authorize_species_observation_stats_request(...)`, and
`claim_species_observation_stats_population(...)`. `429` responses include
`Retry-After: 60` and are `private, no-store`.

Every authorization, lease, finalization, and cache-read database call is
client-aborted after five seconds. The privileged RPCs also set a five-second
PostgreSQL `statement_timeout`, so a lost Edge request cannot leave unbounded
database work behind.

## Response

```json
{
  "schema_version": 2,
  "data": {
    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
    "scientific_name": "Danaus plexippus",
    "source": {
      "provider": "inaturalist",
      "scope": "global",
      "inaturalist_taxon_id": 48662,
      "fetched_at": "2026-07-24T12:00:00.000Z"
    },
    "status": "fresh",
    "total_observations": 450448,
    "last_observation_date": "2026-07-24",
    "fetched_at": "2026-07-24T12:00:00.000Z",
    "provider_errors": [],
    "seasonality": [{ "month": 7, "count": 1200 }],
    "history": [{ "year": 2026, "month": 7, "count": 1200 }],
    "life_stage": [
      {
        "key": "adult",
        "label": "Adult",
        "values": [{ "month": 7, "count": 100 }]
      }
    ],
    "sex": [
      {
        "key": "female",
        "label": "Female",
        "values": [{ "month": 7, "count": 12 }]
      }
    ]
  }
}
```

Schema version 2 makes dictionary UUID/name binding mandatory and introduces the
bounded population contract. The response fields remain backward-compatible with
version 1; clients must ignore additive unknown fields. The current iOS client
requires schema version 2 or newer and verifies that the returned UUID and
normalized scientific name equal the requested pair. A legacy or mismatched
response fails closed and is not memoized.

Status values:

- `fresh`: all requested provider buckets completed and useful data exists.
- `no_data`: the exact taxon could not be resolved or the provider completed
  with no observations. This is a negative cache result.
- `partial`: useful core data exists while annotations refresh, or some provider
  buckets failed. Provider errors with no useful data become `unavailable`, not
  an empty `partial` result.
- `stale`: usable cached data was returned while one lease owner refreshes it.
- `unavailable`: provider resolution/population failed and no usable data
  existed. This outcome is briefly cached to damp provider incidents.

## Provider and Memory Budgets

The function uses only these global public iNaturalist endpoints:

- `/v1/taxa` for an exact canonical-name mapping when the dictionary lacks an
  ID;
- `/v1/observations` for total and most recent observation;
- `/v1/observations/histogram` for seasonality, rolling history, life stage, and
  sex.

Every outbound provider request receives an abort signal. Budgets are:

- 5 seconds per provider fetch;
- 15 seconds for foreground core population;
- 45 seconds for background annotation/full refresh;
- 1 MiB maximum per provider response body, enforced while streaming.

The fixed seven-year history and fixed annotation set bound histogram work.
Requests keep the provider-friendly one-second spacing while budget remains.

Annotation mappings:

| Group      | `term_id` | Value            | `term_value_id` |
| ---------- | --------: | ---------------- | --------------: |
| Life Stage |         1 | Adult            |               2 |
| Life Stage |         1 | Teneral          |               3 |
| Life Stage |         1 | Pupa             |               4 |
| Life Stage |         1 | Nymph            |               5 |
| Life Stage |         1 | Larva            |               6 |
| Life Stage |         1 | Egg              |               7 |
| Life Stage |         1 | Juvenile         |               8 |
| Life Stage |         1 | Subimago         |              16 |
| Sex        |         9 | Female           |              10 |
| Sex        |         9 | Male             |              11 |
| Sex        |         9 | Cannot determine |              20 |

## Cache and Distributed Population

`public.species_observation_stats_cache` is keyed by
`species_id + inaturalist + global`.

| Final status  | Fresh TTL |
| ------------- | --------: |
| `fresh`       |    7 days |
| `no_data`     |  24 hours |
| `partial`     |    1 hour |
| `unavailable` | 5 minutes |

Positive data may be served stale for the original seven-day TTL plus 30 more
days. An expired `no_data` result may be served stale for up to seven days while
refreshing. `unavailable` is never a stale fallback. If a refresh fails while a
positive payload is still within its 37-day retention ceiling, finalization
preserves the payload and original `fetched_at`, records the latest provider
error in row-level cache metadata, marks the row/payload `stale`, and sets a
five-minute retry backoff. A cold miss, negative row, or positive row older than
that ceiling receives the normal five-minute `unavailable` cache instead.

Cold and stale population uses
`internal.species_observation_stats_population_leases`:

1. `claim_species_observation_stats_population(...)` takes a short transaction
   advisory lock and issues a 90-second UUID lease.
2. Other isolates see the active lease and perform no provider work.
3. `finalize_species_observation_stats_population(...)` compares the UUID token,
   validates canonical payload identity, optionally stores an exact taxon ID,
   upserts the cache, and removes the lease in one transaction.
4. An expired owner cannot overwrite a newer generation because its token no
   longer matches.
5. An `unavailable` refresh cannot erase a retained positive payload: the same
   transaction converts that row to `stale`, keeps its original age, and applies
   only the short retry backoff.
6. A post-population cache check in the claim RPC closes the race between an
   Edge cache read and another owner's finalization.
7. Database finalization failures return `503` and leave the lease to expire;
   they are not retried as a downgraded `unavailable` payload.

Rate counters and abandoned leases are pruned hourly in bounded batches.

Successful complete/negative responses send:

```http
Cache-Control: public, max-age=300, s-maxage=86400, stale-while-revalidate=604800
Vary: Accept-Encoding
```

`partial`, `stale`, and `unavailable` responses use the shorter public window:

```http
Cache-Control: public, max-age=30, s-maxage=60, stale-while-revalidate=300
Vary: Accept-Encoding
```

The successful payload is public and identity-independent, so it deliberately
does not vary by `Authorization`; doing so would create one cache entry per
bearer token and amplify origin traffic. All validation, authorization,
rate-limit, and availability errors remain `private, no-store` and vary by
Authorization.

## Error Contract

| HTTP | Code                                | Meaning                                     |
| ---: | ----------------------------------- | ------------------------------------------- |
|  400 | `species_stats_invalid_request`     | Invalid UUID/name/hash input                |
|  401 | `invalid_session_token`             | Invalid supplied user credential            |
|  404 | `species_stats_species_not_found`   | Unknown dictionary ID or name mismatch      |
|  413 | validation message                  | Compatibility POST body exceeds 4 KiB       |
|  429 | `species_stats_rate_limited`        | Request or cold-population budget exhausted |
|  503 | `species_stats_refresh_in_progress` | Another isolate owns the cold lease         |
|  503 | `species_stats_unavailable`         | Database/security boundary unavailable      |

`429` and `503` retry responses include `retry_after_seconds` and `Retry-After`.
Error responses are never publicly cached.

## Privacy Contract

Never add local scan IDs, user IDs, Explore IDs, field notes, locations, local
media, preferred-name overrides, or local observation counts to the request,
response, logs, or cache. The rate tables receive only a verified user UUID when
present and a daily purpose-separated IP HMAC. They are private to the database
owner and are not part of the public payload.

## Verification

```sh
deno fmt --check \
  services/supabase/functions/_shared/clientAddress.ts \
  services/supabase/functions/species-observation-stats \
  services/supabase/functions/_tests/speciesObservationStatsCoverage.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsMigrationContract.test.ts
deno lint --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/clientAddress.ts \
  services/supabase/functions/_shared/clientAddress_test.ts \
  services/supabase/functions/species-observation-stats \
  services/supabase/functions/_tests/speciesObservationStatsCoverage.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsMigrationContract.test.ts
deno test --frozen --config services/supabase/functions/deno.json \
  --allow-read=services/supabase/functions,services/supabase/migrations,services/supabase/config.toml \
  services/supabase/functions/_shared/clientAddress_test.ts \
  services/supabase/functions/_shared/mediaBudgets_test.ts \
  services/supabase/functions/species-observation-stats/db.test.ts \
  services/supabase/functions/species-observation-stats/security.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsCoverage.test.ts \
  services/supabase/functions/_tests/speciesObservationStatsMigrationContract.test.ts
supabase --workdir services test db --local \
  services/supabase/tests/species_observation_stats_security.sql
```

The deploy workflow also runs static route coverage, migration-contract tests,
the global privileged-routine catalog test, and this pgTAP security test.
