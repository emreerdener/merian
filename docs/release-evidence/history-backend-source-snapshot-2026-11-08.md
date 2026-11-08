# History backend source snapshot — November 8, 2026

This snapshot supports local backend qualification preparation. It is **not
release-qualified**, is not the complete native History candidate, and grants no
publication, deployment, activation, hosted testing or device-installation
authority. The active `identification_history_integration_hold` is preserved.
The existing
[deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md) and
[hold evidence controls](README.md) continue to govern external operations.

## Selected source

The base is published main `24094e3e10352cbf8df6b0144d55421eb40acacb`. The
History/Engine backend overlay contains 511 migrations and 1,523 function
TypeScript/JSON inputs, all byte-identical to the completion220 manifests. It
includes matching scripts, SQL tests, function configuration and local owner
documentation. The
[fleet inventory](../backend-and-data/15-edge-function-fleet-review-2026-07-28.md)
describes the functions present in this snapshot.

The separate public-web pagination/quarantine changes are excluded: two
migrations, their two Deno contract tests and two SQL tests. Published release
holds remain unchanged. The deployment smoke inventory retains the existing nine
bounded calls; the unrelated pagination probe is not included.

The native application remains at the published-main baseline, except for these
three static generated completion-contract inputs required by backend tooling:

- `apps/ios/Merian/Core/Network/Inference/InitialCompletionSchema.swift`
- `apps/ios/Merian/Core/Network/Inference/InitialRetainedResultSchema.swift`
- `apps/ios/TestSupport/InitialCompletionFixtures.json`

The checked-in completion-contract generator produced all three. Their bytes
match the native260 compilation inputs. This is historical evidence that those
exact generated declarations/fixtures participated in compilation; it does not
establish that this snapshot's iOS product compiles, installs or works against a
hosted backend. Identify and captured-media contracts/generated DTOs are
unchanged. Native-coupled account-deletion and documentation assertions remain
paired with their original published-main native sources.

The generated Xcode project includes those source/resource inputs after
`make xcodegen` with XcodeGen 2.45.4 in a stable `merian` generation directory.
Only tracked native/public configuration inputs and the three generated
companions were copied there. The initial temporary-checkout output was rejected
because it changed root-group/configuration identifiers; stable-directory
regeneration preserves those identifiers. Project-resource validation and the 53
focused contracts pass after regeneration. This generation check is not an iOS
build.

## Evidence and its limits

Local completion261 evidence records:

| Check                                                    | Result                       | Applicability                         |
| -------------------------------------------------------- | ---------------------------- | ------------------------------------- |
| Focused documentation/tooling/account-deletion contracts | 53 passed                    | Selected source composition           |
| Standard tooling tests                                   | 556 passed, 132 nested steps | Backend tooling inputs                |
| Evaluation filesystem tests                              | 157 passed, 47 nested steps  | Synthetic local evaluation operations |
| DTO tests                                                | 41 passed                    | Generated contract parity             |
| Shell suites                                             | 22 passed                    | Local workflow and tooling contracts  |
| Complete tooling input freeze                            | 6,067 inputs unchanged       | Pre-boundary-record snapshot          |
| Function/script formatting                               | Passed                       | Selected backend source               |

Original failures remain retained. The first full tooling run omitted the
generated completion inputs; regeneration corrected that assembly error. A
subsequent existing synthetic hidden-input test encountered sandbox `EPERM`
opening `/dev/tty`. A copied diagnostic established that cause; the unchanged
fixture and then complete gate passed outside that restriction. No production
code, assertions or permission controls were weakened. The final complete
tooling run took 291.698 seconds.

The source-boundary review and generated-input fix verification were independent
and read-only. They are **not** the agreed cumulative whole-candidate review.
The completion220 backend evidence retains its original environment and test
scope; matching source pins alone do not qualify this new repository assembly or
its full client/backend behavior. Evidence manifests and failed/passing logs are
retained under the local completion220/260/261 records; they contain no private
account mapping.

## Companion work and release boundary

The later native Capture, initial-result delivery, History/reanalysis and
qualification implementation remains in the full shared History candidate. Its
canonical/RFC synchronization, real-app photo/audio/video journeys,
recovery/selection/review/Undo, resource measurements and cumulative acceptance
are outside this snapshot's evidence. Historical native checkpoints in the
included client-prepared-photo RFC describe that wider work; they do not assert
that its native implementation is present here.

Keep published-main canonical client contracts as this snapshot's baseline. Do
not import full-History native claims or replace missing native source links in
normative contracts merely to make an isolated documentation gate pass. Complete
synchronization belongs with the combined source and its evidence. The backend
implementation's exact schema and helper boundaries are traceable through the
selected migrations, executable schemas, tests and function READMEs; this source
snapshot cannot replace final canonical reconciliation.

The historical authorized beta inspection recorded 372 migration versions at
21:25:46 UTC on November 8. This 511-migration inventory has 139 unapplied
versions. The offline planner verifies the existing digest-pinned older gaps and
selects `reviewed-backfill`. That comparison used no network/environment access
and proves neither deployed SQL contents nor live compatibility.

Existing-account mapping inspection is separate private prerequisite evidence.
Server refusal of new-user creation, provider exchange, release-hold exit
criteria, exact-candidate CI, installed qualification and the user's final
walkthrough remain open. HQ243's earlier expiry failure still needs causal
disposition; a later passing catalog run alone does not close it. No backend
mutation, provider call, credential change or app installation is part of this
snapshot. Later deletion/export/redesign milestones remain deferred.

## Local successor after the first candidate CI failure

The authorized run
[42534204389](https://github.com/emreerdener/merian/actions/runs/42534204389)
validated source `9f0deff`: database catalogs passed 187 files / 7,953
assertions. The full Edge suite passed 4,367 tests (1,119 steps) and failed one
contract test that read two native Swift test files omitted from this isolated
snapshot. Database lint/advisors, contention and private-handoff runtime checks
were skipped. The C1 artifact upload failed because its producer was skipped;
disposable database cleanup passed. This failure remains retained.

The local successor replaces that test's source-file dependency with the shared
synthetic `apps/ios/TestSupport/InitialPhotoTransferFixtures.json`. It keeps the
exact status/candidate byte strings and every backend parsing/rejection check.
The combined native candidate separately adds an executable byte-equality test
against its existing inline goldens. Those native test sources are not imported
into this backend snapshot. Backend fixture-contract validation does not claim
execution or compilation of the native companion. XcodeGen 2.45.4 registers the
static fixture using the same stable generation directory and public tracked
inputs described above.

No parser, endpoint, migration, workflow, release hold, private configuration or
provider-exchange behavior changes. The successor requires its own exact-SHA
publication/validation authorization; the first run's permission is not an
automatic retry allowance. No new publication or hosted operation is implied by
this record.
