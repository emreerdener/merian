# CPM verifier runtime packaging and exact hosted-test packet

Status: October 14, 2026. Local packaging and review authorized by the human,
starting **14:55:36 UTC**, with a hard **18:55:36 UTC** deadline. No automatic
extension. This document records the next approval packet; none of its hosted
operations is authorized by local construction or review.

The user reports creation of `merian-cpm-verifier-fixtures`, confirmation of the
private settings, and secure storage of two separately bucket-scoped
credentials. That is user-reported setup, not independent live verification.
Values have not been read or installed. R2-F1/TM-1 design and existing product
limits remain unchanged. Activation remains disabled; AWS and the 160 MiB
total-memory guard remain unapproved. Auto-prompts remain paused.

## Local scope and ownership

History primary is the sole writer. Emre is accountable operator. Independent
review and IC-1 remain read-only. This work packages the representative byte
verifier and driver from the
[completed local checkpoint](client-prepared-media-local-construction-request-2026-10-14.md).
It does not implement CPM admission, original-photo persistence, audio recipes,
funding, AI execution, database authority or shared-asset deletion. G1–G4 and
current IC-1 acceptance remain open. Historical/admitted operation meaning,
media-required new requests, and later version-actions/redesign sequencing are
unchanged.

Source remains under `services/supabase/tests/cpm_verifier_characterization/`.
No route is added to the repository fleet or `services/supabase/config.toml`; no
production helper, workflow, release hold or migration is edited. The operator
driver is a separate local process and never deployed. The staging generator
copies only the entrypoint's local transitive graph, relocates shared imports
into an isolated `supabase/functions/` tree, copies the reachable subset of
existing locked npm records without changing versions, integrities or dependency
lists, and emits a manifest of source and packaged hashes. An existing output
directory is refused. The staging package has one route and no migrations. It
must be type-checked and its fresh staged graph checked with `stage.py --verify`
after generation; generation alone is not bundler evidence. The original fleet
lock remains untouched. The staged lock changes only membership: unused records
are omitted and standalone workspace dependencies are restricted to the two
reachable aliases plus the locked Node type dependency closure.

## Runtime contract and verification

- `runtime/config.ts` fixes the existing production-alpha target to Supabase
  project `qlarqavoqhkuwzmevrmf` (`merian`, inventoried us-east-1), route
  `cpm-verifier-characterization`, and bucket `merian-cpm-verifier-fixtures`.
  Other targets fail closed. No separate project or server is introduced.
- A module-level `Deno.serve` entrypoint constructs one handler and random boot
  alias once. Requests within that module share the reader gate. This identifies
  observed isolate reuse, not a guaranteed physical-worker topology or affinity.
- `verify_jwt = false` is explicit in the isolated package because the handler
  authenticates. It is not permission for public media access. The existing
  public error wrapper avoids constructing a privileged client.
- Auth uses the repository-pinned Supabase SDK's explicit-JWT `getUser` strategy
  with no persisted session, refresh or URL session detection. A dedicated
  transport permits one GET to the target `/auth/v1/user`, redirects disabled,
  inherited abort and a 64 KiB response ceiling before SDK parsing. A second
  attempt, network error, malformed response or non-200/401/403 response stops;
  401/403 and a different verified user deny. Only the configured operator UUID
  maps to the fixed safe alias. No user ID or Auth body enters evidence.
- The run capability is independently compared; expiry is an absolute epoch-ms
  value at most 30 minutes ahead at worker construction. It is rechecked after
  Auth and parsing. The driver checks expiry before every send. Configuration
  failure creates only a closed 503 handler. No partial startup is permitted.
- The private GET signer uses only the dedicated experiment read credential,
  fixed bucket/run/three keys and one direct abort-aware fetch. Operator-write
  credentials never enter the function. No retries, redirects, writes, copy,
  multipart, database or provider operations exist on this path.
- `Deno.memoryUsage()` feeds the approved partial V8 sample/growth rules. Zero
  heap fields, unavailable/invalid fields or proxy breach stop before media.
  Bounded Deno/V8 version headers accompany handler replies. These version
  strings do not identify the entire hosted Edge Runtime build; available
  platform build/shutdown metadata remains separately recorded or unavailable.
- Runtime case 26 runs **first**, before any control or bulk read, and sends a
  deliberately invalid bearer with the run capability. The driver requires a
  handler-marked 403 with the expected public denial code; a gateway denial or
  the old simulated policy Ack does not qualify. It records denial separately,
  without inventing worker/memory/reader measurements for an unauthorized
  response. Local tests assert no R2 call on this path.
