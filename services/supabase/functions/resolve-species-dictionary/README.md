# Resolve Species Dictionary

`POST /resolve-species-dictionary` upgrades a name-only reference page to a
canonical dictionary identity. `withEdgeHandler` validates the user JWT before
any lookup or write; `verify_jwt = false` delegates authentication to that
handler. The public `/species-dictionary` read remains read-only.

Request: `{ "scientific_name": "Fixtureus synonym" }`. Names must be nonempty
and at most 160 characters. The small shared JSON body limit applies. Client
taxonomy, IDs, display text, and ownership claims are not accepted as proof.

Successful response (the returned scientific name is the saved dictionary name,
which can predate the currently accepted name on an existing record):

```json
{
  "schema_version": 1,
  "requested_scientific_name": "Fixtureus synonym",
  "species_id": "00000000-0000-4000-8000-000000000001",
  "scientific_name": "Fixtureus accepted"
}
```

All responses are private/no-store. Existing public rows return directly;
existing nonpublic rows fail closed. A missing name uses the shared
`_shared/verifiedSpecies.ts` validator: exact GBIF species match, accepted
identity, and an independently checked accepted key for synonyms. Each of the
at-most-two provider reads has a six-second deadline and 64 KiB response cap.
There is no Gemini call, AI reservation, or scan allowance consumption.

Service-only admission uses the existing pruned atomic counters under separate
non-AI buckets: six requests per user per minute, sixty per user per UTC day,
and 120 globally per minute, including existing-record hits. Exhaustion returns
429; malformed input returns 400; unavailable species returns 404; an identity
that cannot be verified returns 422; provider failures return 503. Existing
authentication and shared safe error envelopes apply.

`resolve_verified_dictionary_species(jsonb)` inserts one verified taxon with
`ON CONFLICT DO NOTHING`, then checks the surviving public identity. A bounded
indexed GBIF-key lookup under a transaction advisory lock reuses an existing
UUID even when its saved scientific name predates the accepted name. Ambiguous
preexisting taxon-key duplicates fail closed for explicit repair; the resolver
never merges them. During verified persistence, an exact-name legacy record with
no GBIF key receives only the verified missing key, so later accepted-name
changes reuse its UUID. A conflicting stored key is never overwritten. Identity
conflicts and ambiguous keys return the same nondisclosing 404 as unavailable
species. The resolver never overwrites curated content or stores speculative
relationships. The existing transaction-local candidate guard permits reference,
habitat, and tag hydration but suppresses recursive lookalike generation and
same-genus linking. Repeated or concurrent opens, including accepted-name
variants, reuse one UUID across resolver calls. Historical writers do not share
this advisory lock; visible duplicate keys fail closed, but enforcing global
uniqueness would require a separate historical-data migration. A cancelled
request stops before persistence when cancellation is observed; an already
committed record remains reusable.

iOS verifies the echoed request name and canonical UUID, then reads by that UUID
and requires the returned detail ID to equal the receipt. This permits verified
synonyms without relaxing the ordinary Dictionary response validator or caching
an alias under the wrong name. Older name-only Insight entries use the same
route automatically. The page retains public reference content while resolving
and offers Retry after failure. It never starts chat or loads a conversation
automatically.

Validation owners are `handler_test.ts`, `db.test.ts`, the shared verification
tests in `refresh-species-model-content/lookalikeCandidates.test.ts`,
`_tests/speciesDictionaryResolutionMigrationContract.test.ts`, and
`services/supabase/tests/species_dictionary_resolution.sql`. The loopback-only
`_tests/speciesDictionaryResolutionDb.test.ts` additionally verifies concurrent
accepted-name variants reuse one UUID for both new and legacy missing-key
records when `SUPABASE_DB_TEST_URL` is configured. Native coverage lives in the
Dictionary page-state, service, and response-validator suites. Run the complete
Edge/tooling/catalog and iOS gates before release. Apply the new migration
before deploying this endpoint, then distribute the iOS caller. Source
validation does not authorize deployment or production data repair. The
[resolution release gate](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#species-dictionary-resolution-release-gate)
owns rollout, hosted smoke, and recovery requirements.
