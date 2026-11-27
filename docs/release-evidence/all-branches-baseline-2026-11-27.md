# All-branches baseline — November 27, 2026

Status: prepared successor to deployed main
`926ea8bd7717cf0a17985d382bc6e0093c17aa2c`; publication, hosted validation,
deployment and TestFlight remain separate operations.

The user requested that the remaining work be consolidated and released before
this TestFlight build. The inventory covered 83 remote branches, 16 open PRs and
27 available worktrees. All shipping feature work is already represented in
main, including History, Capture and the subsequent device-review corrections.
Existing source, evidence and branch references remain preserved.

## Remaining dependency work

| PR  | Change incorporated by this successor                                        |
| --- | ---------------------------------------------------------------------------- |
| 118 | Admin Mantine core/hooks 9.8.0                                               |
| 121 | Public-web Mantine peer family 9.8.0                                         |
| 155 | Admin Supabase JS 2.119.2                                                    |
| 156 | Admin PostCSS 8.5.33, including Next override                                |
| 157 | Edge Supabase JS 2.119.2 and generated isolated function graphs              |
| 158 | Google GenAI 3.6.1 with explicit `v1beta`, preserving the existing API route |
| 159 | Codex Action v1.14 immutable pin and matching validator                      |
| 160 | Edge JOSE 6.2.18                                                             |

PR150 is closed and superseded by PR158. PRs122–127,133 and136 already have
their requested package/lock/action values in main. The two Mantine PRs were
re-resolved against current source with pinned npm rather than applying their
stale lockfiles. No obsolete branch content may replace newer integrated code
merely to mark a PR merged. After the successor is integrated, close covered PRs
as superseded with the exact inclusion evidence; retain branch references unless
deletion is separately requested.

Three remote simulator/video diagnostic branches are temporary experiment
history. Local analysis-lifecycle guidance was superseded by the current project
skills; older initial-engine research and comparison checkpoints are retained
history, not extra shipping features. Their existence does not require dormant
feature activation, new provider experiments or taxonomy imports.

## Validation and release boundaries

The native product tree is unchanged from main926. Retained native methods and
follow-up evidence stay source-bound; no automatic full native suite restart is
needed for these dependency updates. The closed
[dependency-successor acceptance contract](../development-guides/08-testing-strategy.md#november-27-dependency-successor-validation)
requires fresh exact-source backend, public-web, admin and deterministic Agent
Quality results. The unsigned archive and signed Organizer archive must both
belong to the successor. Historical main926 acceptance is not a new-commit pass.

The local full Edge task exposed an outdated local database fixture. Its failed
DB results and ignored groups remain unqualified; the source-matching disposable
Candidate Validation database must execute the complete required
database/Edge/C1 checks. Local SDK, crypto, authentication and application
quality checks do not replace that hosted result.

Before deployment, regenerate and check all Identification, Gemini and Field
Chat bundle identities. Read Gemini release and Field Chat cutover state without
changing it. The November27 readback found Field Chat active and no Gemini
activation-release records. Recheck before the deployment window: `ready` Field
Chat would cause the existing production workflow to perform one-way activation,
which requires its own authorization. Never invoke its one-way activator with
new hashes over an already active historical record. Normal
Capture/History/Reanalyze admission is independent of these generated diagnostic
hashes; preserve the approved feature flags and dormant initial-engine/CPM
state.

After backend deployment, verify the new function identities, cleanup health and
normal feature gates. Promote both tested Naturebook sites only through their
held, blocking-check release path. Complete the applicable device/media,
install-over, consent and tester-assignment prerequisites before TestFlight.
Taxonomy remains deferred. No success report grants mutation or publication
authority, and no historical failed workflow is relabelled green.
