# Incident workflow

Use this workflow for an active incident, a regression discovered during
refactoring, or a historical post-incident review.

## Status model

Do not collapse the following states:

1. **Investigating** — impact or cause is not yet bounded.
2. **Reproduced** — a deterministic or evidence-backed failure path exists.
3. **Mitigated in source** — the repository fix and regression coverage exist.
4. **Candidate validated** — required gates passed for one exact candidate.
5. **Deployed** — an explicitly authorized operation changed the named target.
6. **Runtime verified** — sanitized positive and negative checks confirm the
   target behaves as intended.
7. **Data recovery complete** — affected durable records are repaired,
   quarantined, or documented as unrecoverable.
8. **Closed** — every declared exit criterion is satisfied.

## Investigation sequence

- Define symptom, expected behavior, impact, first/last known occurrence, and
  affected versions or environments.
- Build a state-transition timeline from durable evidence. Use monotonic event
  order where wall clocks or client timestamps are unreliable.
- Compare one failing and one known-good path.
- Classify the boundary: client lifecycle, persistence/migration, offline queue,
  API contract, Auth, database authorization, Edge processing, media storage,
  public projection, or release artifact.
- Test competing hypotheses and record why each was accepted or rejected.
- Locate the narrowest invariant owner and every downstream consumer that may
  contain partial or stale state.

## Regression design

A regression should:

- use synthetic or redacted fixtures,
- reproduce the causal order, not only the final error string,
- assert durable state and user-visible outcome separately,
- cover retries, duplicates, cancellation, account/session changes, and stale
  completion when relevant,
- prove unauthorized or cross-account paths remain denied,
- avoid real providers and production endpoints in automated tests.

## Operational boundary

Repository edits, local tests, disposable databases, and candidate validation
are implementation work. Hosted writes, deployment, key rotation, queue replay,
data cleanup, TestFlight/App Store actions, RevenueCat changes, and rollback are
operations that require explicit authorization. Unknown targets stay read-only.

## Documentation boundary

Use `docs/incidents/TEMPLATE.md`. Preserve original observations and append
dated corrections. Link current behavior to canonical contracts instead of
turning the incident into the permanent architecture guide. Never publish
credentials, personal data, raw coordinates, session material, or raw production
payloads.
