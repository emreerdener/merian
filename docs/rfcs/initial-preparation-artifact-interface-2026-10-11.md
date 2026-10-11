# Initial preparation executable artifact: local feasibility

Status: proposed M3 interface after accepted inactive M2
`0ef9e1c4d5efef773aa117db314d10e79d201448`, October 11, 2026. This is a bounded
local preparation proof under IC-1, not a provider, production loader, release
builder replacement or hosted execution attestation. Exact interface review
precedes executable acceptance.

## Ownership and scope

The history primary alone writes the new local bootstrap, builder/harness,
focused tests and this document. The initial-analysis hardening owner and an
independent project reviewer review read-only. Shared deployment workflows,
runbooks, generated deployment identities and unrelated edits remain untouched.

The deliverable is one retained, reproducible local artifact built from a
verified historical preparation closure plus an explicitly measured new
bootstrap. Execute identity and a real WAV preparation/resampling vector with
that exact artifact. This does not claim arbitrary media safety, all supported
formats, provider construction, dispatch or installed native integration.

The immutable original source archive remains the source of historical code,
configuration and lock bytes. Its current catalog includes the audio processor,
WAV/resampling helpers, encoding, media budgets and HTTP helpers. The initial
preparation closure appears local-only; prove that inventory during feasibility.
A missing file, unresolved external module or unaccounted dynamic import, asset,
process environment dependency or code-loading mechanism holds the candidate. Do
not fetch dependencies or substitute current-checkout implementations.

## Measured inputs and version selection

Select the exact retained source archive and its existing configuration-assets
identity. Verify every source byte through the archive resolver before creating
an isolated build tree. Reject symlinks, duplicate paths, path escapes,
unexpected files and size overruns. Preserve immutable archived configuration
and lock bytes; do not update or relax them to make a build succeed.

The new bootstrap is a separately measured adapter, with its own source digest
and reviewed source revision. It is not represented as part of the old archived
revision. A finite local artifact registry binds the tuple of archive digest,
configuration-assets identity, bootstrap digest, build policy and toolchain
identity to an artifact digest. Unknown tuples hold. No newest-version fallback,
runtime downloading or reprocessing with current sources is permitted.

The complete manifest records canonical relative paths, byte counts and SHA-256
for every actual build input, including the bootstrap and any resolved
transitive dependency or data asset. The preparation-only closure must have zero
external runtime dependencies for this increment. Provider SDK specifiers in the
larger source archive are not falsely described as retained resolved SDK bytes;
provider construction remains a later explicitly measured closure.

Inventory actual static/dynamic imports and source-loading/environment access.
The existing regex source graph alone is insufficient evidence that no
additional code can execute. Use the pinned toolchain's resolved graph plus a
reviewed closed source inventory; reject unaccounted mechanisms. Bundle output
must be a single self-contained artifact with no runtime source imports, dynamic
code loading or neighboring-file dependencies.

## Toolchain and deterministic build

Record the actual Deno executable bytes/digest, reported version and target,
architecture/OS assumptions, exact flags and any secondary bundler executable or
asset actually used. Version text or an image tag alone is insufficient. Missing
secondary toolchain inputs hold; do not auto-download them. A private verified
toolchain snapshot is required where replacement could occur between checking
and execution.

The installed Deno 2.9.4 bundler rejects `--cached-only`; that earlier
feasibility claim was incorrect. Investigate its supported `--no-remote`,
`--no-npm` and `--deny-import` controls for this local-only closure. Retained
configuration and lock remain explicit, frozen inputs; packages must be bundled,
with the Deno platform and one ESM output. No source maps containing temporary
absolute paths, code splitting, externalized packages or environment-file
discovery.

Each build uses a fresh private `DENO_DIR`, seeded only with manifest-verified
secondary tooling or dependency bytes. It cannot consult the user's ambient
cache. Reject every cache miss or unlisted resolved graph node; a negative test
must prove that a dependency present only in the host cache is unavailable.

The harness builds twice in independent fresh private directories with identical
verified inputs and controlled environment, then compares output digests and
sizes. Record both commands and results. If output differs, identify the cause
before claiming reproducibility; do not normalize away unexplained differences.
Bound materialized input bytes, build duration, diagnostics and output bytes. Do
not infer network isolation merely from successful cache resolution.

