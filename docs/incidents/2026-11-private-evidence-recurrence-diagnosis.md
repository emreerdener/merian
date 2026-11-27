# Private-evidence cleanup recurrence diagnosis

Status: investigating; diagnostic source prepared, not deployed or recovered.
Target: beta Supabase `qlarqavoqhkuwzmevrmf`. Baseline:
`4aa05c8a2980a8dfe05f5bb1a4092620ce6acd8e`.

## Observations

The November 27 scheduled health report 61 reports intentionally disabled
worker, admission and cron, a preserved historical unknown/503 outcome, and a
stale successful heartbeat. Fresh read-only inspection confirms the dispatch
slot is empty and both History and capture-stage queues have zero pending work
or claims. The controls remain paused; no new recovery operation has been
performed.

The failure belongs to the earlier worker version 33. Current deployed version
49 is separate deployment evidence, not proof the intermittent issue is fixed.
The retained 02:40–05:56 UTC window has 185 HTTP 200 responses and one executed
HTTP 503. An HTTP 200 count is not terminal-receipt/settlement qualification.

The failed invocation returned after approximately 48.5 seconds. Serial bounded
RPCs make RPC delay plausible, but duration is not causal proof. The widened
05:51–05:59 UTC database window contains statement timeouts for other SELECTs,
the cleanup dispatcher and a cleanup claim. The dispatcher and claim errors
occurred after the Edge response and lack a retained common execution identity;
they cannot be attributed to that response. Complete log ingestion is unproven.
The worker's later EarlyDrop event similarly does not establish why it returned
503 earlier.

## Prepared diagnostics and invariants

The worker's database boundary now proposes fixed failure-stage/category events
through the existing identity-safe logging helper. The generic HTTP failure has
a fixed summary event. Raw errors and identities remain excluded. Logging cannot
change cleanup behavior. Existing deadlines, no-retry policy, SQL acquisition
fences, original-token settlement, unknown-slot preservation and monitor
failures remain unchanged. No timeout increase or lock-policy repair is
justified by the current evidence.

## Recovery sequence and remaining prerequisites

1. Independently review and validate the diagnostic patch on the exact baseline.
   Preserve the passing native evidence; this change has no native or client
   wire impact. Complete exact-candidate backend validation remains required
   before publication/deployment is qualified.
2. Obtain separate exact-target authorization to deploy the diagnostic worker
   while cleanup remains paused, using the canonical release procedure. Bind its
   deployed source, bundle, routine catalog and configuration without printing
   secrets. Deployment alone does not authorize restart.
3. Prepare a new exact-version restart packet with fresh empty-slot,
   paused-control, backlog, catalog, credential, transaction-drain and
   maintenance-window checks, a rollback-only rehearsal, once-only guarded
   activation, and protective pause. Old restart/slot-clear approvals and
   packets are consumed and must not replay.
4. After explicit restart authorization, require a fresh correlated V4 terminal
   receipt and matching database settlement. Keep collecting bounded aggregate
   health beyond the previous approximately three-hour recurrence window. A
   brief green heartbeat is initial qualification, not incident closure.
5. On any unknown or failed outcome, preserve its slot, stop through the
   approved protective pause, and capture stage categories plus bounded
   platform-log correlation before response retention expires. Do not
   automatically clear, replay, extend deadlines or suppress the monitor.
   Inspect live lock/wait state read-only if the diagnostic categories support
   that path.

No feature activation, site promotion, TestFlight upload/distribution, direct
storage operation, or production mutation is part of this preparation. Actual
object erasure and sustained recurring health remain distinct acceptance items.
