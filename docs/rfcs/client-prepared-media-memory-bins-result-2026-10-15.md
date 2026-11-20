# CPM fixed-bin diagnostics: growth stop reproduced

October 15, 2026. **The approved control passed; the four-read campaign failed
the unchanged growth gate.** Both execution allowances are consumed. No retry or
extension. Activation remains disabled, AWS/160 MiB unapproved, all limits
unchanged and auto-prompts paused. No hosted, device, credential or provider
operation occurred.

## Result and useful evidence

The denial control qualified the compressed loader and bounded retirement path
in 2.983253 seconds: one denied request, two original memory calls, zero media
activity, no runtime or diagnostic fault, complete receipts and removal.

The prefix campaign stopped at `growth_stop` after 42.345024 seconds; 45.200370
seconds including cleanup. One worker handled five requests including the
denial. Four media reads consumed 67,239,936 bytes; all four bodies closed.
Three acknowledgments were verified and the fourth stopped. The four quiescent
proxies rose from 17,647,141 through 17,848,986 and 22,264,965 to 28,425,349
bytes. Their increase was **10,778,208 bytes (10.278900 MiB)**, above the
unchanged 8 MiB rule. Peak reported proxy was 34,948,481 bytes (33.329469 MiB),
below the unchanged 96 MiB ceiling.

The fixed-bin observer collected only original calls: seven for each control
read and 518 for each large read. No diagnostic fault occurred. Its numeric
backing remained 2,384 bytes; no memory call, timer, idle probe, forced GC or
extra request was introduced.

| Request        | Classification            | Initial verifier to last chunk proxy change | Cleanup proxy change | Final handler proxy change |
| -------------- | ------------------------- | ------------------------------------------: | -------------------: | -------------------------: |
| Case 1, 64 KiB | Verified path             |                              +328,960 bytes |                    0 |                          0 |
| Case 2, 64 KiB | Verified path             |                               +66,404 bytes |                    0 |                          0 |
| Case 3, 32 MiB | Verified path             |                            +4,291,164 bytes |                    0 |                          0 |
| Case 4, 32 MiB | Unclassified stopped path |                             Not interpreted |      Not interpreted |            Not interpreted |

For case 3, the bin covering original-call ordinals 229–260 began at 32,982,401
bytes, reached a maximum 34,948,481, and ended at 18,300,069. Another drop
occurred within ordinals 453–484. These observations localize rises and falls
**within the verified reading/hashing interval**, before owned cleanup. They do
not identify GC, allocator ownership, reachability, physical memory or an idle
plateau. A zero proxy delta across cleanup does not prove that cleanup released
no resources, nor that it reclaimed the underlying allocation. The proxy remains
`heapTotal + external`, not RSS.

Case 4 remains raw and unclassified even though its call count is 518 and the
main reports `growth_stop`. That reason is not sufficient proof of the sole
failure cause. No internal cancellation/verification provenance was added. No
semantic phase claims are made for that stopped request.

The narrower question was answered for verified requests: observed net proxy
increases occurred during reading/hashing, not at the two later measured
boundaries. Whether a retained allocation exists, and which allocation path owns
it, remains unresolved. The changed observer can affect allocation timing; this
is not a controlled comparison proving the original failure's cause. Earlier
workload passes and failures remain intact. No qualification gate is relaxed or
reinterpreted.

## Teardown and scope closure

Campaign teardown passed the scoped envelope: cleanup acknowledgment 1, empty
registry after two inventory reads, matching early-drop event, required receipt
order, no runtime errors, expected signal/exit 15, EOF and confirmed removal.
`shutdown_evidence_complete:true` is separate from the assessor's
`qualified:false` and `overall_lifecycle_passed:false`, which include the failed
workload predicate. Exit 15 is external operator termination, not graceful
process exit.

A final read-only Docker inventory found no `merian-cpm-bins` containers. The
build, control and campaign containers were removed; unrelated existing local
Supabase containers were untouched. No cleanup obligation remains. All evidence
writes stayed inside the approved 4 MiB incremental allowance, 512 MiB aggregate
cap with 16 MiB temporary reservation, and 20 GiB free-space floor. The campaign
runtime log was 22,811 bytes. Exact final inventory is in the preservation
record.

The approved fresh window was 16:37:22–18:37:22 UTC. Execution ended at the
first campaign failure; unused time authorizes no retry or expanded diagnostic
method. This result does not qualify sustained reuse, hosted behavior,
original-media retention, initial identification/reanalysis, native or
integrated acceptance. The approved deletion/export/redesign sequence remains
dependent on those open requirements. Further experiments require a separately
bounded reviewed scope.

## Exact candidate and evidence

Evidence root: `.artifacts/client-prepared-media/memory-bins/`.

- Executed 102-file candidate:
  `c8b9ad5aa5a59602d9cd0d2e6ef089bf56fa86eb00b5b5437ff57891bbd14605`.
- Worker executable SHA-256:
  `bf5d46fa9443f42b6a8e07ab15c2492567fbec59f915a8ebacd5fbc58d28e08d`. Compressed
  1,820,865 bytes; uncompressed 8,444,293. Only compressed bytes were retained;
  compilation and runtime expansion used capped 16 MiB tmpfs.
- Control outcome:
  `08cf579d41728e6bbd55a2758f16a79b140655e02462ce792b3f58baa1083411`. Its
  12-file evidence set:
  `c717c3b8f1ef6d46ae132c3b71433ae1b4d824d4c25365423c60686ce65162d0`.
- Campaign outcome:
  `d23b15089ef31549d8c8514ed17317634581aa5cf02da7d458a243c3a8994111`.
  `campaign-analysis.json` retains raw numeric observations and only the three
  valid verified-path interpretations; all four acknowledgments remain intact.
- Independent reviewer `/root/diagnostics_review_fallback` and IC-1 concurred
  before the control and separately before the campaign. IC-1 control turn:
  `01a1407b-50e9-7632-8194-7fbdf4b96917`; campaign turn:
  `01a1407c-c8c2-7260-b4aa-b98483d7f1f1`. Exact receipts are retained.
- `prior-status-snapshots.json` preserves the reviewed proposal's status bytes
  as gzip; `execution-status-snapshots.json` reconstructs each executed status
  by prefixing the named text file to its decompressed snapshot. This avoids
  another full copy while preserving exact candidate hashes.

## Validation and corrections retained

Thirty-three focused Python tests passed, including classification identity,
duplicate/count rejection, pre-write capacity, source identity, compressed
identity, lifecycle collection and qualified clock/guardian reuse. Eight Deno
observer tests and six retirement tests passed; two lifecycle and one loader
ownership test passed after correction. All three entries were recursively
typechecked with cached-only `deno test --no-run --frozen`; corrected main
entries were rechecked. No dependency download occurred.

Pre-control independent/IC-1 review required pre-write capacity enforcement,
complete classification identity checks and explicit loader input cleanup. These
were corrected and re-reviewed on the executed 102-file candidate. The initial
unsupported `deno check --cached-only` invocation and stale baseline
unit-harness failure are retained; they were not campaign attempts. The loader
ownership regressions cover output-open and decompression failure.

Changed Markdown was formatted and the repository changed-Markdown gate passed.
No deployable Function, migration, product UI or API changed. Production/full
backend suites were not rerun for this isolated local diagnostic. All 115
unrelated dirty paths remain byte/status-identical. Final exact result review is
recorded separately from its self-excluding manifest.
