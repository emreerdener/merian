# update-scan-context

Authenticated deferred-context endpoint for a scan already accepted by the
durable client/server ingestion pipeline. It allows slow WeatherKit or reverse
geocoding work to finish after identification has started, without delaying the
first Gemini request or making a second model call.

## Request

`POST /functions/v1/update-scan-context`

```json
{
  "scan_id": "a1b2c3d4-0000-4000-8000-000000000000",
  "gps_elevation": 42.5,
  "weather_temperature_f": 68.0,
  "weather_condition": "Partly Cloudy",
  "semantic_location": "Zilker Park"
}
```

`scan_id` is required and must be a UUID. At least one valid optional field is
required. camelCase aliases are accepted. Validation limits are:

- `gps_elevation`: `-500...9500`
- `weather_temperature_f`: `-200...200`
- `weather_condition`: non-empty, at most 120 characters
- `semantic_location`: non-empty, at most 240 characters

The endpoint intentionally does not accept raw coordinates, media, public
location-sharing policy, or arbitrary scan columns.

## Authentication And Ownership

The route injects the opt-in `claimsAuth.ts` authenticator, which verifies the
ES256 JWT signature and issuer, audience, expiration/not-before, role, and
`sub`. Anonymous and authenticated owners are allowed; public service-role use
is rejected. The request body does not choose a user. The claims-auth policy is
not imported by the universal Edge wrapper; it uses the same pinned Supabase SDK
as the rest of the fleet.

The Edge handler calls service-role-only `apply_or_stage_scan_context` with the
verified `user.id`. Direct RPC execution is revoked from `PUBLIC`, `anon`, and
`authenticated`.

## Apply-Or-Stage Behavior

- If the owner's `scans` row exists, allowed context fields are patched and the
  response is `{ "success": true, "applied": true }`.
- If the owner's ingestion job exists but the scan insert is still pending, the
  fields are upserted into `scan_deferred_context_updates` and the response is
  `{ "success": true, "applied": false }`.
- A `BEFORE INSERT` trigger merges staged context into the matching owner scan
  and removes the staging row.
- If the server has not claimed the scan yet, the RPC error is returned as
  `409`. The iOS `CaptureSubmissionDeferredContextService` first retains the
  context in the durable local queue, then performs at most one remote retry
  after 500 ms. Endpoint, transport, or task cancellation is terminal and does
  not start that retry; the local copy remains the durable fallback.

The staging table has RLS enabled and no direct client grants. It deliberately
does not foreign-key `user_id` to `public.users`, because the first anonymous
scan may claim ingestion before the background ghost-user upsert completes.
Ownership is established by verified claims plus the matching ingestion job or
scan row.

## Native Caller And Verification

On iOS, `Core/Network/Endpoints/MerianNetworkClient+ScanEnrichment.swift` owns
`updateDeferredScanContext` request construction and the existing 15-second,
body-ignored HTTP call. The client sends only supplied optional context fields;
the validation and owner-scoped apply-or-stage rules above remain server-owned.
`CaptureSubmissionDeferredContextService` retains local persistence,
cancellation, and the bounded retry described above; the endpoint extension does
not own that workflow.

See the
[canonical API contract](../../../../docs/backend-and-data/05-api-contracts.md#deno-update-scan-context-edge-node),
[Capture Submission ownership](../../../../apps/ios/Merian/Features/Capture/Submission/README.md),
and the
[native focused matrix](../../../../apps/ios/Merian/Core/Network/README.md#enrichment-export-and-feedback-verification)
for request, transport, and caller-policy coverage.

## Deployment And Verification

Apply `20260715153946_reduce_identification_latency_round_trips.sql` before
deploying this function. Its `config.toml` entry uses `verify_jwt = false`
because the function performs the stricter claims verification itself.

```sh
deno check --config services/supabase/functions/deno.json services/supabase/functions/update-scan-context/index.ts
deno test --config services/supabase/functions/deno.json --allow-env --allow-net services/supabase/functions/_tests/auth.test.ts services/supabase/functions/_tests/migrationMediaContract.test.ts
```
