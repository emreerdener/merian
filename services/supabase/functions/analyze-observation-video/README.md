# Video analysis submission

Verified JWT owner; closed V4 JSON; private status only. The route composes the
service-only begin RPC and separate video worker. Whole-cohort preflight
precedes one durable dispatch/invoke; received outcome precedes settlement and
awaited lease release. Unknown execution stays held without retry or refund.

All gates remain disabled. No deployment, scheduler, native activation or device
qualification is supplied. `index.ts` starts the route, `route.ts` owns
HTTP/auth, `db.ts` owns RPC composition. The shared video execution owner is
`_shared/analysisHistory/videoExecution.ts` and materialization is in
`videoProduction.ts`.

See the
[canonical API contract](../../../../docs/backend-and-data/05-api-contracts.md#gated-video-edge-execution)
for payloads, fences and deadlines. Route tests use synthetic identities and
mocked transport; no real provider or hosted service is invoked.
