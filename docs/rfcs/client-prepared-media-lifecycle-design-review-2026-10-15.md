# CPM verifier lifecycle: design decision from retained evidence

October 15, 2026. Proposal only. The user authorized a short design review using
existing evidence, not implementation, tests or hosted access. Activation stays
disabled, AWS and 160 MiB remain unapproved, all limits remain unchanged, and
auto-prompts remain paused. This document adopts no new acceptance criterion.

## Recommendation

**Keep platform-managed worker reuse on the existing backend, with bounded
verification requests. Do not introduce application-controlled worker retirement
as the next architecture.** This is the feasible design direction under the
current infrastructure constraints, not a claim that sustained reuse has passed.

A fresh worker per verification would be attractive containment if the deployed
platform supported an enforceable lifecycle boundary. Our evidence establishes
that capability only in the local diagnostic main service. The existing Supabase
deployment has no established application-owned creation, affinity or retirement
contract. Building another local one-read-per-worker demonstration would not
resolve that deployment gap. No custom server, runtime fork, AWS worker or
additional Supabase project is proposed.

Bound the verification job; do not assume the physical worker is fresh. A
request owns one immutable source-read attempt, incremental hashing, its
existing deadline and cleanup obligations. Keep the module-level busy and
terminal-stop state across requests; do not recreate the handler or reset growth
accounting per request. This retains the existing reusable-worker compatibility
requirement. It is not itself a fix for the demonstrated growth failure.

## Evidence and tradeoffs

The reviewed
[fixed-bin result](client-prepared-media-memory-bins-result-2026-10-15.md) is
committed at `ee17a9ae7`. The four-read campaign failed the unchanged 8 MiB
growth stop at 10.278900 MiB. Its peak partial proxy was 33.329469 MiB, below 96
MiB; all four bodies closed and scoped teardown passed. Three verified paths
showed net increases during reading/hashing, with zero measured change across
later cleanup/handler boundaries. Case 4 remains unclassified. These are neither
leak attribution nor evidence that the growth gate should be removed.

The earlier attended hosted run (`hosted-qdeec80c5e139e0/outcome.md` under
`.artifacts/client-prepared-media/`) completed 25 verified reads with 25
distinct observed module aliases. Maximum sampled proxy was 29.61 MiB; longest
reported request was 3,721.19 ms. This supports transport/per-request
feasibility on that candidate. It guarantees neither fresh workers, CPU
qualification, physical concurrency nor warm reuse. No combination of different
candidates' successful parts constitutes an end-to-end pass.

| Choice                                   | Benefit                                                                                    | Cost or unresolved risk                                                                                                  | Decision                                                |
| ---------------------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------- |
| Platform-managed reuse, bounded requests | Fits the existing deployment; avoids forcing cold startup and new infrastructure ownership | Cross-request retention and the existing growth failure remain; no control over routing or reclamation                   | Recommended direction; still unqualified                |
| Fresh physical worker per verification   | Could isolate repeated verifier allocations if retirement and replacement are enforceable  | Startup/CPU/latency overhead; replacement overlap, controller memory, and shutdown races; hosted control not established | Do not construct or test under the current architecture |
| One-read module latch without retirement | Can deny further media work in the same module                                             | Does not free memory or guarantee a fresh destination; can repeatedly deny legitimate work and exhaust retry budgets     | Not a substitute for worker retirement                  |

The source distinction is concrete:

- `services/supabase/tests/cpm_verifier_characterization/runtime/entrypoint.ts`
  owns one `createWorker`/handler per module and calls `Deno.serve`; it is a
  qualification-only entrypoint, not registered in the production fleet.
- `services/supabase/tests/cpm_verifier_characterization/handler.ts` owns the
  busy/halted latch and `Growth` history; `verifier.ts` owns incremental hashing
  and body closure. These are application-owned boundaries.
- `.artifacts/client-prepared-media/memory-bins/campaign/index.ts` explicitly
  creates a worker with `forceCreate`, loads its executable and calls
  `retirePool`. The operator launches a custom local `--main-service`.
- The
  [pinned-runtime retirement review](client-prepared-media-pool-retirement-proposal-2026-10-15.md)
  limits its pool API evidence to that isolated main service. A cleanup
  acknowledgment plus empty registry is not proof of process destruction.
