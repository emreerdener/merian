# Unified development baseline — November 23, 2026

Status: local integration in progress; not qualified for publication, merge to
main, or deployment. This record supplements the historical
[November 13 packet](pr-consolidation-preparation-2026-11-13.md), not its
approval.

## Source and preservation

The local `codex/unified-development-20261123` candidate starts at
`b029e6bbba7f8d95ecdd7750578e9bf731eee49a`, the byte-verified checkpoint of
accumulated History and Capture work, and reconciles PR152 source
`24b3b1d88314e1aa5eef9fe8e382e2efb55389fc`. The running PR152 native gate
remains bound to that separate source; it cannot qualify this integrated
candidate.

All original branches and preservation commits remain available. No worktree,
branch, source file or retained evidence is deleted as cleanup. The seven
additional checkpoint tips are `2a016d689`, `4518f0243`, `3d46d6458`,
`2776b610f`, `be565cf69`, `efa60a43` and `eaf40993`. Their older snapshots are
compared by changed behavior before incorporation. In particular, the old Book
navigation placeholders and placeholder UI tests do not replace the current
functional library, collections and search. Reasoning evaluation files and
runtime-audit ownership fixes are retained in the evolved baseline. The
source-reservation checkpoint has no missing paths (124 identical, 50 evolved).
The older main-scan SQL authority is superseded by Initial Analysis admission,
media fencing, cancellation and atomic terminal controls; it is not replayed.
All local heads have been accounted for against these sources. Two genuinely
missing Composition persistence/transport test suites from `28cc8c655` are
restored, with authorization adapted to the current immutable protocol and the
recovery-only recipient denial. Their original request, replay, disk-reopen,
selection/correction and source-invalidation assertions remain. Temporary
simulator diagnostic workflows and the historical Gemini photo-return release
record remain preserved through their named refs rather than entering the live
baseline.

PR150 is excluded. Its closed, unmerged SDK 3.0 proposal is not part of the
baseline; the active `@google/genai` dependency stays at 2.24.0. The separate
already-preserved guarded Gemini implementation remains part of the source.

## Integration decisions

- Preserve current History/Capture API, ownership and migration contracts.
- Carry forward PR152's complete native sharding, simulator qualification,
  prepared-video inputs, status-sender synchronization and compatible dependency
  updates. No test is skipped to reconcile source.
- Extend the offline video catalog to include six newer Capture portrait and
  coordinate-gradient inputs. Keep the original nine media files unchanged.
  Regenerate project membership from `project.yml`; do not hand-merge the Xcode
  project.
- Regenerate backend deployment identities from the combined graph rather than
  selecting an old digest from either branch.
- Restore the lifecycle checkpoint's status-aware persistence classifier and
  forward HTTP status in its three upsert adapters. Returned transport errors
  cannot authorize media/quota cleanup. Restore its pinned-client regression and
  additionally reject 408/429 as rollback authority even with a PostgreSQL code.
  No older lifecycle SQL is reinstated.
- Keep `identification_history_integration_hold` active. Automatic deployment
  cannot rely on exit criteria attached to an inactive source hold.

## Migration and deployment boundaries

Retain the deliberate, byte-identical web migration retimes
`20261113222833_public_web_explore_pagination.sql` and
`20261113222835_quarantine_public_web_explore.sql`. Do not restore the old
November 8 filenames or introduce duplicates. Before any later deployment, a
fresh read-only target ledger inventory must prove neither old version was
applied and reconcile every migration of the exact integrated source. Historical
remote inventories are supporting evidence, not a current target clearance.

The Gemini migration filenames and bytes are inherited unchanged from both
`ac8f1737d` and `b029e6bbb`: `20261114063734`, `20261114072437` and
`20261114145252`. Integration does not rename them or activate their runtime
gates.

The November 13 packet's original Vercel observations are historical. Both
project holds and distinct Web Quality/Admin Quality production checks were
subsequently read back before PR152 publication; the local receipt is
`.artifacts/pr-consolidation-20261113/photo-status-entry-vercel-prepublication.json`.
Any later publication or release still requires the packet's fresh control
readback for its exact candidate. Local consolidation changes no Vercel setting.

## Validation still required

The combined source requires generated-project and identity verification,
focused fixture and conflict regression checks, complete affected tooling and
security contracts, recursive Edge checks, disposable-database replay/catalog
and integration checks, web/admin package gates, and the complete exact-source
native gate. Review migration ordering and the fresh target ledger before a
release decision. Reuse earlier evidence only where exact inputs remain
applicable; preservation commits are not validation evidence.

Local evidence now includes the 52 focused persistence/hold/security tests, the
17 post-regeneration dependency/identity tests, all 15 asset hashes with
original-nine byte preservation, successful host type-checking of the fixture
loader/tests, generated-project/agent/Markdown checks, and syntax parsing of all
19 changed Swift files. The five newer function-local dependency configs are
regenerated from the same compatible root pins. These checks do not qualify
native runtime behavior, the recovered Composition test execution, database
application, or deployment. The existing 604/603 source-size policy exceptions
are unchanged; portable test expectations now match those checked-in limits.

Web/admin package and workflow bytes match the passing PR152 source exactly.
That evidence remains applicable to those unchanged surfaces, but new
candidate-SHA required checks must still pass before any main merge.

All portable iOS tooling components and all portable Supabase tooling components
passed across retained runs and scoped resumptions. The synthetic terminal-input
lane was rerun with terminal access; its fake credentials made no provider call.
All 130 function entrypoints recursively type-check with their deployment-local
configs; all 130 isolated graphs validate. Migration contracts passed 604 tests
across 160 discovered files, and recursive formatting/lint passed. These are
static contracts, not disposable-database replay or catalog execution.

The final native static preflight passed source size, Swift syntax, generated
membership, resources and diff checks, then stopped at the 20 GiB storage
requirement with approximately 18 GiB free. No storage floor was bypassed. The
transport owner's 600-line ceiling remains unchanged; formatting removed four
lines without changing any Swift token or measured-receiver guard.

The local Mac has fallen below the build wrapper's 20 GiB free-space floor. No
native build may bypass that preflight. No full hosted rerun or external
publication is started by preparing this record. Outstanding checks remain
blocking, with all original branch/evidence references retained.
