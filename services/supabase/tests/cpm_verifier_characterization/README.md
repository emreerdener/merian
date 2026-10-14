# CPM representative verifier: local qualification candidate

Current October 14 follow-up: [runtime packaging](runtime/README.md) adds a
local-only deployment package, test-key authentication/private GET adapters,
singleton entrypoint and an operator driver. It remains outside the deployment
fleet. See the
[hosted approval packet](../../../../docs/rfcs/client-prepared-media-test-auth-hosted-packet-2026-10-14.md).
No app session is required. Product Auth/identity overhead is excluded. Nothing
is deployed or activated. The original construction description below records
the earlier injected-adapter checkpoint; its claims of absent runtime adapters
are historical. Runtime case 26 now runs first with genuine rejected
credentials; the earlier offline simulated schedule remains regression evidence.

## Original local checkpoint

This is the bounded local construction authorized on October 14, 2026 under
[the four-hour request](../../../../docs/rfcs/client-prepared-media-local-construction-request-2026-10-14.md).
It is not the complete verifier, an application route or a deployable function.
No `Deno.serve`, default network transport, credentials, environment reader or
hosted launcher is provided. Activation remains disabled, AWS unapproved and
product package/storage limits unchanged. The 160 MiB guard is not adopted.

## Composition and authority

| Piece            | Reused implementation                                                 | Local substitute / limitation                                                                                                                                                                                                                                                                   |
| ---------------- | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Request boundary | `withPublicEdgeHandler`, real error/metadata behavior                 | No `withEdgeHandler`: that wrapper unconditionally obtains privileged configuration.                                                                                                                                                                                                            |
| Authorization    | `bearerTokenFromAuthorizationHeader`, capability comparison           | `authenticate` is a trusted injected verifier returning a fixed operator alias, not caller-supplied identity. Local tests simulate verified identity, rejection and delay. Actual `requireAuth`/Auth transport and principal-to-alias binding are absent and must be reviewed before packaging. |
| Manifest         | `readBoundedJsonBody`, 4096-byte limit                                | Fixed run/case/fixture only; arbitrary keys/URLs rejected. Shared parser is byte-bounded but has no independently cancellable read deadline. A stalled body may keep a request pending; checks after parsing prevent a late GET. This is not hostile ingress qualification.                     |
| Media            | `node:crypto` incremental SHA-256                                     | Pull-generated fixture streams, no full-file aggregation. No decoding, derivation or faithful-video provenance claim.                                                                                                                                                                           |
| Private GET      | Pinned `aws4fetch` signing only, fixed R2 endpoint/bucket/prefix/keys | Dummy credentials and injected transport in tests. Never `AwsClient.fetch`; one transport call, redirect mode `error`. No TLS, sockets, live credentials or object immutability measured.                                                                                                       |
| Telemetry        | TM-1 sample/stop logic and active timer                               | Injected fields/clock; no runtime memory budget or CPU measurement. P is `heapTotal + external`, partial V8 accounting. RSS is explicitly unavailable.                                                                                                                                          |
| Driver           | Fixed schedule, journal, bounded response parser                      | Direct injected transport to simulated workers. No real routing, invocation gateway or shared project load.                                                                                                                                                                                     |

The handler may invoke the trusted Auth adapter once and the private GET adapter
once. Future adapters must expose all outbound attempts, honor abort and have no
hidden retries; the reserved four handler outbound calls per invocation are an
accounting allowance, not proof about an unbuilt Auth adapter. Production
imports transitively include Supabase/Auth code; import-time behavior is
exercised with environment and network denied, but no privileged client is
constructed. No SQL, scan-token funding, admission, receipts, AI provider,
shared-asset deletion or iOS preparation path is invoked.

## Fixed finite workload

Two 64 KiB controls, two nine-request 32 MiB warm cohorts (320 seconds each),
two different-object concurrent pairs and one reader plus a fixed denied case
make 26 cases. Each driver group has at most two clients; no fixture can be
shared within a read pair. Groups advance only after both terminal
acknowledgements. Same-worker busy denial says only that its own request opened
no reader. The reader gate is local to one `createHandler` instance, not shared
by alias. Future packaging must construct exactly one handler instance per
physical worker and a unique worker alias; this local result cannot prove hosted
isolate or route uniqueness. Worker aliases report simulated topology; no forced
affinity or replacement requests fill routing gaps.

