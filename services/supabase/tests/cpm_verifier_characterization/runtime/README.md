# Local runtime packaging for CPM characterization

> Current October 14: the approved local campaign ran after exact independent
> and IC-1 concurrence, then stopped at the unchanged 8 MiB growth gate after
> approximately 42 seconds. One worker, five attempts, three verified reads; all
> four opened bodies closed and the container was removed. No retry. See the
> [exact result](../../../../../docs/rfcs/client-prepared-media-controlled-worker-result-2026-10-14.md).
> Post-run independent/IC-1 review concurs with the corrected report, including
> its shutdown defect. Sustained reuse and product acceptance remain open.
> Activation disabled, AWS/160 MiB unapproved, all other limits unchanged.
> Earlier status/approval statements below are historical.

> Current October 14 prelaunch finding: the user approved local preparation and
> execution only after exact-candidate review. The pinned runtime's default
> supervisor retires at half the configured lifetime, so the 900-second setting
> conflicts with the 682-second schedule. No campaign launched; allowance
> unused. See the
> [prelaunch finding and unapproved amendment](../../../../../docs/rfcs/client-prepared-media-controlled-worker-preflight-2026-10-14.md).
> Existing limits remain unchanged, activation disabled, AWS unapproved. Earlier
> approval/status notes below are historical.

> Current October 14 controlled-reuse proposal: the attended v1.77.0 run
> completed all 26 checks and cleanup, but all 25 reads reported different
> worker aliases. Hosted warm reuse, growth and physical read overlap remain
> unobserved. The user authorized only the
> [local controlled-worker proposal](../../../../../docs/rfcs/client-prepared-media-controlled-worker-reuse-proposal-2026-10-14.md)
> and independent/IC-1 review; construction and execution await approval.
> Activation disabled, AWS and 160 MiB unapproved, credentials retained,
> auto-prompts paused. Earlier status entries below are historical. No product
> acceptance, ownership or follow-up sequencing changes.

Current October 14 v1.77.0 evidence and proposed hosted runtime expectation are
in the
[latest reviewed packet](../../../../../docs/rfcs/client-prepared-media-runtime-177-hosted-packet-2026-10-14.md).
Executable candidate and staged package remain unchanged from `9c88cc72d`; CLI
2.109.1 / v1.74.2 bundling remains pinned. Local v1.77.0 execution passed
startup and two synthetic control reads; bulk/long-warm/concurrency acceptance
remains open. Both stored credentials are retained by explicit user decision;
temporary copies were removed. Earlier status below is historical. No new hosted
action is authorized.

Current correction: the original hosted attempt stopped; its route/settings were
removed. The user confirms both R2 keys remain active. The
[runtime diagnostics packet](../../../../../docs/rfcs/client-prepared-media-runtime-diagnostics-hosted-packet-2026-10-14.md)
supersedes the earlier preparation status below. Local testing now includes
network-disabled pinned user workers. Decorated Deno version strings are
accepted by a shared bounded header-safe validator. Startup 503 responses have
only a fixed failure marker; the operator result adds allowlisted status/header
booleans and fixed failure stages, never arbitrary bodies or exception text. The
`.artifacts/client-prepared-media/local-diagnostics/` probe has separate actual
candidate and synthetic-transport bundles; only `staged-01` is deployable. No
hosted action is authorized until a fresh exact packet is approved.

This directory packages a representative byte-verifier experiment. The human
authorized the test-only authentication revision and independent/IC-1 review on
October 14. Previous JWT-based preparation is retained as historical evidence.
No hosted operation is authorized. The canonical current packet is
[the corrected runtime diagnostics hosted request](../../../../../docs/rfcs/client-prepared-media-runtime-diagnostics-hosted-packet-2026-10-14.md).
Activation stays disabled; AWS, the 160 MiB total-memory guard and any product
limit changes remain unapproved.

## Owners and entrypoints

- `config.ts`: fixed Merian production-alpha target, seven experiment-only
  settings, dedicated test key, run capability/expiry and private bucket.
- `auth.ts`: bounded 64-hex test-key possession comparison; no product identity,
  Auth request, session, privileged client or retry. The all-zero key is
  reserved for first-call denial; the real key must be independent of the run
  capability and R2 credentials.
- `worker.ts`: runtime composition; positive partial V8 fields and bounded
  version metadata. `entrypoint.ts` constructs one module-level handler and
  registers once. Missing configuration fails closed before any network I/O.
- `transport.ts`: local driver sends only to the fixed test route, including a
  well-formed incorrect test bearer for case 26, sent first before fixture
  reads. It requires `test-run-key-v1` mode and runtime metadata, with no
  redirects. The handler's public 403 is distinct from a gateway refusal.
- `run.ts`: future operator-only launcher. It requires an explicit execution
  argument, fixed credentials supplied privately, and a fresh durable journal.
  Cases 1–2 precede the operator bulk-readiness barrier. The barrier shares the
  run expiry. Warm-cohort spacing is anchored after readiness; insufficient
  remaining time stops before bulk reads. It does not extend expiry or
  automatically upload.
- `stage.py`: offline manifest-based relocation into a single-function staging
  tree. No network, credentials, subprocesses or deployment. Rejects foreign
  modules, symlinks and existing output. Import aliases are derived from the
  reachable graph using exact root `functions/deno.json` pins; a closed subset
  of existing frozen npm lock records is copied with exact versions, integrity
  and dependency lists. Only standalone membership changes; the shared lock is
  untouched. This deliberately excludes unused fleet aliases from the standalone
  package; it does not change the fleet's generated configs.

