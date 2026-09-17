# Incident: Short descriptive title

- **Date detected:** YYYY-MM-DD
- **Status:** Investigating
- **Affected versions/environments:** Unknown
- **Affected surfaces:** iOS / watchOS / Supabase / web / admin / release
- **Current contract:** Link to the canonical current document

## Summary

Describe the user-visible or system symptom, expected behavior, and present
status in a few sentences. Do not include personal data or raw production
payloads.

## Impact and scope

Record confirmed impact, bounded time window, affected states or versions, and
unknowns. Separate measured counts from estimates and hypotheses.

## Detection

Describe how the issue was detected and which sanitized evidence establishes the
symptom.

## Timeline

| Time (UTC)       | Event               | Evidence status      |
| ---------------- | ------------------- | -------------------- |
| YYYY-MM-DD HH:MM | Initial observation | Confirmed / inferred |

## Reproduction

Document the deterministic fixture, test, or bounded comparison that reproduces
the causal order. If no safe reproduction exists, state why and identify the
best available evidence.

## Root cause and failed invariant

State the narrowest failed invariant, its owning boundary, contributing factors,
and rejected competing hypotheses.

## Regression coverage

List exact tests, negative cases, concurrency/retry cases, selectors, and any
device or hosted checks. Never mark an unrun check as passed.

## Repository mitigation

Describe source, migration, configuration, test, and documentation changes.
Record the exact candidate when one exists.

## Candidate validation

List gates run for the exact candidate and any environment limitations. Green
validation does not imply deployment.

## Production deployment

Record only an explicitly authorized operation, target, immutable source, time,
operator evidence, and rollback readiness. Otherwise write **Not performed**.

## Runtime verification

Record sanitized positive and negative checks against the named target.
Otherwise write **Not performed**.

## Data recovery

Describe affected durable records, the authorized recovery or quarantine method,
aggregate results, and unrecoverable scope. Otherwise write **Not performed** or
**Not required**, with the reason.

## Privacy and security review

Confirm that the record contains no credentials, personal data, raw coordinates,
auth/session state, or production response bodies. Record any authorization or
cross-account negative checks.

## Exit criteria

- [ ] Impact and root cause are bounded.
- [ ] Regression coverage proves the failed invariant and negative paths.
- [ ] Repository mitigation is reviewed and candidate validation is complete.
- [ ] Production deployment is completed or explicitly not required.
- [ ] Runtime behavior is verified in every affected target.
- [ ] Data recovery is complete, unnecessary, or documented as unrecoverable.
- [ ] Current canonical contracts and ownership docs are synchronized.

## Follow-ups

| Owner             | Action             | Due/status |
| ----------------- | ------------------ | ---------- |
| Team or subsystem | Concrete follow-up | Open       |

## Dated corrections

Append corrections here without rewriting the historical evidence above.
