> October 15 adoption: the user approved GAC-1 and bounded local implementation
> preparation. The proposal below is preserved as reviewed history. See the
> [current adoption and execution scope](client-prepared-media-gac1-implementation-2026-10-15.md).
> No execution is authorized; other limits and disabled activation remain.

# GAC-1: proposed verifier growth acceptance contract

October 15, 2026. **Review proposal only; not adopted.** No tests, runtime/code
changes, limit changes or hosted actions. Activation disabled; AWS and 160 MiB
unapproved; auto-prompts paused. The current 8 MiB stop remains in force until
an explicit amendment is approved, implemented and independently reviewed.

## Recommendation

Replace the four-endpoint monotonic-growth veto with **fixed-workload cohort
drift acceptance**, while retaining the former rule as a reported warning and
retaining all absolute resource, correctness and closure stops. Keep the numeric
8 MiB allowance for the proposed drift comparisons; do not raise it to fit a
failed run. Retain the 96 MiB sampled partial-proxy stop unchanged.

This changes the observation window, comparison method and stopping behavior. It
is not numerically increasing a memory ceiling, but it is a material change to
the acceptance contract and must be approved as such. It accepts a finite amount
of measured variation, not a claim of zero retention or leak freedom.

## Is the present rule appropriate?

`services/supabase/tests/cpm_verifier_characterization/telemetry.ts:Growth.add`
stops when four consecutive same-worker post-read proxies are strictly
increasing and their first-to-last difference is at least 8 MiB. The proxy is
`heapTotal + external`. The endpoint called `quiescent` is taken after owned
reader/hash cleanup, before returning to the handler; it is not a post-GC,
post-response or idle-memory measurement.

The rule is reasonable as a conservative experiment stop while behavior is
unknown. It is not a validated leak detector or a sufficient acceptance model:

- The initial window combines two 64 KiB controls with two 32 MiB reads. Request
  count does not normalize the allocation workload.
- Four ordered points cannot distinguish retained allocations from transient
  backing stores, heap capacity changes or accounting/reclamation timing.
- Strict monotonicity misses an oscillating upward envelope: a single drop
  breaks the predicate even when later typical or peak values are higher.
- The 8 MiB number has no demonstrated calibration against known retained bytes,
  false-alarm rates, or a justified safe worker lifetime. It remains an
  engineering tolerance, not an empirically established boundary.

The [retained result](client-prepared-media-memory-bins-result-2026-10-15.md)
correctly failed that rule at 10.278900 MiB. A 33.329469 MiB sampled peak and
positive reader closure do not invalidate its failure or prove it harmless. The
[source review](client-prepared-media-allocation-source-review-2026-10-15.md)
found no supported correction; it did not establish absence of a leak or an
external runtime defect. This proposal is motivated by the rule's structural
limitations, not by choosing a number that makes old evidence pass.

## Proposed fixed decision rule

Use the already documented full serial schedule and its existing original
samples: denial, two 64 KiB controls, then nine 32 MiB reads of fixture A and
nine of fixture B, at the original spacing, on one module/worker. A and B have
the same size, chunk geometry, hash algorithm and request path; their content
seeds/digests differ. Require both individual cohorts to pass and their
comparison to remain below the review-hold threshold; do not assume equal byte
size proves identical runtime behavior.

Let `Q_A` be the nine exact post-read proxy values for cases 3–11, and `Q_B`
those for cases 12–20. Let `P_A` and `P_B` be their corresponding per-request
sampled proxy maxima, each taken from co-timed component sums. Use bytes and
integer comparisons, without MiB rounding. Define:

