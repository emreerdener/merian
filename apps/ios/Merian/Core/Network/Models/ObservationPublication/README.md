# Observation publication wire models

Prepared native boundary for immutable publication admission and exact-operation
status reads. `ObservationPublicationRequest` freezes caller-provided operation,
observation and analysis IDs, revisions, taxonomy, note and ordered consent.
Construction and strict saved-request decoding enforce the backend bounds: 1–6
unique media IDs, bounded integer revisions, at most 1,000 Unicode scalars in
the note and a 3,800-byte encoded request. UUIDs encode lowercase and nullable
fields encode explicit null. Restoring a request does not create a new
operation.

`ObservationPublicationReceipt` admits only exact, bounded server fields and
matches all three IDs against the initiating request. Admission requires the
accepted receipt and valid timestamp; polling accepts only the five documented
states. Private reasons, media, work tokens and post IDs fail closed. A
historical `admitted` status is not current visibility or identification
authority.

`MerianNetworkClient+ObservationPublication` reuses the existing pinned raw-JSON
bridge, requires the expected owner at dispatch and disables classified-401
session recovery so a future Auth-drained outbox cannot await itself. Neither
route opts into automatic ambiguous-transport replay. Existing platform-route
discovery retries remain unchanged. No legacy sharing fallback, operation-ID
generation, outbox, UI or rollout activation is added. A future durable owner
must save before I/O and recheck its account lease and current scan/job after
every await before changing local state.

See the
[API contract](../../../../../../../docs/backend-and-data/05-api-contracts.md#native-publication-wire-boundary).
