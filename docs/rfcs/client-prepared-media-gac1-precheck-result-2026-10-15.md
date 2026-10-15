# GAC-1 local precheck stop and command correction proposal

October 15, 2026. The approved fresh local window began at 18:38:33 UTC, with an
absolute end of 20:38:33 UTC. Work stopped at the first failed check. This is a
command-line compatibility failure, not a demonstrated source type error or
memory result. No packaging, container, denial control or 20-read campaign ran.
Activation remains disabled; AWS/160 MiB unapproved; all other limits unchanged;
auto-prompts paused.

## Exact candidate and retained result

Local source commit `771ac5e29`, 96-file source set
`d0a722dff7933fa35b16c926b8a1b7bcab844ebcb35bf3a9d617cb7867847731`. The
candidate already had exact independent and IC-1 source concurrence. The new
human approval authorized the ordered checks and conditional local execution in
the [GAC-1 packet](client-prepared-media-gac1-implementation-2026-10-15.md). It
did not waive its first-failure stop.

Evidence is retained under `.artifacts/client-prepared-media/gac-1/`:
`execution-approval.json`, `window.json`, `checks-results.json`, `checks.log`,
`precheck-stop.json` and `type-command-help.txt`. Earlier source and review
records remain historical. `precheck-status.json` preserves the exact source
bytes of the seven status documents changed after the stop: remove only the
recorded added prefix and verify the old hash. This composes with the previous
six-file recovery chain; no previous failure evidence is overwritten.

| Required step                                                             | Result                                                                                                               |
| ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Exact source, unrelated work and prior evidence                           | 96 source identities, 115 unrelated byte/status identities and 129 prior result identities verified                  |
| Pins and capacity                                                         | Deno 2.9.4, Xcode Python 3.9.6, both existing pinned local images and caches present; more than 20 GiB disk headroom |
| Qualification formatting and lint                                         | Passed                                                                                                               |
| Qualification tests                                                       | 43 passed, including GAC-1 and legacy v1/no-growth/original-stop regressions                                         |
| Independent TypeScript validator tests                                    | 2 passed                                                                                                             |
| Independent Python predicate, prefix-assessment and packaging-bound tests | 9 passed                                                                                                             |
| Recursive explicit-file type gate                                         | CLI argument failure before source checking                                                                          |
| Staged/main lint                                                          | Not run after the stop                                                                                               |
| Packaging, control, campaign                                              | Not attempted                                                                                                        |

The failing command was
`deno check --cached-only --frozen --config
services/supabase/functions/deno.json`
with the explicit complete TypeScript file list retained in
`checks-results.json`. Deno 2.9.4 rejects `--cached-only` for `check`. The
parser returned exit 1 before checking any file. Passing test commands did check
their own module graphs; that does not substitute for the missing complete
explicit-file gate. No passing `checks-receipt.json` or executable concurrence
exists.

## Reviewed correction; execution still pending

Independent review and IC-1 turn `01a140df-cd64-7ee0-b087-d53ddcfa2d97` agree
with the tooling-failure classification and the supported replacement:

```sh
deno test --no-run --cached-only --frozen --check \
  --config services/supabase/functions/deno.json \
  --no-prompt --deny-net --deny-env \
  <the same explicit complete .ts file list>
```

The bracketed text is a description, not a literal shell argument. The exact
list is the failed command's retained path list, unchanged. Local pinned help
documents `--no-run` as caching modules without running tests, `--cached-only`
as requiring cached remote dependencies, and `--frozen` as rejecting lockfile
changes. Local modules are type-checked; `--check` makes that intent explicit.
Do not use directory discovery, which selects test filenames, or add
`--check=all` and silently expand dependency typing. This is a supported
explicit-file, cached, frozen type-check gate through the test command; it is
not claimed to be an identical `deno check` command. No replacement was run.

Recommend a fresh two-hour continuation, subject to human approval:

1. Preserve this failure and the 54 passing tests. Verify their exact executable
   source/dependency identities; carry those passes forward only if unchanged.
   Do not rerun completed suites merely because documentation changed.
2. Record the command-only correction in a new candidate/checklist; obtain exact
   independent and IC-1 review. Run the corrected explicit-file type gate and
   the previously unrun staged/main lint, within the existing combined 32 KiB
   check-output cap. Stop on the first failure or overflow; no automatic repair
   or retry. Do not mark recursive typing or full lint passed in advance.
3. Only after all checks qualify, use the still-unattempted single offline
   bundle allowance, seal the two loader literals, and obtain fresh exact
   executable independent/IC-1 concurrence before the single denial control.
4. Only after a passing control and separate exact concurrence binding its
   outcome, run the single conditional 20-read serial campaign with at least 17
   minutes remaining. Preserve the original schedule, media-byte cap,
   clock/watchdog, deadlines, cleanup and all memory/storage/resource limits.
5. Stop on any failure or review hold. Independently assess the result and
   cleanup; no hosted qualification or product activation follows automatically.

This proposal changes only the unsupported checking command. It changes no GAC-1
predicate, measurement, runtime code or product contract. No source fix has been
demonstrated necessary. The failed window is closed rather than silently
renewing it. There was no hosted access, credential action, upload, deployment,
push, merge, device work or provider invocation. Product/native/ integrated
acceptance and deletion/export then redesign sequencing remain open.