| Comparison                                                    | Predicate                                                 | Outcome                             |
| ------------------------------------------------------------- | --------------------------------------------------------- | ----------------------------------- |
| Within-cohort typical drift, separately for A and B           | `median(last 3 Q) - median(first 3 Q) >= 8 * 1048576`     | Fail local drift acceptance         |
| Within-cohort endpoint envelope drift, separately for A and B | `max(last 3 Q) - max(first 3 Q) >= 8 * 1048576`           | Fail local drift acceptance         |
| Endpoint envelope across cohorts                              | `max(Q_B) - max(Q_A) >= 8 * 1048576`                      | `cross_cohort_envelope_review_hold` |
| Sampled request peak envelope across cohorts                  | `max(P_B) - max(P_A) >= 8 * 1048576`                      | `cross_cohort_envelope_review_hold` |
| Typical endpoints across the complete large-read schedule     | `median(last 3 Q_B) - median(first 3 Q_A) >= 8 * 1048576` | `cross_cohort_endpoint_review_hold` |

**Either a failure or a review-hold prevents an overall pass.** Never average a
failed cohort against a passing one. A within-cohort failure takes precedence if
a cross-cohort hold also occurs. Median comparisons reduce dependence on a
single endpoint; maxima prevent silently discarding high endpoints or sampled
peaks as convenient outliers.

Cross-cohort comparisons are conservative review triggers, not estimates of
retention or fixture-independent drift. Fixture and sequence effects are
confounded across A and B, and peaks also depend on sampling timing. The
inherited 8 MiB tolerance has not been calibrated as a fixture-difference
budget; therefore there is no automatic drift failure based on cross-cohort
comparisons. The whole-schedule first/last-three median comparison is also a
review trigger, not a causal drift estimate. A hold requires a separate explicit
acceptance decision; it authorizes neither a pass nor another run, variant or
threshold adjustment. Values below that trigger do not establish drift absence.

The whole-schedule endpoint hold addresses cumulative increases hidden by an
early high maximum. For example, conceptual Q values in MiB
`A=[20,20,20,70,24,25,27,27,27]` and `B=[27,27,27,30,31,32,34,34,34]`, with
peaks of 80 throughout, pass the within-cohort and cross-maximum rules. The
endpoint comparison is 14 MiB and therefore blocks an overall pass. This is a
design counterexample, not a new test or a rescore of retained evidence. Smaller
cumulative increases, interior patterns and unmeasured allocations can still
escape these comparisons; a pass is limited to the listed finite comparisons,
not a guarantee of bounded cumulative memory growth.

These are policy checks, not confidence intervals or proof of a plateau. Even
within a fixture, allocator timing can cause rejection; no exclusion is allowed
after seeing results. Freeze Q's post-cleanup/pre-handler-return timing and P's
existing per-request maximum semantics in any later exact implementation.

The two small controls still participate in absolute resource, identity,
authorization, digest/closure and historical four-point warning evaluation. They
are excluded only from comparable-size cohort statistics, by fixed design, not
as adaptive warmup. All 18 large reads are included. No discarded prefix, extra
idle period, forced GC, worker restart, sampling change or reordering.

The old four-point rule continues to be calculated and reported over the entire
schedule, including controls, but **would no longer abort the candidate solely
on that signal**. Its warning must remain visible even if GAC-1 later passes.
After case 11, evaluate A's internal drift; after case 20 evaluate B and all
cross-cohort predicates. A failure or review-hold at either decision point stops
new work. There is no retry credit. Retain immutable request outcome and warning
fields; do not relabel an old stopped acknowledgment as verified.

Hard failures remain immediate at their existing observation points: proxy at or
above 96 MiB, invalid/missing telemetry, wrong size/digest, unauthorized read,
unowned or unresolved I/O, deadline/CPU/resource stop, unexpected worker
identity, uncontrolled concurrency, runtime error or incomplete cleanup. A
missing point, stopped read, incomplete cohort or worker replacement yields
failed/incomplete evidence, never a statistical pass. All other existing
command, package, media, storage, timing and cleanup limits stay unchanged.

## What a pass would and would not establish

A pass means: this exact candidate completed the specified finite workload with
correct results and scoped cleanup, stayed below the observed proxy ceiling, and
satisfied the listed finite drift/envelope comparisons, with no cross-cohort
review trigger reached. It does not establish a flat memory curve, a true peak,
zero leakage, indefinite reuse, hosted worker lifetime,
process/RSS/native-memory coverage or request-CPU attribution.