## Execution and result binding

Execute only the artifact bytes whose digest was verified against the selected
manifest. Use a private immutable snapshot or an equivalent transfer of those
verified bytes that prevents a hash-then-replace race. No adjacent source
imports, current-checkout reads or ambient configuration discovery during
execution.

The execution child has no network, environment, filesystem read or write,
subprocess, FFI or import permission. Run in a private working directory with
explicit user-code read denial (including `--deny-read` if compatible with
root-module loading). Prove attempted reads of sentinel adjacent and
current-checkout files fail. Standard input is the sole input channel after
verified artifact loading. Input arrives over bounded standard input; bounded
output returns over standard output. The bootstrap accepts a closed versioned
local protocol for identity and the saved WAV transform only, with explicit
options. It invokes the archived transformation, not a rewritten copy. Results
bind input/output byte counts and digests, transform/options, archive/config and
artifact identity; the parent independently hashes actual returned bytes.
Neither a manifest echo nor an embedded ID is proof of execution.

For this feasibility increment, use synthetic qualification inputs within a
small fixed byte/duration/channel/rate envelope. Include at least one supported
non-16-kHz WAV requiring actual processing and compare against the retained
implementation's expected output. Reject unsupported operations and options,
malformed or excessive input, extra output and missing final completion.

The parent owns a monotonic timeout, bounded concurrent execution (one child),
output limits, explicit V8 heap/work limits and a measured process memory
ceiling. Document whether the available host can enforce a hard native memory
limit; a sampled RSS ceiling or JS heap limit must not be described as a hard
process-memory bound. If the required isolation cannot be demonstrated, retain
the feasibility blocker instead of accepting executable qualification. Kill and
reap owned children after cancellation, timeout or failure, and remove temporary
source/execution trees without deleting retained evidence or dependencies.

No raw user media, submitted text, credentials or production output enters
fixtures, logs or manifests. Preserve only synthetic vectors and bounded
sanitized diagnostics. Store retained artifacts and proof outside disposable
build caches, above the 20 GiB disk floor.

## Acceptance and remaining integration

| Required row                   | Owner                                  | Concrete pass condition                                                                                                                                       |
| ------------------------------ | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Complete input closure         | History primary; independent review    | Every executed input accounted for by retained digest; missing/dynamic/external input holds without fetch or current-source fallback.                         |
| Toolchain closure              | History primary; initial-engine review | Actual executable and secondary tool bytes recorded; build environment and flags fixed; unsupported primitives reported honestly.                             |
| Reproducibility                | History primary                        | Two fresh builds produce identical artifact bytes and manifest identity.                                                                                      |
| Exact execution                | History primary; independent review    | Verified artifact executes both vectors without adjacent sources or denied permissions; actual output hashes match retained expected results.                 |
| Resource isolation             | History primary                        | Input/work/output/lifetime and memory behavior measured and enforcement boundaries stated; failed required enforcement blocks executable acceptance.          |
| Tampering and missing versions | History primary                        | Altered bootstrap, dependency, prompt/config/archive/artifact and unknown saved tuple fail closed before acceptance; no fetch/fallback.                       |
| Process lifecycle              | History primary                        | Timeout, cancellation, output excess and nonzero exit kill/reap the owned child and leave retained evidence intact.                                           |
| Candidate verification         | History primary                        | Focused regression and complete affected tooling/format/lint/type gates, with exact hashes and independent re-review; retained failed attempts distinguished. |
| Hosted execution and final CI  | Separate release authorization         | Remain unqualified; local artifact evidence cannot close hosted provenance, exact-push approval or current remote candidate CI.                               |

M3 must not silently replace admission's existing preparation semantics or claim
that the provider path consumes this artifact. A later reviewed integration must
bind preparation and provider construction to the same admitted implementation
identity, preserve original durable media, and satisfy the separate dispatch
fence. Structural/decode validation, result/completion, route/recovery adapters,
source-bound history text and native journeys remain open. Activation stays
false, backend selection null and ordinary installation nil.
