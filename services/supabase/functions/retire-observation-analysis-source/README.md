# Retire observation analysis source

Prepared authenticated `POST retire-observation-analysis-source` retires one
exact unfunded source reservation. It is separate from reader10 funded
`retire-observation-analysis`. No native caller or deployment is included.

`request.ts` owns the public envelope: exactly `schema_version: 1`, `candidate`
and `operation_id`. The candidate is the full original four-key source
reservation request, including unchanged photo/audio input and fingerprint. The
retirement UUID must be saved before first HTTP attempt and retained on
recovery. It cannot equal the parent, source or child UUID. The parser snapshots
both candidate and operation before awaits, validates the fingerprint and
rejects owner, SQL identity-only tuple, receipt, funding or replacement fields.

`route.ts` authenticates with `withEdgeHandler`, bounds actual input to1,048,663
bytes (original candidate1MiB plus87-byte minimal envelope), and creates a
scoped five-second/2-KiB streamed-response service client. The shared
`sourceReservationRepository.retireUnfunded` alone builds the existing frozen
SQL request and calls `retire_owned_observation_analysis_source` with verified
owner and reader11. SQL owns locks, exact replay, never-admitted predicates,
immutable proof and occupancy release; its gate stays false.

Only an exact `retired_unfunded` receipt returns200. Other states, including
funded `retired_before_dispatch`, held/unavailable, malformed or foreign
replies, timeout, cancellation and transport loss return sanitized503. Known
operation conflict returns409; it proves neither release nor replacement
authority. Invalid JSON/schema/fingerprint/UUID association returns400,
oversize413, unsupported content type415, method405 and authentication401. Every
response is private/no-store. A lost answer can conceal committed retirement;
explicit recovery retains the same full candidate and operation, with no
automatic retry, remint, refund, successor or provider invocation.

Tests cover scoped actual RPC arguments, same-operation recovery after loss,
full-candidate snapshots, aliases/SQL tuples, exact/+1 body limits, chunked
response overflow cancellation, uncooperative timeout, sanitized errors and
wrong receipt variants. Both CI type-check and helper lists include them. See
the canonical
[API contract](../../../../docs/backend-and-data/05-api-contracts.md).