Keeping 8 MiB avoids an unsupported numeric increase but does **not** validate
that tolerance. Slow accumulation below the tolerance, allocations outside the
proxy, or growth after the finite schedule remain possible. A drift pass must
therefore be labelled local partial-proxy qualification, not complete resource
or product readiness. No extrapolation from 20 reads to all requests in a
30-minute worker lifetime is allowed.

The earlier
[complete-verifier proposal](client-prepared-media-complete-verifier-measurement-proposal-2026-10-13.md)
requires whole-worker peak and attributed CPU evidence and treats rising
envelopes as unresolved. GAC-1 would supersede only the later local four-point
proxy veto and the local requirement for every such window to pass. It does not
silently waive those broader observability requirements. If those requirements
cannot be met, a separate explicit acceptance decision remains necessary before
resource/product readiness. Production activation remains separately gated.

## Tradeoff and alternatives

| Option                                                     | Assessment                                                                                                                                                                                    |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Keep the current four-point veto                           | Strong early stop, but continues blocking on a short, mixed-workload pattern without resolving retention or sustained-capacity risk. Valid if the user prefers that conservative policy.      |
| Raise 8 MiB, or rely on 96 MiB alone                       | Not recommended: no justified replacement number; peak-only checking loses drift detection.                                                                                                   |
| Request forced GC, idle probes or custom worker retirement | Not recommended here: different measurement/lifecycle contracts and unsupported hosted control, with additional qualification work.                                                           |
| GAC-1 fixed cohorts, same tolerance plus envelopes         | Recommended for the next bounded qualification contract: more comparable observations and explicit finite claims, at the cost of later drift detection and remaining measurement uncertainty. |

Waiting until a cohort boundary permits more reads after the old warning. This
is a real relaxation of early stopping, not automatically a safety improvement.
The unchanged 96 MiB guard is sampled JavaScript telemetry, not a hard native
allocation cap. Existing runtime/container limits remain safeguards, not proof
that every unobserved peak is safe. Approving GAC-1 means explicitly accepting
that bounded experimental exposure; it does not authorize hosted exposure.

## Adoption and finite verification plan

1. Independent and IC-1 review this proposal, including false-negative risk,
   exact predicates, classification and the limited scope of supersession. User
   approval is required to adopt the amended rule. This turn performs no scoring
   of old runs under GAC-1 and no executable tests.
2. Only after separate construction approval, version the method and change the
   qualification handler, independent driver/assessor, bounded warning
   reporting, fixtures for the predicate, README and relevant acceptance/status
   documents together. Preserve every original measurement call and fixed
   schedule; do not deploy this test handler as a production resource
   controller.
3. Verify predicate boundary arithmetic, monotonic and oscillating examples,
   outliers, equal thresholds, cohort sizes, missing data, worker mismatch,
   stop/warning separation, and independent assessor agreement. Review one exact
   package. No telemetry/log allowance may expand to accommodate the amendment.
4. With separate execution approval and exact concurrence: one denial control,
   then one conditional full serial campaign, within existing resource/time/
   evidence caps. Stop on the first new-contract failure or review-hold; no
   repeat-to-pass. Construction infeasibility, a failed campaign or a
   review-hold returns a decision, not a new series of diagnostic runs. Hosted
   work needs its own approval packet.

This would be a **methodology qualification**, not a claimed source fix.
Adoption must explicitly amend the earlier lifecycle plan's source-correction
prerequisite for this one methodology candidate; otherwise that prerequisite
still blocks a new run. Approval of the document alone is not execution
approval.

Prior failures, stopped acknowledgments, source manifests and cleanup evidence
retain their original classifications. No historical result can be promoted
using GAC-1. Initial media-required submissions, admitted-operation recovery,
immutable history, retention/deletion, native/integrated gates and subsequent
feature sequencing are unchanged. History primary is sole writer; independent
and IC-1 reviewers remain read-only. No new funding, provider invocation or
refund is permitted by verification uncertainty.
