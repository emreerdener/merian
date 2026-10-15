# GAC-1 type-check pass, loader lint stop and correction proposal

October 15, 2026. The approved continuation began at 19:18:15 UTC with a
21:18:15 UTC absolute end. The corrected recursive type gate passed. Staged/main
lint then failed; the first-failure rule stopped this scope before packaging. No
container, denial control or 20-read campaign ran. Activation disabled, AWS/160
MiB unapproved, other limits unchanged, auto-prompts paused.

## Exact evidence and classification

The 107-file continuation source set is
`8f6b7f781f64634aa689b84d614abc4a0571900585e42b4221a245f70c01b8e8`. Independent
review and IC-1 turn `01a14101-de3c-7282-b6c7-1993a44278ce` concurred before the
checks. Executable source, dependency configuration and lockfile were unchanged,
so the previous 54 passing tests and qualification format/lint were carried
forward. The clock/watchdog qualification was reused.

The corrected `deno test --no-run --cached-only --frozen --check` command, with
explicit configuration, no prompts, denied runtime network/environment access
and the same 59 explicit TypeScript paths, exited zero. This establishes the
requested local-module graph typing; no tests were rerun. The subsequent
staged/main lint checked 37 files and reported two `no-unsafe-finally` errors:

- `.artifacts/client-prepared-media/gac-1/proposed/bundle.ts:40`
- `.artifacts/client-prepared-media/gac-1/campaign/bundle.ts:40`

Both loader copies explicitly rethrow a non-`BadResource` input-close error
inside nested `finally` blocks. Such a throw can replace an earlier operation
failure. This is a demonstrated lint failure and a source-level error-reporting
risk, not a reproduced runtime cleanup failure or a memory-growth result. The
loaders remain unsealed and unchanged. No full passing check receipt or
executable concurrence was issued.

Evidence under `.artifacts/client-prepared-media/gac-1/`:
`continuation-checks-results.json`, `continuation-checks.log`,
`reuse-evidence.json`, `source-concurrence.json` and `lint-stop.json`. Prior and
continuation check output totals 11,695 bytes, below the unchanged combined 32
KiB cap. Original records are retained through `continuation-prior/` and
`continuation-preservation.json`; earlier status prefixes remain recoverable.
New dated headers use `lint-status.json` and `lint-status/` to preserve the
current candidate's exact document bytes. No dependency or prior evidence was
deleted. All 115 unrelated paths remain preserved.

## Proposed bounded correction; not implemented

Limit the implementation to the two local bundle loaders and a shared or
duplicated, equivalent testable cleanup routine. Do not change decompression,
streaming, byte/hash validation, fixture content, loader identity sealing,
verifier measurement, GAC-1 predicates or product code. Do not suppress the lint
rule or broaden ignored errors.

1. Capture any primary acquisition/read/write/sync failure using an explicit
   boolean and its original value, including `throw undefined`.
2. Attempt cleanup independently, in the existing order: cancel the acquired
   reader, release its lock, close the acquired output, close the input. A
   failure in one step must not skip any later acquired resource. Keep cleanup
   awaited; do not introduce detached work, retries or a new deadline.
3. Ignore `Deno.errors.BadResource` only at the existing input-close boundary.
   Collect at most four unsuppressed cleanup failures with fixed step labels.
4. Throw only after cleanup. If only the primary operation failed, rethrow its
   original value. If only cleanup failed, throw an aggregate containing its
   ordered failures. If both failed, throw an aggregate with the primary first
   and cleanup failures in step order. No bundle validation or successful return
   may follow any unsuppressed cleanup failure.

Diagnostics remain bounded and local. Do not serialize arbitrary error objects,
paths, stack traces or other unbounded details into campaign logs; use the
existing bounded failure reporting. The fix preserves existing external
deadlines rather than claiming cleanup is always guaranteed to settle.

## Proposed acceptance and execution scope

Request a fresh two-hour local implementation/validation continuation, after
human approval. Before executing checks, obtain exact independent and IC-1
review of the corrected source and focused tests. Cover these cases with
fabricated resources and no Docker, network, provider or actual bundle:

- Each acquisition/operation failure and each cleanup-step failure; all acquired
  resources receive their ordered cleanup attempts exactly once.
- Primary plus cleanup failures preserve both, with primary first; thrown
  `undefined` remains a failure; multiple cleanup failures remain ordered.
- Input-close `BadResource` alone is tolerated; the same error from another
  cleanup step is not. No digest/readback/return follows a cleanup failure.
- Successful cleanup continues to the unchanged length/hash checks. Wrong
  length/hash still fails. Both loader copies have equivalent behavior.

Run the focused loader tests, affected explicit-file cached/frozen no-run type
gate, formatting and staged/main lint. Carry forward the 54 unaffected passing
tests only after exact source/dependency verification. Retain the current type
pass as historical evidence; it does not qualify the future changed loaders.
Keep all old and new check output inside the existing combined 32 KiB cap;
overflow stops the scope. Do not rerun unchanged suites or use repeated checks
to obtain a pass. Stop on the first failure and return for a decision.

Only after all checks pass: the still-unattempted single offline bundle,
two-literal sealing, fresh exact independent/IC-1 executable concurrence, one
denial control, independent assessment, then separate exact campaign concurrence
binding the passing control. With at least 17 minutes remaining, permit the
single conditional 20-read serial campaign under the original schedule,
604,110,848-byte cap, resource limits, clock/watchdog, deadlines and cleanup.
Any failure or review hold stops further work; no automatic replacement run.

No allowance has been consumed for packaging, control or campaign, and this
proposal adds none. The stopped window is closed. The earlier command-only
proposal is superseded by this demonstrated loader correction requirement. No
hosted, credential, upload, deployment, push, merge, device or provider action
is authorized. Product/native/integrated acceptance and approved deletion/export
then redesign sequencing remain open.
