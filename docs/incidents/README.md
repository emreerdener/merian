# Incident Records

This directory contains Merian reliability, security, privacy, data-integrity,
and release incident records. Each record is historical evidence: it explains
what was observed, which invariant failed, what changed, and which closure
conditions were or were not satisfied at that time.

Use [`TEMPLATE.md`](./TEMPLATE.md) for a new incident. Name records
`YYYY-MM-short-slug.md`; add a day only when multiple records in one month would
otherwise collide.

## Authority and lifecycle

Incident records do not replace current architecture, API, security, testing, or
release contracts. Link the relevant canonical document and update that document
when present behavior changes. Preserve the original incident evidence and add
dated corrections or status updates rather than rewriting history.

Use precise status language:

1. investigating,
2. reproduced,
3. mitigated in source,
4. candidate validated,
5. deployed,
6. runtime verified,
7. data recovery complete,
8. closed.

These states are independent. A green local or CI result does not prove a
production deployment, runtime recovery, or repaired data. Deployment and data
mutation require the explicit authorization and target described in root
`AGENTS.md` and the canonical runbook.

## Evidence and privacy

- Distinguish direct observation from inference and record dates, versions, and
  environments needed to interpret evidence.
- Use synthetic fixtures or redacted aggregates. Never include credentials,
  personal data, raw coordinates, auth/session material, or production response
  bodies.
- Link immutable candidate or release evidence rather than copying sensitive
  logs into the repository.
- State which device, hosted, deployment, monitoring, or recovery checks remain
  unrun.

## Maintaining the index

`docs/README.md` provides the curated incident index. Add a concise entry there
for every new record. If an incident changes a current invariant, also update
the canonical contract, test ownership matrix, and local owner README in the
same change.
