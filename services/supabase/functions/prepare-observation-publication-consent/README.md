# Prepare observation publication consent

Owner-authenticated POST read for one explicit analysis. `route.ts` owns bounded
JSON/auth/no-store handling; `db.ts` invokes the service-only owner RPC with a
12-second deadline; `handler.ts` validates the closed correlated response using
`_shared/analysisHistory/publicationConsent.ts`. Owner identity comes
exclusively from verified authentication. No admission, provider or media I/O
occurs.

The snapshot contains exact revisions, active taxonomy, fixed-null initial taxon
and ordered immutable V2 photo metadata only. Candidate count can exceed six;
final explicit consent must select 1–6 photos. Candidates confer neither ready
media nor current publication authority. General history/status reads are
unchanged. All activation gates remain false, and the native consent producer
and UI remain separate work.

See the
[canonical API contract](../../../../docs/backend-and-data/05-api-contracts.md#owner-publication-consent-preflight)
for exact fields, eligibility, errors and later-admission revalidation.
