# Reserve observation analysis source

Prepared authenticated `POST reserve-observation-analysis-source` reserves exact
source occupancy for an immutable photo/audio candidate. It does not admit or
execute an analysis. Native photo V2/audio V3 have a durable handoff and
retained injected reservation service, but no composition/UI/scheduler caller is
installed. Composition and deployment remain separate.

`route.ts` owns authenticated HTTP parsing and sanitized responses; `index.ts`
registers it through `serveEdge`. The shared `sourceReservationRepository`
performs the sole privileged RPC, `reserve_owned_observation_analysis_source`,
with verified `user.id`, the exact original candidate and reader11. The SQL
routine owns locks, replay, owner/deletion fences and the default-false gate.

The existing schema1 request has exactly `schema_version`, `input`,
`fingerprint_version` and `fingerprint`. Input is existing executable InputV2
photo or InputV3 audio with immutable source identity. Actual request bytes are
bounded to1MiB. The scoped service transport bounds actual streamed responses
to2KiB and the RPC to five seconds; the adapter strictly validates the response
against the original candidate and owner. It performs no automatic retry,
provider request, quota mutation or fallback.

All responses are private/no-store. Exact reserved/held/unavailable observations
return200 and confer no execution permission. Invalid candidate/JSON returns400,
oversized body413, unsupported content type415, wrong method405 and failed
authentication401. Unknown/lost/malformed/RPC/cancelled answers return
sanitized503; missing, foreign and deleted database scope are not distinguished.
An error is not proof of vacancy, retirement or release. A lost answer may
conceal committed occupancy: retain the identical candidate for explicit
recovery, never remint or infer permission for a successor.

The route tests exercise the real scoped SDK fetch boundary with synthetic
responses: authenticated owner and fixed reader, closed receipts, body limits,
malformed and foreign replies, one call on503/lost reply, and actual chunked
response overflow cancellation. Codec and adapter tests own fingerprint parity,
immutable snapshots, five-second deadline and cancellation races. The explicit
CI type-check and helper-test lists include this route suite. See the canonical
[API contract](../../../../docs/backend-and-data/05-api-contracts.md).

A received exact `analysis_history_operation_conflict` from the source RPC is
preserved as a typed conflict (HTTP409 for reservation). It is not a vacancy or
release receipt and never permits replacement or dispatch. Other RPC failures
remain sanitized unavailable errors.
