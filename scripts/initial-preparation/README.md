# Local initial-preparation qualification

This directory owns the bounded M3 preparation experiment under
[IC-1's artifact interface](../../docs/rfcs/initial-preparation-artifact-interface-2026-10-11.md).
It has no production caller, provider invocation, hosted installation or feature
activation. The selected historical closure contains six local WAV helpers and
zero external runtime modules. The bootstrap is a separately committed input.

The
[local owner integration](../../docs/rfcs/initial-preparation-local-owner-integration-2026-10-13.md)
adds an explicitly synthetic composition of the existing preparation owner and
registered validated-WAV artifact. Exact-source independent and IC-1 review
cleared local execution; the synthetic owner run and both standalone artifact
regressions pass. Final independent and IC-1 evidence review is required before
the local checkpoint commit. Portable tests simulate replies and process control
and must not be reported as actual executable qualification.

`owner-fixture.json` is a separate finite test vector, always Edge-ineligible.
`owner-source-files.json` lists its local module closure. The explicit
`qualify_owner.py --deno <verified-executable> --artifact <registered-artifact>
--output <private-output-directory>`
command snapshots that closure and uses the existing harness's single selector
to supervise both children. Only the original fresh grant may emit a transform
request. Original outcome replay emits none. The parent validates exact
grant/source/profile correlation and retains scalar evidence, never media
frames. Its shared timeline allows 9 seconds for active work, 14 for both
groups' cleanup and 15 for cache checks and evidence framing. Expected transform
rejection still means original-operation recovery, never re-execution or refund.
Sampled RSS and declared fixture CPU/heap fields do not qualify hard resource
limits or abrupt supervisor death.

Both existing standalone artifact profiles require executable regression after
changes to their shared process owner. This command is explicit local
qualification only and is never launched by the portable Make target or CI.

`registry.json` is the finite selector. It pins the committed bootstrap/blob,
archive/configuration/input inventory, platform/toolchain provenance and exact
artifact bytes. Unknown identities fail closed. A null artifact registration
permits only explicit `--build-only`, which emits `candidate-` files without
executing them. Registration authorizes only this local synthetic qualification;
it cannot authorize initial provider dispatch or deploy anything.

## Checks

- `make test-initial-preparation` runs portable synthetic tests, format, Deno
  type and lint checks. It requires Python 3 and the repository-pinned Deno, but
  no retained archive or downloaded bundler. Source bootstrap tests do not
  qualify the historical artifact.
- `make test-initial-preparation-retained-inputs` explicitly checks retained
  local archive evidence and the actual historical bootstrap commit. A shallow
  checkout without those inputs must not claim this check passed.
- Actual qualification requires the retained verified archive, Deno executable,
  pinned esbuild/provenance bundle, and a precreated owner-only `0700` output
  directory without symlink ancestors. Supply their paths with `--archive`,
  `--deno`, `--toolchain`, `--output`, and the registry ID with `--version` to
  `python3 -B scripts/initial-preparation/artifact.py`. Add `--build-only` to
  retain an unexecuted candidate. No command provisions missing dependencies.

The executable probe runs only on macOS ARM64 and requires permission to apply
its own macOS network-denial sandbox. CI must not automatically run this local
qualification or interpret portable checks as hosted/runtime acceptance. The
checkout-wide nonblocking lock prevents overlapping harness invocations. Disk
preflight requires 20 GiB plus 180 MiB for a private toolchain snapshot.
Temporary sources/caches are removed after execution; retained receipts,
dependencies and old failures are preserved. Conflicting output files are never
replaced.

## Evidence and limits

Each receipt includes its exact registry tuple and harness digest. Two fresh
builds must resolve exactly the reviewed local graph and produce identical
bytes. Build-only receipts explicitly say `unqualified_build_only`. Graph
receipts retain verified relative modules rather than unexecuted package
metadata from the historical lock file.

Runtime qualification checks identity and real 32 kHz to 16 kHz WAV resampling,
closed output identity, denied permissions/imports, timeout, cancellation after
a started signal, output excess, nonzero exit and invalid input. A synthetic
ambient cache seeded with the verified secondary bundler must not satisfy a
fresh private cache's missing-tool request. The real user's cache is untouched.

Measured source directories are non-writable for each child's lifetime; writable
caches and bundle outputs are separate. This is a private local snapshot, not a
sandbox against a malicious process already controlling the same user account.
Each process has bounded input/output and a monotonic deadline. Qualification
requires observed RSS samples and direct-child reaping with no surviving process
group. The 64 MiB V8 heap limit and sampled 256 MiB group RSS ceiling are **not
a hard native-memory bound**. Hosted isolation and broader media formats remain
unqualified.

## Validated-WAV local profile

`wav-validation-bootstrap.ts` is the source adapter for the finite
`validated-wav-darwin-arm64-v1` profile. Its v2 synthetic protocol uses exact
compact JSON spelling and canonical Base64, validates one private copied view
before transforming it, and preserves the explicit video-companion fallback
option. Only typed structural rejection and known existing transform denials
produce stage-specific negative diagnostics; unexpected errors fail generically.

Portable adapter and process protocol tests run in
`make test-initial-preparation`. They do not register or qualify a new artifact.
The historical registry and bootstrap remain unchanged. The closed-profile
harness pins prior committed new source blobs separately from archived transform
inputs, reproduces two builds and executes the full qualification. See the
[profile contract](../../docs/rfcs/initial-wav-artifact-profile-2026-10-11.md).

The prepared `validated-wav-darwin-arm64-v1` registry profile now pins source
anchor `e4fc83d27` separately from the unchanged historical transform archive.
Its `validator` binding carries path/commit/blob/SHA256/byte count, and the new
bootstrap also has an explicit byte count. The harness derives graph and cache
allowlists from the selected finite profile, never from arbitrary registry
paths. Both profiles share the same process and cleanup controls.

The registered artifact is 16,647 bytes with SHA256
`cf2df93f4bdcdea853ae7d9c0e1432149cec470270880ca87dcb3b43f51a2f64`. Two fresh
builds reproduced it and local synthetic execution passed all 13 WAV/protocol
cases plus shared process controls. Build-only evidence remains separate and
cannot itself qualify an artifact. Its qualification checks exact v2 response
spelling and stage-specific exits for structure versus known transform denials,
PCM/float output, fallback on/off, and strict protocol rejection. The historical
profile also passed executable qualification after these shared harness changes,
retaining its original 12,296-byte artifact and registered digest. Future shared
harness changes require that regression again. Neither profile updates saved
admission or installs a runtime caller.

## Inactive preparation reference

`preparation_reference.py` projects only the registered validated-WAV profile
into bounded immutable canonical bytes and a domain-separated digest. Its fixed
vector and portable tests run in `make test-initial-preparation`. Untrusted
reference bytes must match the exact authority spelling; no caller JSON is
parsed and no subprocess or artifact is executed. Historical feasibility,
unknown and unregistered profiles cannot construct this stronger reference.

The reference remains local evidence and is always ineligible for Edge. It
changes no admission, media receipt, configuration snapshot or installed caller.
The later v2 admission/retained-derivation sequence and separate
service-contract prerequisites are specified in the
[binding interface](../../docs/rfcs/initial-preparation-binding-interface-2026-10-11.md).
