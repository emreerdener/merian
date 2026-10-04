# Private history photo resolution

Prepared authenticated POST route; not deployed and both database read gates
remain false. `index.ts` uses the common verified auth/body/error boundary;
`handler.ts` validates the exact protocol-8 request and returns a transient
no-store photo ticket; `db.ts` alone calls the service-only completed-result
receipt RPC. `PrivateHistoryEvidenceStorage` signs with the dedicated read
credential. The handler rechecks ownership/deletion after signing.

No upload, inference, publication, credit settlement, public-media fallback or
persistent cache is involved. SQL and Edge tests cover denied owners, incomplete
uploads, legacy readers, deletion/account races and diagnostic redaction. The
native loader verifies the content tuple and bytes and never stores the URL.

The
[API contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-protocol-8-reads-and-private-photo-resolution)
owns request/response fields, limits, bearer-capability lifetime and remaining
activation requirements.
