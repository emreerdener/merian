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

`ObservationPublicationConsentRequest` and
`ObservationPublicationConsentSnapshot` add a separate descriptive preflight for
an explicit historical analysis. Its exact eight-field response has its own 32
KiB cap; admission/status retain their 4 KiB decoder. Initial taxon must be
present and null. Exact candidate objects preserve all 1–64 photo references in
server order, with unique lowercase UUIDs, JPEG/PNG/HEIC types, positive
integral byte counts, a 32 MiB aggregate cap and exact lowercase SHA-256. No
object key, URL, operation or visibility field is accepted. These candidates do
not prove ready media or select the final cohort.

`MerianNetworkClient+ObservationPublication` reuses the existing pinned raw-JSON
bridge, requires the expected owner at dispatch and disables classified-401
session recovery so Auth-drained work cannot await itself. None of its three
routes opts into automatic ambiguous-transport replay. Existing platform-route
discovery retries remain unchanged. The separate durable delivery owner now
recovers saved publication operations; the prepared foreground consent service
validates explicit choices before persistence, while ordinary UI remains
unconnected. This layer never mints operation IDs or calls legacy sharing.
`ObservationPublicationConsentService` saves the exact chosen 1–6 media before
delivery, fences account/session changes and rejects stale preflight state. No
rollout activation.

See the
[API contract](../../../../../../../docs/backend-and-data/05-api-contracts.md#owner-publication-consent-preflight).
