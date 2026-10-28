# Initial photo allocation

Local candidate only: authenticated photo create/status facade, not deployed,
activated or called by the app. The canonical wire and recovery rules live in
[API contracts](../../../../docs/backend-and-data/05-api-contracts.md#october-28--initial-photo-allocation-http-candidate).
The [schema](./schema-v1.json) owns the closed app projection; the existing
[CPM contract](../../../../docs/rfcs/client-prepared-photo-content-contract-2026-10-27.md)
owns exact content and server assignment semantics.

`route.ts` uses the shared verified-session/body/error boundary. `handler.ts`
keeps private diagnostics out of the response. `db.ts` calls only the existing
service-only create/status RPCs with bounded deadlines and no retries.
`contract.ts` validates the complete private assignment before projecting the
minimal receipt. Status may terminalize expiry; it is not mutation-free.

Do not use this endpoint as an upload, execution or local-release capability.
Native receiving-slot allocation claims and release fences are the next
integration requirement. Until they exist, the app remains at local receipt.

Run the focused synthetic tests from the repository root:

```sh
deno test --frozen --config services/supabase/functions/deno.json --allow-env --deny-net services/supabase/functions/initial-photo-allocation/contract_test.ts services/supabase/functions/initial-photo-allocation/route_test.ts
```

These tests cover authenticated fixed RPC calls, exact assignment projection,
closed requests, lost replies, cancellation, response bounds and opaque holds.
They do not prove hosted allocation, native persistence, physical media transfer
or complete photo qualification. Deployment and PR116 holds remain unchanged.
