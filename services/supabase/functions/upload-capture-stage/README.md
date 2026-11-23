# Private capture stage upload

Prepared authenticated ingress for one client-known artifact of a complete
version-1 capture plan, before ordinary admission. See the
[canonical contract](../../../../docs/backend-and-data/05-api-contracts.md#prepared-capture-upload-plan-and-audio-recovery--november-20).

JWT identity owns the plan. Binary wire1 carries a closed plan and media ID;
clients never choose an object key, private backend, role or server-audio bytes.
The same private stage parent records every client destination before writing.
One-shot write authorization precedes conditional private PUT, and full readback
must verify before completion. Unknown writes recover through readback only. All
storage uses the private `capture-stage/v1` namespace. Account/scan retirement
and retained adoption use the existing typed V4 erasure owner.

The response acknowledges only that artifact's readiness. It cannot admit a job,
reserve funding, invoke a provider, complete History or release local originals.
The schema-4 complete-stage begin successor and live Identify continuation are
connected in source; the native upload caller remains unconnected. This source
change does not authorize deployment or activation.

Run the route suite and shared `initialCaptureClientStaging_test.ts`, plus the
client-stage/adoption disposable database suites and catalog security tests.
