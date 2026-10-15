# GAC-1 adoption, local implementation and pending execution scope

October 15, 2026. **Adopted contract; local source construction only. Execution
is not approved.** User approval adopts the exact reviewed GAC-1 proposal at
`7a8d986a0`, document SHA-256
`d7ba30874d1a2df0d34f65f5e769fe51cf1608b59e0aca2c8c45f611ca0f6d45`. This record
supersedes that proposal's pending-adoption status and the earlier lifecycle
plan's source-correction prerequisite for this one methodology candidate. It
does not claim a memory defect was fixed. Activation disabled; AWS/160 MiB
unapproved; auto-prompts paused. No hosted, credential, deployment, push, merge
or device operation is authorized.

## Contract and implementation boundary

The
[reviewed comparisons](client-prepared-media-growth-acceptance-review-2026-10-15.md)
are adopted unchanged: within each nine-read identical-fixture cohort, median
and maximum of last three Q minus first three Q at or above 8 MiB fail. At the
end, cross-cohort Q/P maximum increases and whole-schedule last-three-B versus
first-three-A median increases at or above 8 MiB block acceptance for review.
Within-cohort failure takes precedence; if both cross holds occur, report the
envelope hold. Every raw Q/P and per-request legacy warning remains available.
No hold authorizes a pass, waiver, rerun or variant. The offline assessor
evaluates every valid available prefix before terminal-success checks, retaining
warning cases and distinguishing a verified growth failure or review hold from
incomplete evidence. None can produce a pass. A local pass describes only these
finite comparisons and does not establish bounded cumulative growth, leak
freedom, RSS/native memory, CPU attribution or indefinite hosted reuse.

`services/supabase/tests/cpm_verifier_characterization/gac1.ts` owns bounded
serial state (18 Q/P pairs and the old four-point warning window). The handler
opts in only through explicit trusted `growthContract: "GAC-1"`; the default
handler and runtime entrypoint remain legacy version 1. The local GAC-1 entry
calls `createWorker(ports, "GAC-1")`; no environment switch enables it. Its
version-2 acknowledgments add exactly
`growth: {contract: "GAC-1", warning:
boolean, decision}` for successfully
verified/closed reads. Decisions are `pending`, `pass`, `drift_failure`,
`cross_cohort_envelope_review_hold`, or `cross_cohort_endpoint_review_hold`.
Invalid/stopped reads without valid GAC fields cannot qualify. A decision
failure/hold returns `outcome: stopped`, with original digest/closure retained,
and halts dispatch. Unexpected order is rejected before GET. Denial case 26 does
not enter statistics.

Q retains its exact post-verifier-cleanup/pre-handler-return measurement. P is
the original co-timed per-request sampled maximum including the existing final
handler capture. No original memory call, interval, deadline or fixture changes.
The old growth rule is reported on all 20 reads, including small controls, and
no longer independently stops this explicit candidate. The unchanged 96 MiB
partial-proxy stop and every correctness, ownership, CPU/deadline and cleanup
failure still block further work.

The non-deployable sibling package is `.artifacts/client-prepared-media/gac-1/`.
Its TypeScript controlled driver and Python assessor independently compute the
predicates, validate version, fixed identity/order, digest/size, same worker and
owned closure, and refuse missing, stopped, mismatched or incomplete data. No
generated Identify DTO, application request, funding, admission, provider
dispatch, history or retention behavior changes. The ordinary test runtime is
outside the deployment fleet.

## Evidence and measurement bounds

The prior memory-bins directory, source/result manifests and failed outcomes
remain immutable. Six mutable status documents preserve their exact original
bytes as suffixes after new dated headers. `gac-1/prior-status/` retains the
added prefixes; `prior-status.json` binds old and current hashes and the exact
removal recipe. This avoids duplicating large status histories. Historical
verification removes only the exact added prefix and verifies the original hash;
it must not reinterpret new headers as part of the old candidate. Future changes
must preserve this recovery chain.

The prior fixed-bin observer still collects from the same calls. Only its two
original boundary summaries and activity summary are emitted per request; bin
and ordinal rows are not emitted in this full schedule. This declared reporting
change prevents the four-read diagnostic format from exhausting existing limits.
It provides no within-read bin conclusion for the new campaign.

Encoded diagnostic limits (including prefix, excluding newline) are tightened to
512 bytes per boundary, 384 per activity and 128 per fault, inside the unchanged
1024-byte diagnostic maximum. Main records cap responses at 1024,
attempt/dispatch at 256, and other fixed records at 512 bytes. Full campaign: 63
normal diagnostic rows plus one fault, 63 request records and six main
lifecycle/result/ready records, below 256 total and 128 diagnostic records. With
newlines and 8 KiB runtime-text reserve, the fixed bound is below the existing
96 KiB campaign allocation. Denial control retains 16 KiB. Outcome bounds remain
128/32 KiB; assessments 4 KiB. Any overflow fails, never truncates into a pass.
Combined logs remain below the existing 512 KiB outer ceiling.

