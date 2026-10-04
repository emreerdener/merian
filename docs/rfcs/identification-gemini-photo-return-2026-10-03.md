# Prepared Gemini photo return — 3 October 2026

Status: implementation and local validation complete; not deployed. The owner
approved preparing a controlled return to Gemini after repeated anecdotal
reports that photo identifications were better before the OpenAI switch. This is
a product decision under uncertainty, not a benchmark qualification or
superiority claim. The completed reasoning comparison found no supported
medium-effort gain; its scientific findings and closed spending allowance remain
unchanged.

## Exact change

Migration `20261003063950_restore_gemini_beta_photo_identification.sql` changes
only `scan_identification` / `multimodal_photo_v1` catalog rows, from
`openai_photo_v1` / `gpt-6-sol` to `gemini_baseline_v1` with
`processor_permission = google_gemini`, `provider_model = NULL` and
`minimum_identification_protocol = 0`. It rejects absent or unexpected source
assignments and checks the affected count; the update repeats the expected
source tuple so a concurrent catalog edit fails closed. Existing entitlement
protocol minima, quota policies and catalog keys remain unchanged.

NULL restores the existing quota-selected Gemini model. **Pro and complimentary
scans use Gemini 2.5 Pro; exhausted free-tier fallback uses Gemini 2.5 Flash.**
This is a return to the existing tier policy, not Pro for every possible photo.
Audio, mixed photo/audio, video, text, enrichment and compatibility routes are
outside the change. No confidence threshold, prompt, output field, subscription
rule, credential or consent receipt changes.

## Compatibility and preserved history

The existing Gemini adapter and native reader already recognize the restored
binding, model, prompt, schema and confidence provenance. Pro uses the preserved
5,000-thinking-token configuration; Flash retains its existing profile. This
migration adds no provider call or fallback dispatch. The normal Gemini result
policy applies to new Gemini answers; stored OpenAI answers retain their own
unqualified confidence policy. No score is recalculated.

Completed responses and live/committed quota attempts retain their immutable
provider snapshot. A duplicate of a pre-switch OpenAI attempt continues to
return that original provider identity. A new metered attempt uses the
then-current binding under existing admission rules; this change does not
authorize retrying completed scans. If a client preflighted OpenAI immediately
before activation, the recipient mismatch denies fresh inference and rolls back
quota consumption; the client must refresh its normal preflight.

No stored scan/history migration, iOS source change or app distribution is part
of this candidate. The separate scan-history work is excluded from this isolated
checkout. Existing consent checks, RLS, private catalog access and public API
shapes remain in force.

## Validation

Final local evidence on the isolated candidate:

- Exact Supabase CLI 2.109.1; clean replay of the final migration chain into
  dedicated disposable project `merian-gemini-return-20261003`, port 55442.
- All 72 database catalog files passed, 474 assertions, including real
  reservation/preflight/immutable-replay behavior and privilege checks.
- All 69 static migration contract files passed, 363 tests.
- Complete backend suite passed: 2,256 tests and 343 steps, with 11 existing
  database-dependent tests ignored by that network-denied suite.
- Complete Supabase tooling gate passed: 499 standard tests, 149 evaluator
  filesystem tests, both DTO suites and all discovered shell tests. Synthetic
  terminal tests used no real credentials or provider requests.
- Formatting, lint, DTO contracts, all 104 Function configs and 104 isolated
  dependency graphs passed. Research register and changed-Markdown checks
  passed.
- Read-only review confirmed scope, tier policy, drift guards and preserved
  OpenAI replay. Initial synthetic-fixture parser/type and free-credit setup
  defects were corrected before the successful final replay/catalog run.

No real provider call, hosted preflight/deployment, iOS build or device smoke
was performed. The separate database-dependent Edge concurrency tests and hosted
advisors remain part of exact-SHA candidate CI before release; local results do
not claim those checks passed. No runtime TypeScript or Swift source changed.

Tests cover exact fresh defaults, Pro, complimentary and exhausted free
fallback, immutable assignment snapshots and stale-recipient quota rollback. The
preserved OpenAI fixture explicitly installs its old assignment before
exercising OpenAI admission and replay across a Gemini catalog change. This
keeps historical-reader coverage without treating OpenAI as the new default.

## Release and recovery boundary

No production action has been taken. Deployment requires an explicit request to
apply this photo-routing return to Supabase production `qlarqavoqhkuwzmevrmf`,
then the repository's exact-SHA candidate validation and protected Production
workflow. Local green tests do not authorize deployment. Do not deploy the main
checkout's unrelated uncommitted scan-history migrations with this candidate.
The existing deployed Gemini adapter is required before assignment changes.

Before activation, verify the exact old photo tuple, current Pro/complimentary
and free quota-model rows, and live Gemini adapter availability without printing
private data. After applying the migration, verify only photo rows changed,
Gemini recipient/model selection works for new photos, a stale OpenAI
expectation fails without charging, and an existing completed OpenAI result is
recovered without reidentification. A separately authorized normal app smoke is
runtime verification, not accuracy validation.

Recovery is a separately reviewed forward migration restoring the exact prior
OpenAI photo tuple after confirming its deployed adapter and model are still
available. Keep consent records, old/new provenance, confidence readers, usage
accounting and all saved results. Never rewrite completed identifications during
recovery. The remaining research priority is independently supported examples of
actual reported failures and visual-evidence sufficiency; no new paid study is
started by this return.
