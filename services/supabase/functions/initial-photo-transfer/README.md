# Dormant initial photo transfer facade

Source-only authenticated `issue`/`status` composition. There is deliberately no
`index.ts`, `serveEdge`, deployment registration, installed policy/credentials,
or ordinary native caller. The inactive native adapter is documented in the
[current scan contract](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-31--inactive-native-ticket-transport).
This folder does not expose an endpoint. Provider enforcement remains
unqualified and all existing release controls apply.

The
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#dormant-authenticated-photo-transfer-facade--october-30)
owns request/response semantics; the
[scan guide](../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#october-30--dormant-authenticated-transfer-facade)
owns integration status and qualification exclusions.

- `schema-v1.json` and `contract.ts` define two closed requests. Issue includes
  the exact frozen candidate; status requires only saved scan/assignment/object
  identity and original receipt clocks. Neither accepts an owner, policy or
  backend selector.
- `route.ts` uses the existing verified-session wrapper and bounded body parser.
  `handler.ts` recovers the authenticated allocation through the existing
  allocation repository, then calls the existing CPM issuer or status bridge.
- `catalog.ts` snapshots trusted configuration and pins one policy/profile per
  backend tuple. No configuration loader or entries are installed. Historical
  mappings must not be replaced during rotation; removed/unknown tuples deny
  fresh issuance. Status never resolves this catalog.
- `fixtures.ts` contains synthetic test data only. The concrete database-adapter
  tests intercept all requests and deny network access.
  `native_contract_test.ts` reads only the named Swift golden fixtures for
  executable request parity.

Run the focused tests from the repository root:

```sh
deno test --frozen --config services/supabase/functions/deno.json --allow-env --deny-net --allow-read=apps/ios/MerianTests/Core/Network/Transport services/supabase/functions/initial-photo-transfer/*_test.ts
```

An unavailable or lost issue reply remains uncertain. Recover the same write
status; do not repeat issuance, renew clocks or release retained source bytes.
No status result is upload, inference or cleanup authority. The inactive native
composition includes trusted destination resolution and durable PUT-started
admission; complete runtime and real-app qualification remain required before
this facade can participate in an accepted journey.
