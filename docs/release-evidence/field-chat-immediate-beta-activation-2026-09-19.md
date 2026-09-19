# Immediate Field Chat beta activation — September 19, 2026

## Owner direction and scope

After the successful backend deployment, the owner explicitly requested Field
Chat activation now instead of scheduling another deployment after midnight UTC.
This supersedes only the next-day waiting requirement in the
[September 18 beta decision](./field-chat-beta-release-decision-2026-09-18.md)
for the pending beta cutover on Supabase project `qlarqavoqhkuwzmevrmf`. The
scheduled follow-up was paused. This record describes authorization and the
implemented policy; it does not claim production activation or passing checks.

## First-day accounting tradeoff

The original migration populated the durable daily usage ledger from retained
messages. Messages deleted before that migration cannot be reconstructed, so
those counts are a lower bound for that partial UTC day. The next-day fence was
a conservative accounting policy, not a Supabase scheduling requirement.

Immediate beta activation preserves every recorded count. A user whose earlier
messages were deleted may receive additional capacity during the remainder of
that UTC day. Fresh admissions still stop when the durable ledger reaches 20;
this does not establish an upper bound on historical usage before the migration.
From the next UTC day onward, the new deletion-resistant ledger accounts for all
admissions normally. Authentication, consent, eligibility, atomic quotas,
conversation caps, idempotency, and provider controls remain unchanged.

## Forward change and retained controls

`20260919125625_authorize_immediate_field_chat_beta_activation.sql` locks the
single cutover row and advances only a still-pending, unactivated fence using
the database clock. It records `beta_original_not_before_utc` and
`beta_early_activation_at` for audit. Already-ready and already-active
installations remain unchanged. The migration does not activate sends, change
usage counts, modify grants or admission routines, or expose the private audit
columns through the service RPC.

The owner-only deployment tools accept a non-midnight eligibility time only when
both audit values agree with that time and retain a later original UTC boundary.
The Production workflow must still validate the exact candidate, force-deploy
all three Field Chat bundles in `ready` state, observe their exact live digests,
and perform the existing one-way activation. There is no runtime bypass flag or
recurring early-activation operation. Failures leave admission closed. Follow
the [deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md)
for verification and forward recovery.