The driver reserves 48 setup/metrics calls, then five calls per invocation
before sending (178 ordinary reservations total), with 64 cleanup calls held
separately; total never exceeds 256 and ordinary never exceeds 192. It reserves
all three fixture uploads plus each scheduled media read conservatively within 2
GiB. These are ledger reservations only; this candidate performs no setup,
upload, metrics query or external cleanup. Cleanup reservations record manual
operator work, never execute it, and stop accepting reservations 15 minutes
after the first terminal run state. The future operator must complete work
within that window; no credential/route cleanup adapter is constructed.

Fixtures are exactly two 32 MiB objects and one 64 KiB object. Each 64 KiB chunk
is filled with `(seed + chunkIndex) % 251`; seeds and independent expected
SHA-256 identities are in `policy.ts`. Local checks generate/release chunks on
demand; no media fixture files are retained. Maximum accepted chunk is 1 MiB and
maximum chunk count is 65,536; these are candidate stream-processing bounds, not
product asset limits. Actual transport chunking is still unqualified.

## Closure, uncertainty and restart

A verifier owns acquisition, reader, hash and timer until acquisition/read work
settles, cancellation (when needed) settles, `reader.closed` settles, and the
reader lock/hash are released. A successful acknowledgement follows timer and
slot release. This proves application-owned promise/stream cleanup only, not
native socket release or garbage collection. Cancellation failure keeps the
worker held and halted. An abort-ignoring injected transport can remain pending;
no positive closure or replacement read follows it.

The driver journals the entire pair and reservations before sending. Invalid,
lost, late, oversized, mismatched or incomplete acknowledgements stop the run.
Outstanding obligations survive a driver timeout; late responses are cleaned up
but cannot authorize another call. Pending cleanup promises remain exposed for
inspection. An existing, partial or truncated journal blocks restart; no
resumption/replay path exists. The file journal uses exclusive creation,
complete writes and file/directory synchronization. Tests exercise process-level
reopen; power-loss/filesystem durability is not established by a unit test.

96 MiB sampled P stops further work. Four same-worker ordered quiescent samples
whose three increments are all positive and total at least 8 MiB also stop.
Worker-wide stop aborts all live requests, retaining the active reader slot
until cleanup settles. Absolute elapsed-time checks supplement timers around
GET/read/ hash and before terminal success, but cannot preempt blocked native
work. Sampling ends on abort/deadline/terminal response. Component maxima and
maximum sampled P can occur at different instants. They are observed samples,
not true peaks; blocked event loops, short peaks and native allocations can be
missed. No forced GC or one-second CPU/30-second physical termination claim is
made.

## Local check commands

Use the installed pinned Deno 2.9.4, existing frozen configuration and cache.
Run from the repository root; all results are synthetic. No network,
environment, subprocess or general filesystem capability is granted to the
tests.

```sh
deno fmt --check services/supabase/tests/cpm_verifier_characterization
deno lint --config services/supabase/functions/deno.json services/supabase/tests/cpm_verifier_characterization
deno test --cached-only --frozen --config services/supabase/functions/deno.json --no-prompt --deny-net --deny-env --allow-read=.artifacts/client-prepared-media/verifier-local-candidate --allow-write=.artifacts/client-prepared-media/verifier-local-candidate services/supabase/tests/cpm_verifier_characterization
```

The scoped read/write grant is solely for tiny synthetic journal evidence. Deno
type-checks test roots and transitive imports. Separately check every candidate
module, including modules not imported by a test. The existing local deployment
selector must select zero functions for this candidate's exact changed-file set.
Do not interpret that scoped result as release clearance for the unrelated dirty
checkout or PR #116.

## Evidence and next boundary

Evidence, failed attempts, source/dependency manifests and review records live
under `.artifacts/client-prepared-media/verifier-local-candidate/`. A passing
local candidate supports a later exact packaging/installation request only.
Before hosted execution, the actual Auth adapter, runtime telemetry source,
private fixture readiness, expiry/identity configuration, operator stop and
credential/route cleanup paths need a separately approved exact candidate. No
construction, provisioning or execution of that hosted packet is authorized by
these local checks. Full CPM acceptance, native memory, CPU, ingress writer
closure, initial/reanalysis integration and later redesign remain open.