No source is registered under the repository's `functions/` tree. The isolated
staged tree is the only deployable experiment package. Runtime local transitive
imports include dormant service-role helpers from `edgeHandler.ts`, but use
`withPublicEdgeHandler` and never construct the privileged client. No SQL,
provider, scan-token, receipt, original-media or shared-deletion implementation
is part of this experiment. No native/UI caller consumes this contract.

## Offline verification and reproducible staging

Run local checks from the repository root with Deno 2.9.4, frozen existing
configuration/cache and no environment or network capability. The owning parent
README gives the full candidate test command. Include this directory in those
checks. The entrypoint wiring test replaces `Deno.serve`, environment, memory
and fetch before importing; it opens no server or socket.

```sh
python3 -m unittest discover -s services/supabase/tests/cpm_verifier_characterization/runtime -p '*_test.py'
deno check --frozen --config services/supabase/functions/deno.json services/supabase/tests/cpm_verifier_characterization/runtime/*.ts
```

Generate a fresh local graph, then stage into a new directory. The graph and
stage must be generated from the reviewed frozen source set; recheck source
hashes after generation. These commands do not run the entrypoint or driver:

```sh
deno info --json --config services/supabase/functions/deno.json services/supabase/tests/cpm_verifier_characterization/runtime/entrypoint.ts > .artifacts/client-prepared-media/test-auth-revision/graph-final.json
python3 services/supabase/tests/cpm_verifier_characterization/runtime/stage.py .artifacts/client-prepared-media/test-auth-revision/graph-final.json .artifacts/client-prepared-media/test-auth-revision/staged-01
deno check --frozen --config .artifacts/client-prepared-media/test-auth-revision/staged-01/supabase/functions/cpm-verifier-characterization/deno.json .artifacts/client-prepared-media/test-auth-revision/staged-01/supabase/functions/cpm-verifier-characterization/index.ts
```

Generate a second graph from the staged entrypoint and verify graph closure and
unchanged source/packaged bytes before bundling:

```sh
deno info --json --config .artifacts/client-prepared-media/test-auth-revision/staged-01/supabase/functions/cpm-verifier-characterization/deno.json .artifacts/client-prepared-media/test-auth-revision/staged-01/supabase/functions/cpm-verifier-characterization/index.ts > .artifacts/client-prepared-media/test-auth-revision/staged-graph-06.json
python3 services/supabase/tests/cpm_verifier_characterization/runtime/stage.py --verify .artifacts/client-prepared-media/test-auth-revision/staged-graph-06.json .artifacts/client-prepared-media/test-auth-revision/staged-01
```

`staged-01` is retained evidence: use a new directory for regeneration, never
overwrite it. Record the staged manifest and offline ESZIP digest. Use only the
cached `public.ecr.aws/supabase/edge-runtime:v1.74.2` image, network none,
read-only source/npm/remote cache mounts and a separately bounded writable
output. No dependency cache is modified. No function is started during bundling.
An isolated temporary cache has a 128 MiB cap; the local container has a 512 MiB
memory limit, one CPU and a 30-second bundling timeout. These are local
packaging limits, not adopted product/runtime resource thresholds.

The prior JWT-based package and its failed intermediate bundles remain in
`.artifacts/client-prepared-media/runtime-packaging/`. Revised package and ESZIP
identities are in
`.artifacts/client-prepared-media/test-auth-revision/checkpoint.md`. No
dependency pins or product auth helpers change. This experiment excludes product
Auth network/SDK/identity overhead and cannot qualify the full product path. The
public gateway key is not evidence of caller identity.

## Future execution and operator barrier

Installation, secret mutation, fixture upload, execution and removal require the
exact hosted packet's separate human approval. No credentials are needed to run
any local check above. Run `entrypoint.ts` only in the explicitly authorized
network-disabled local harness with synthetic configuration; `run.ts` remains
hosted-approval gated.

The driver reads only the future process environment's run, capability, expiry,
test key and canonical public gateway key. It sends no user/session details to
local artifacts. The run ID must be a fresh opaque alias (not a person, email or
other personal identifier). Existing or partial journals refuse restart.

After the rejected-caller preflight and two valid controls, the operator must
review `preflight.json` (control Acks and observed Deno/V8 versions), available
runtime evidence and positive reader closure before bulk uploads. Write the
following _shape_ to `bulk-ready.json` only after all three fixed uploads have
positively completed and no writer remains. The identity values come from
`policy.ts`, never from a mutable request. This is an operator attestation:

```json
{
  "run": "opaque-run-alias",
  "writersClosed": true,
  "fixtures": [
    { "id": "a", "bytes": 33554432, "sha256": "policy.ts a digest" },
    { "id": "b", "bytes": 33554432, "sha256": "policy.ts b digest" },
    { "id": "control", "bytes": 65536, "sha256": "policy.ts control digest" }
  ]
}
```

The identities above are illustrative placeholders, not accepted values. A
failed/uncertain upload must not produce this file. Timeout, stale expiry,
malformed evidence or uncertainty stops; there is no automatic retry, redirect,
new key, resumed journal or replacement call. CLI/session loss is not evidence
that a writer ended. Terminal driver output preserves unresolved obligations.

Only available partial V8 samples are measured. Version strings and a boot alias
report observed runtime/module identity; they do not attest the platform's
entire build, total memory or worker affinity. Genuine rejected-caller evidence
has no invented Ack telemetry. Existing 26-case/256-call/2 GiB/window caps and
operator stop/cleanup restrictions remain mandatory.
