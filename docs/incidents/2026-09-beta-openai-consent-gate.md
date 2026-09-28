# Incident: OpenAI permission remained in the default beta flow

- **Date detected:** 2026-09-28
- **Status:** Mitigated in source; validation and deployment tracked below
- **Affected versions/environments:** PR 97 source and Supabase Production
  `qlarqavoqhkuwzmevrmf`; installed native build identity unverified
- **Affected surfaces:** iOS identification/retry/Settings and Supabase
  admission
- **Current contract:**
  [Independent OpenAI consent evidence](../backend-and-data/05-api-contracts.md#independent-openai-consent-evidence)

## Summary

The owner reported a photo showing **Permission needed** after requesting OpenAI
photo access for every beta user without a separate consent step. PR 97 still
enforced historical OpenAI withdrawals and exposed OpenAI permission controls.
The correction defers both OpenAI collection and enforcement during beta and
presents owned legacy pauses with a normal explicit retry.

## Impact and scope

The screenshot confirms a permission pause. The original activation source can
produce it for a revoked OpenAI history, and older installed binaries can retain
additional local checks. The owner's receipt history and installed build were
not inspected, so the exact triggering history and affected population are
unknown. Ordinary age/Terms/Gemini consent remains required. Only still-photo
assignments use OpenAI; audio and sampled-video assignments remain Gemini.

## Detection and timeline

| Time (UTC)          | Event                                                                                        | Evidence status                           |
| ------------------- | -------------------------------------------------------------------------------------------- | ----------------------------------------- |
| 2026-09-28 17:55:55 | Original photo activation deployment completed at `204056f60cc782522270ee164e43231d2b15e73e` | GitHub run `36460034494` succeeded        |
| 2026-09-28          | Owner reported the permission pause and clarified access for all beta accounts               | User report; source enforcement confirmed |
| 2026-09-28          | Forward migration and matching native correction prepared                                    | Source mitigation; release status below   |

## Reproduction and root cause

A synthetic current account with an older-version OpenAI revocation reaches
`require_identification_processor_consent` in the original policy and receives
`ai_openai_consent_required`. The native coordinator also excludes revoked or
pending-withdrawal histories from beta access, and the saved queue maps this
code to permission review. This implemented only an absent-choice exception
instead of the requested beta-wide deferral. Historical evidence storage is not
itself a permission to enforce the deferred gate.

## Repository mitigation

Forward migration `20260928183305_defer_openai_consent_during_beta.sql`
validates the known recipient and ordinary required consent only. It does not
change provider assignments, quota, attempts or receipts. The strict receipt
validator remains intact for a future coordinated release.

The native beta coordinator suppresses permission controls and collection calls,
and permits OpenAI access for its current account regardless of OpenAI history.
Fresh dispatch still validates ordinary consent and account identity. Legacy
saved pauses keep their media and retained funding, display generic paused copy,
and require an explicit online eligible retry. Account/scan/funding checks
repeat at the durable transition. There is no automatic paid resubmission.

## Regression coverage and candidate validation

- `AIProcessingConsentCoordinatorTests`: absent, granted, revoked and older
  histories; truthful receipts; suppressed collection and account transitions.
- `OfflineQueueOpenAIPermissionTests`: explicit retry preserves media/history;
  wrong account/scan, missing or released funding and transitions deny.
- `InferenceFailurePresentationTests` and `InsightQueuedRetryPresentationTests`:
  beta pauses have no permission prompt or automatic retry.
- `testBetaOpenAIResumePreservesPausedScanWithoutConsentUI`: synthetic
  historical withdrawal remains saved through navigation and offers retry
  without a consent action. No provider is called.
- Migration contracts and disposable SQL fixtures cover all beta histories,
  preserved strict evidence checks, ordinary consent, protocols, recipient
  drift, quota rollback and private ACLs.

Disposable replay and all 67 database catalogs (435 assertions) passed locally;
database lint reported no schema errors. The focused native check passed 13
XCTest cases, 39 Swift Testing cases and the new UI smoke. The complete Edge
suite passed 2,174 tests with 343 steps, including local database concurrency
fixtures. Full native/tooling and exact-SHA CI results are pending at this
source checkpoint. Final immutable candidate and deployment evidence will be
linked in the correction PR.

## Production deployment and runtime verification

The owner explicitly requested enabling OpenAI photos for all beta users on the
existing Production project. Execute only through the exact-SHA GitHub
Production workflow, preserving candidate validation and release controls.
Correction **not yet deployed** at this source checkpoint; live verification is
pending. The original activation remains historical evidence, not proof of this
fix.

Recovery uses a reviewed forward repair through the same workflow. If photo
routing must revert, restore only fresh photo assignments to Gemini as described
in the
[runbook](../backend-and-data/06-supabase-deployment-runbook.md#openai-photo-adapter-deployment-order).
Never reinterpret existing OpenAI attempts or automatically retry them on
Gemini.

## Data recovery

No receipt or saved-scan data mutation is needed. Existing paused scans remain
saved until the owner explicitly retries from an updated native build. Actual
phone recovery is unverified; native archive/upload remains owner-operated.

## Privacy and security review

This record contains only source identities and synthetic/aggregate evidence. No
credentials, personal data, raw coordinates, sessions or production response
bodies were retained. Current account, ordinary required consent, quota,
funding, protocol and recipient controls remain in force.

## Exit criteria

- [x] Source cause and known/unknown impact are bounded.
- [x] Current policy and future consent recovery requirements are synchronized.
- [ ] Native and complete backend validation passed for the reviewed candidate.
- [ ] Exact-SHA Production deployment and live policy verification succeeded.
- [ ] An updated native build recovered the reported phone scan explicitly.

## Follow-ups

| Owner                       | Action                                                                                                                                                         | Status                    |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| Implementation/release      | Record candidate CI, deployment and sanitized live verification in the correction PR                                                                           | Pending                   |
| App owner                   | Install the updated native build; retry the saved scan                                                                                                         | Pending                   |
| Public-release consent work | Every permission alert needs a direct **Review permission** action, returning to the same scan for separate retry; restore native/backend enforcement together | Deferred until after beta |
