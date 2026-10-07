# Retire observation analysis

Prepared authenticated `POST retire-observation-analysis` retires one exact,
never-dispatched admitted analysis. `withEdgeHandler` authenticates the owner;
body-supplied owners are rejected. A scoped service client calls only
`retire_owned_observation_analysis_execution` with reader 9. The SQL routine
owns canonical locks, current funding/execution predicates, atomic settlement,
private-evidence erasure obligations and immutable receipt replay.

The schema-1 request contains exactly `operation_id`, `observation_id`,
`analysis_id`, nullable `source_analysis_id`, `request_digest` and
`schema_version`. The exact response adds only
`state: "retired_before_dispatch"`. Original child/source/digest and the
retained retirement UUID cannot change on retry. The HTTP body is capped at 2
KiB; actual streamed RPC responses at 4 KiB. The one RPC attempt has a
five-second deadline, propagates caller cancellation and returns even if abort
acknowledgement stalls. It has no retry, provider call or taxonomy work.

All responses are private/no-store. Invalid requests return 400; missing,
foreign and deleted work share 404; known operation conflicts return 409;
unknown, malformed or interrupted upstream outcomes return sanitized 503. **None
of those errors proves retirement.** A lost reply may hide a committed
transaction; recover only by explicitly replaying the identical retirement
request. Do not remint, infer success from absence or dispatch the analysis.

The default-false SQL gate remains disabled. This endpoint is prepared source,
not deployed or installed into native actions. Unknown execution, absent-request
sealing, other terminal remediation and native durable action admission remain
separate contracts. See the
[API contract](../../../../docs/backend-and-data/05-api-contracts.md).
