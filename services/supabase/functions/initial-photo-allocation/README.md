## October 29 — native v2 transport candidate

The inactive native owner and authenticated adapter now support explicitly
reserved v2 create/status. That owner/transport checkpoint passed Engine review
and 17 methods / 49 cases. The inactive Capture composition now selects v2 and
passed focused native qualification: 9 methods / 22 cases. Engine cleared
production; the corrected test-macro failure remains retained. The ordinary
factory remains disabled. The
[scan transport contract](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-29--native-v2-transport-integration-candidate)
owns dispatch, durable reservation, exact recovery and remaining integration.

## Native enrichment status — October 29

An explicit inactive native reservation/persistence candidate passed focused
native qualification: 13 methods / 38 cases. The
[transition contract](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#native-allocation-enrichment-inactive-candidate)
owns its accounting and recovery rules. Ordinary HTTP requests remain v1; older
notes below describe the projection-only checkpoint. No transfer or execution
capability is enabled.

# Initial photo allocation

Local candidate only: authenticated photo create/status facade, not deployed,
activated or installed in the ordinary app factory. An inactive Capture caller
and durable v1 allocation owner have local validation evidence. The canonical
wire and recovery rules live in
[API contracts](../../../../docs/backend-and-data/05-api-contracts.md#october-28--initial-photo-allocation-http-candidate).
The [v1 schema](./schema-v1.json) and [v2 schema](./schema-v2.json) own the
closed app projections; the existing
[CPM contract](../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md)
owns exact content and server assignment semantics.

`route.ts` uses the shared verified-session/body/error boundary. `handler.ts`
keeps private diagnostics out of the response. `db.ts` calls only the existing
service-only create/status RPCs with bounded deadlines and no retries.
`contract.ts` validates the complete private assignment before projecting the
minimal receipt. V2 additionally projects the complete ordered
role/reference/object identity cohort; neither version returns storage keys,
URLs or execution authority. Status may terminalize expiry; it is not
mutation-free.

Do not use this endpoint as an upload, execution or local-release capability.
The native request/caller/persisted receipt remain v1. The inactive v2 decoder
checks mapping association and saved identity, but durable enrichment must first
reserve metadata/revision capacity. See the
[current v2 contract](../../../../docs/backend-and-data/05-api-contracts.md#october-29--versioned-photo-allocation-role-projection-inactive).
Physical transfer, remote write closure and admission remain pending.

Run the focused synthetic tests from the repository root:

```sh
deno test --frozen --config services/supabase/functions/deno.json --allow-env --deny-net services/supabase/functions/initial-photo-allocation/*_test.ts
```

These tests cover authenticated fixed RPC calls, exact assignment projection,
closed requests, lost replies, cancellation, response bounds and opaque holds.
They do not prove hosted allocation, native persistence, physical media transfer
or complete photo qualification. Deployment and PR116 holds remain unchanged.