- `services/supabase/functions/_shared/edgeHandler.ts:runBackground` uses
  `EdgeRuntime.waitUntil`; this is not a worker retirement/affinity interface.
  Absence of a repo-backed control is a feasibility blocker, not a universal
  claim about all future Supabase capabilities. No new platform lookup was made.

## Finite acceptance plan, not execution permission

**Decision gate first.** Accept or reject the recommended existing-backend
architecture without another experiment. Do not spend another campaign to choose
between an available deployment model and an unestablished lifecycle API.

**Before another campaign:** require one concrete source-supported correction to
allocation/ownership behavior, with a predicted observable improvement and a
frozen diff. Existing evidence does not yet identify that correction. A repeated
unchanged run, more logging alone, a smaller fixture, changing the synthetic
transport to reuse buffers, or resetting growth state is not sufficient. If
source review cannot identify a defensible correction, report that blocker and
stop; do not create another diagnostic sequence by default.

Only after separate implementation/execution approval and exact independent/IC-1
concurrence, the proposed qualification sequence is:

1. Focused deterministic checks of the changed allocation/ownership path and
   existing denial, cancellation, late-body closure, digest/size mismatch, busy
   and halted behavior. Review generated/package identities. Reuse unaffected
   evidence rather than rerunning unrelated suites.
2. One denial control, then one conditional campaign using the original full
   retained serial reuse schedule: denial plus 20 reads (604,110,848 media
   bytes), one module/worker, unchanged ordering and spacing. The four-read
   prefix alone is insufficient for sustained-reuse acceptance. Preserve the
   current measurement method and growth history across the entire run. The
   already-consumed control/campaign grants do not authorize this sequence.
3. Pass only if the complete workload and teardown pass on the same exact
   candidate: correct bytes/digests and closure for every read; no unexpected
   replacement, stop, error, overlap or unresolved read; all resource and
   deadline predicates pass; complete scoped local controller
   cleanup/receipt/removal evidence, without claiming physical worker retirement
   or hosted lifecycle proof. Every original rolling growth window must pass.
   Below-96-MiB peak alone is insufficient. First failure consumes the campaign
   and stops qualification; no repeat-to-pass, automatic variant, timeout
   extension or relaxed gate.
4. If local qualification passes, prepare a separate hosted approval packet for
   the gaps that still require it: the changed candidate's private-R2 behavior,
   intended-runtime resources and concurrent admission/closure. Hosted aliases
   remain observations. Lack of observed warm reuse or physical overlap is
   inconclusive for that requirement; do not keep rerunning hoping to observe
   them. Report any remaining gap for a decision.

The plan changes no numeric resource, media, package, storage, CPU or timing
limit. In particular, retain 96 MiB partial-proxy and 8 MiB four-point growth
stops, one active read in the local reuse campaign, 30-second requests,
30-minute internal lifetime, 15-minute external campaign deadline, and all
existing cleanup/evidence caps. Exact future commands must demonstrate storage
headroom before approval; this review reserves no execution space or window.

A different measurement definition or replacement of the reuse criterion would
be a separate explicit contract amendment, not an interpretation of this
recommendation. The growth rule is a stop policy, not a proven leak classifier;
its current failure remains binding. Do not reset it by assigning a new worker
identity or silently mark it inapplicable.

## Product boundary and stopping rule

This qualification addresses only verifier resources and lifecycle. It does not
close original-photo retention, audio recipe/quality, immutable upload identity,
writer closure/reservation release, recovery/deletion, native or integrated
acceptance. Preserve historical/admitted operation meaning and media-required
fresh submissions, including video. Deletion/export/redesign sequencing remains
unchanged.

Read-only verification recovery and AI recovery remain separate: a later
verification attempt may only follow its explicitly reviewed identity, closure,
deadline and budget policy. An uncertain AI operation permits only
original-operation recovery/reconciliation, never another invocation or refund.
No automatic verification retry or new durable schema is adopted here.

History primary remains the sole implementation writer; IC-1 and independent
reviewers remain read-only. Supabase owns the physical hosted worker lifecycle;
Merian owns admission, immutable identity, funding/dispatch, reader obligations
and result recovery. Neither party's responsibilities can be replaced by a local
diagnostic controller.

We now have enough evidence for this architecture recommendation. More testing
is justified only to accept a concrete changed candidate against the unchanged
contract. If no defensible correction is available, or the one future campaign
fails, stop and present the decision conflict. No further test, infrastructure
change or threshold amendment follows automatically.