- After cases 1–2, the driver writes bounded control evidence and waits for a
  local `bulk-ready.json` operator attestation. It sends no bulk request until
  the exact three fixture identities and positive writer closure are attested.
  Bulk timings begin at readiness, retaining the 320-second warm-cohort spans.
  The original absolute run expiry never extends. If the entire remaining
  schedule plus final request bound cannot fit, no bulk call starts.
  Missing/invalid evidence stops; no new run or automatic retry follows. This
  file is operator evidence, not storage-enforced immutability or independent
  writer-closure proof.

The request/Ack contract is owned by `handler.ts`/`driver.ts`; runtime metadata
and denied-caller behavior are owned by `runtime/worker.ts`/`transport.ts`. Only
the experiment driver consumes them; no Swift/web/admin or saved-operation codec
changes. The original offline simulated denial test remains historical coverage,
separately labelled in the README. Runtime imports include dormant service-role
helper definitions through the shared wrapper, but neither the privileged
factory nor database/provider clients are invoked.

Current official references checked October 14:
[Auth getUser](https://supabase.com/docs/reference/javascript/auth-getuser) and
[project environment boundaries](https://supabase.com/docs/guides/functions/secrets).
The former validates against Auth; the latter means experiment secrets share the
project environment. **Every function in this existing project can access the
installed experiment secrets**, including the bucket-read credential. A separate
route name does not provide secret/resource isolation from other functions.
Approval must explicitly accept that shared-project exposure; the writer
credential is never installed. No separate project is required.

## Exact candidate evidence

The local evidence directory is
`.artifacts/client-prepared-media/runtime-packaging/`. It retains the baseline
hashes for 115 unrelated dirty files, failed checks, corrected checks, source
and package manifests, review findings and re-review. The final checkpoint
records commit SHA, exact package digest and all scoped paths. These records are
local; no push, PR update, GitHub workflow dispatch or publication is implied.

The package must have:

1. Passing network/environment-denied candidate tests, recursive type checks,
   formatter/lint, staging tests and a staged-entrypoint type check.
2. Independent and IC-1 concurrence against the same source/package manifests,
   followed by re-review of corrections.
3. Provenance comparison for every staged module, a frozen dependency lock and
   confirmation that the normal checkout still selects no new deployed route.
4. A scoped evidence statement separating this candidate from the unrelated
   checkout/PR116, and the retained 20 GiB free-space floor and 512 MiB local
   cap.

Final locally verified stage: `staged-06`, 20 files, 94,225 bytes; package
SHA-256 `d3841f1471f1cebad46ded3f95abc16fb196357098cf9c3f8efa90ae9e6661c0`.
Offline ESZIP: 8,425,366 bytes; SHA-256
`dbb594bd6e7b6e196b1972e9e0e7fa9d426f0b13cd479314c352fde526202c94`. The cached
Edge Runtime v1.74.2 image identity is
`sha256:a82676277615aee03c4f288cbbbf68dedb5ba8693073e567ab8dbfdd11ba5d45`. The
final source/review record is `checkpoint.md` in the evidence directory. A
frozen staged typecheck, graph/provenance verification and offline Docker bundle
pass. Failed 40 MB bundles and the earlier frozen-lock mismatch remain retained.
The final dependency subset resolves that packaging failure without updating any
dependency. The current
[CLI bundle limit](https://supabase.com/docs/guides/functions/limits) is 20 MB;
this is packaging evidence, not a memory measurement.

Hosted routing, TLS, real Auth/R2 responses, runtime sampling, actual CLI
installation and shutdown/cancellation behavior remain qualification work. No
local pass closes those gates or the complete-verifier resource budget.

## Hosted approval requested only after local review

Approve **one attended experiment**, operated by Emre, for the final recorded
candidate SHA/package hash. The named targets are project
`qlarqavoqhkuwzmevrmf`, test route `cpm-verifier-characterization`, and only
`merian-cpm-verifier-fixtures` in the Cloudflare account where the user created
it. Immediately before mutations, confirm project/account/bucket and that the
route does not already exist; ambiguity or collision stops, without replacing an
existing function or choosing another target.

The exact future authorization must include all of these operations:

1. **Install:** allow the reviewed exception to the whole-backend release hold
   for this one experiment route only. Stage from the recorded SHA and verify
   hashes. Use the pinned CLI 2.109.1 and reviewed local Docker bundling; no
   `--use-api`, fleet deploy, `--prune`, migrations, ordinary routes or
   main/PR116 merge. If isolated bundling fails, retain evidence and return for
   correction; do not switch deployment methods or broaden the route graph. This
   exception is not granted by this document and does not clear the repository
   hold.
2. **Secrets:** install only the seven names below; never read/overwrite
   ordinary app R2 settings or privileged keys. The SDK resolves existing public
   project configuration through the repository helper. The verified operator
   UUID and credentials are supplied securely at installation, not copied to the
   packet. A fresh opaque run/capability and absolute expiry are fixed before
   launch.
3. **Fixtures:** exactly one 64 KiB control and two 32 MiB synthetic objects
   under `cpm-verifier/<run>/control.bin`, `a.bin`, `b.bin`, matching
   `policy.ts`. Single-part creation only, no overwrite. Confirm new empty
   namespace first. Upload and positively close the control writer, run the
   rejected-caller check followed by the two control calls, review
   metrics/versions/closure, then upload/close the two bulk writers and supply
   the local attestation. Any uncertain write stops; no replacement key, retry,
   bulk read or assertion that a later HEAD proves writer closure.
4. **Execution:** run the fixed 26-case driver once in an attended quiet window,
   with no other planned deployment. Confirm operator session lasts through the
   window; no login, user creation or refresh is added to the test. The control
   calls and rejected-caller check count within 26. Preserve actual warm
   routing; no extra calls or forced affinity fill missing observations.
5. **Stop/cleanup:** authorize stopping the driver, deleting only this test
   route through the independently available control plane, revoking both
   experiment credentials, removing only the seven experiment settings and
   deleting only the three run objects after positive writer/reader closure. Do
   not delete the bucket or touch `merian`/`portfolio`. Unknown closure retains
   private objects and obligations, stops new work and requires operator
   reconciliation; neither expiry nor credential revocation proves in-flight
   termination. Retained unknown objects receive review within 24 hours, not
   blind timed deletion.

| Experiment secret            | Purpose                                                    |
| ---------------------------- | ---------------------------------------------------------- |
| `CPM_Q_RUN`                  | Opaque namespace, fixed across uploads, handler and driver |
| `CPM_Q_OPERATOR_ID`          | Exact verified Auth subject, never logged                  |
| `CPM_Q_CAPABILITY`           | Dedicated random run authorization                         |
| `CPM_Q_EXPIRES_AT`           | Absolute epoch milliseconds, at most 30 minutes ahead      |
| `CPM_Q_R2_ENDPOINT`          | Exact account S3 endpoint for the created bucket           |
| `CPM_Q_R2_ACCESS_KEY_ID`     | Bucket-scoped read credential                              |
| `CPM_Q_R2_SECRET_ACCESS_KEY` | Bucket-scoped read secret                                  |

The operator-write pair stays only in the operator's secure credential store.
The local driver additionally receives `CPM_Q_OPERATOR_BEARER` and the public
project key securely in its process environment. No secret values go in command
arguments, source, manifests, logs, screenshots or retained evidence.

## Finite bounds, stop conditions and conclusions

Retain the approved R2-F1/TM-1 limits: 26 invocations; two clients; one active
reader per module; no concurrent reads of one fixture globally; 30-second read
limit; 30-minute run plus 15-minute cleanup; 256 application HTTP calls (192
ordinary, 64 cleanup); 2 GiB media transfer; 512 MiB local evidence; proposed
$10 incremental experiment allowance requiring confirmation before execution.
The driver reserves 48 setup/observation calls and five calls per case (178
ordinary reservations); its Auth transport actually permits only one outbound
request and its media adapter one GET. Operator actions must fit the reserved
setup/cleanup ledger; no hidden retry allowance. Price/allowance and window are
reconfirmed in the execution decision; no paid add-on or spend-cap change.

Stop new work on invalid telemetry, sampled `heapTotal + external >= 96 MiB`,
three consecutive positive same-isolate quiescent increments totaling >= 8 MiB,
integrity error, timeout, runtime kill, uncertain closure, application health
alert, new throttling/5xx pattern or any bound breach. Fixed expiry only
prevents fresh authorization; operator route deletion and credential revocation
are independent controls, not proof of instantaneous physical cancellation.

Report 25 possible verifier Acks and one genuine denied-caller result, observed
isolate cohorts, contention outcome, sample components and phase times. No
native/RSS peak or attributed request CPU is inferred. No one-second CPU, 160
MiB, ingress immutability, storage reservation, complete-verifier or product
acceptance follows. No provider invocation or scan-token accounting is involved.

The
[exact operator command sheet](client-prepared-media-hosted-operator-sheet-2026-10-14.md)
is part of this packet. Approval must name this source/package, the
shared-project secret exposure, $10 ceiling, an attended start window, and the
install/upload/run/ cleanup operations above. The opaque run alias and private
settings are supplied only at execution, without altering the reviewed code or
limits. No wider PR116 integration, device work, activation, AWS or 160 MiB
adoption is included. This packet does not authorize execution merely because
the local gates pass.