The new root remains below 4 MiB; aggregate CPM retention plus the 16 MiB
transient reservation remains below 512 MiB. Construction baseline is in
`construction.json`; capacity is checked before packaging and writes. A single
compressed bundle may occupy at most 2 MiB (a tighter suballocation), with the
existing 9 MiB raw bundle bound and 16 MiB tmpfs. Reserve 832 KiB for control
and 704 KiB for campaign; no evidence/dependency deletion is authorized to make
space. The 20 GiB free-disk floor remains. Feasibility is conditional on
measured bundle size and available aggregate capacity; exhaustion returns a
blocker.

## Proposed execution approval packet

**Not authorized by construction approval.** Proposed fresh two-hour local
window, starting only after explicit approval, with these ordered steps:

1. Verify exact source review receipts and source/dependency hashes,
   preservation, disk/capacity, pinned existing Deno 2.9.4, Python 3.9.6 at the
   qualified Xcode path, qualified monotonic clock/watchdog bytes and locally
   available pinned images. No image pull, dependency download, credentials or
   hosted access.
2. Run prepared pure-data predicate, independent-validator and ownership tests,
   cached recursive type/lint checks and existing affected qualification tests.
   Include equal thresholds, oscillation/max masking, terminal precedence,
   warning/non-stop separation, missing/invalid values, wrong worker/version,
   original closure/denial behavior and record bounds. Explicitly run legacy
   version-1 handler/runtime regressions: version 1, no `growth` field, and the
   old four-point stop. The new static import must not regress default mode.
   Stop on failure and return for a decision; no campaign while checks are
   unresolved.
3. One network-disabled offline compilation using existing image
   `sha256:a82676277615aee03c4f288cbbbf68dedb5ba8693073e567ab8dbfdd11ba5d45`, at
   most 30 seconds plus bounded cleanup. Stream gzip retention; caches
   read-only, 512 MiB container/one CPU/16 MiB tmpfs. Do not edit source during
   compilation. Seal only the two loader byte-count/SHA literals from successful
   packaging, form the executable manifest and obtain fresh exact independent
   and IC-1 concurrence before the control. No second compilation attempt.
4. One denial-only control: 15-second absolute deadline plus 30-second cleanup;
   require 403, zero media/chunk activity, successful package load, full pool
   retirement receipts, expected external exit 15, EOF and container removal.
   Independently assess. Failure stops the scope without replacement.
5. With separate exact independent/IC-1 concurrence binding the same executable
   set and passing control outcome, and at least 17 minutes remaining: one
   conditional full serial campaign, denial 26 then cases 1–20, on one worker.
   Exactly two 64 KiB controls and eighteen 32 MiB reads, at original spacing,
   maximum 604,110,848 media bytes. No cases 21–25, concurrent pairs, forced
   affinity retries, GC or idle probes. External deadline 900 seconds plus
   120-second cleanup; 30-minute internal worker lifetime. Stop at any hard
   failure, case-11 drift failure or case-20 failure/review-hold. No
   repeat-to-pass.
6. Independently assess and review retained result, including every warning and
   raw Q/P. Preserve failed/incomplete classifications. Finish removal and
   report physical/native retirement as unproven despite positive application
   cleanup. A passing local candidate still leaves broader resource/hosted and
   product/native/integrated acceptance open.

The runtime image stays
`sha256:5f555406dc0705d775323c58e27e856cca7b5b8d0ab726cc6a30b11fcfc7c6b3`. Other
limits: 256 MiB worker, 512 MiB container, one CPU, 5000/10000 ms soft/hard CPU
limits, 30-second request, 8 KiB response, 100 ms sampling, one active reader,
zero runtime grace, one-second Docker grace, two-second host drain, 1500 ms
retirement, 16 host journal rows, 256 call/2 GiB transfer outer ceilings. No
hosted test or activation follows automatically.

## Current verification and ownership

Only file construction, formatting and read-only review are allowed in this
checkpoint. Tests, type checks, compilation, containers, measurements and
historical rescoring have **not run**. The loader is intentionally unsealed; no
bundle, execution approval/window or control/campaign concurrence exists. Those
missing gates prevent launch. Source review is not executable validation. The
source manifest and review receipt under `gac-1/` identify the exact reviewed
preparation; executable hashes can only exist after future packaging.

History primary remains sole writer. Independent and IC-1 reviewers are
read-only. All 115 unrelated edits remain byte/status identical. The adopted
contract does not change media-required submission rules, historical records,
exact recovery of admitted operations, optional supporting descriptions, source
retention/deletion, native acceptance or approved deletion/export then redesign
sequencing. AWS remains unapproved and activation disabled.
