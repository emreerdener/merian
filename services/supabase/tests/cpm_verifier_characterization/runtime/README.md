# Local runtime packaging for CPM characterization

This directory packages a representative byte-verifier experiment. The human
approved four hours of local work/review on October 14. No hosted operation is
authorized. The canonical current packet is
[the runtime packaging and hosted request](../../../../../docs/rfcs/client-prepared-media-runtime-packaging-and-hosted-packet-2026-10-14.md).
Activation stays disabled; AWS, the 160 MiB total-memory guard and any product
limit changes remain unapproved.

## Owners and entrypoints

- `config.ts`: fixed Merian production-alpha target, seven experiment-only
  settings, exact operator UUID, run capability/expiry and private bucket.
- `auth.ts`: pinned Auth-server `getUser` with one abort-aware fetch and 64 KiB
  response bound. No persisted session, refresh, privileged client or retry.
- `worker.ts`: runtime composition; positive partial V8 fields and bounded
  version metadata. `entrypoint.ts` constructs one module-level handler and
  registers once. Missing configuration fails closed before any network I/O.
- `transport.ts`: local driver sends only to the fixed test route, including a
  genuine deliberately-invalid bearer for case 26, sent first before fixture
  reads. It requires runtime metadata and no redirects. The handler's public 403
  is distinct from a gateway refusal.
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
deno info --json --config services/supabase/functions/deno.json services/supabase/tests/cpm_verifier_characterization/runtime/entrypoint.ts > .artifacts/client-prepared-media/runtime-packaging/graph-final.json
python3 services/supabase/tests/cpm_verifier_characterization/runtime/stage.py .artifacts/client-prepared-media/runtime-packaging/graph-final.json .artifacts/client-prepared-media/runtime-packaging/staged-06
deno check --frozen --config .artifacts/client-prepared-media/runtime-packaging/staged-06/supabase/functions/cpm-verifier-characterization/deno.json .artifacts/client-prepared-media/runtime-packaging/staged-06/supabase/functions/cpm-verifier-characterization/index.ts
```

Generate a second graph from the staged entrypoint and verify graph closure and
unchanged source/packaged bytes before bundling:

```sh
deno info --json --config .artifacts/client-prepared-media/runtime-packaging/staged-06/supabase/functions/cpm-verifier-characterization/deno.json .artifacts/client-prepared-media/runtime-packaging/staged-06/supabase/functions/cpm-verifier-characterization/index.ts > .artifacts/client-prepared-media/runtime-packaging/staged-graph-06.json
python3 services/supabase/tests/cpm_verifier_characterization/runtime/stage.py --verify .artifacts/client-prepared-media/runtime-packaging/staged-graph-06.json .artifacts/client-prepared-media/runtime-packaging/staged-06
```

`staged-06` is retained evidence: use a new directory for regeneration, never
overwrite it. Record the staged manifest and offline ESZIP digest. Use only the
cached `public.ecr.aws/supabase/edge-runtime:v1.74.2` image, network none,
read-only source/npm/remote cache mounts and a separately bounded writable
output. No dependency cache is modified. No function is started during bundling.
An isolated temporary cache has a 128 MiB cap; the local container has a 512 MiB
memory limit, one CPU and a 30-second bundling timeout. These are local
packaging limits, not adopted product/runtime resource thresholds.

The first all-fleet-import package produced 40,214,443 bytes, above the
documented 20 MB CLI bundle limit. The graph-selected two-alias map produced
8,723,794 bytes but had an unresolved frozen-lock mismatch. A later whole-lock
package again exceeded the bundle limit. The final closed lock subset produces
**8,425,366 bytes** and passes frozen staged typechecking and graph
verification. All artifacts remain as evidence. The exact final manifest is
retained separately after review; the earlier package is not a deployment
candidate.

## Future execution and operator barrier

Installation, secret mutation, fixture upload, execution and removal require the
exact hosted packet's separate human approval. No credentials are needed to run
any local check above. Never run `entrypoint.ts` or `run.ts` merely to validate
packaging.

The driver reads only the future process environment's run, capability, expiry,
operator bearer and canonical public key. It sends no user/session details to
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
