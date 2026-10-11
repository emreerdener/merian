# Local initial-preparation qualification

This directory owns the bounded M3 preparation experiment under
[IC-1's artifact interface](../../docs/rfcs/initial-preparation-artifact-interface-2026-10-11.md).
It has no production caller, provider invocation, hosted installation or feature
activation. The selected historical closure contains six local WAV helpers and
zero external runtime modules. The bootstrap is a separately committed input.

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
