import {
  type CpmPhotoStatusBridge,
  type CpmPhotoStatusIdentity,
  decodeCpmPhotoWriteStatus,
  snapshotCpmPhotoStatusIdentity,
} from "../_shared/initialAnalysis/cpmPhotoWriteStatus.ts";
import {
  type CpmWriteClosureBridge,
  decodeCpmWriteClosureReceipt,
  snapshotCpmWriteClosureInput,
} from "../_shared/initialAnalysis/cpmPhotoWriteClosure.ts";
import { initialMediaUnavailable } from "../_shared/initialAnalysis/mediaBinding.ts";
import {
  checkInitialDeadline,
  initialAbortable,
} from "../_shared/initialAnalysis/transport.ts";

export type RoleProgressBridge =
  & CpmPhotoStatusBridge
  & Pick<CpmWriteClosureBridge, "readReceipt" | "load">;

/** A live closure alone can outlive erasure. Rejoin the original authenticated
 * attempt to the current locked live snapshot AFTER reading its immutable
 * receipt. This reads metadata only; next-role issuance and final cohort
 * verification still have to pass their own independent current fences. */
export async function readLiveRoleProgress(
  bridge: RoleProgressBridge,
  original: CpmPhotoStatusIdentity,
  attemptID: string,
  signal: AbortSignal,
) {
  const identity = snapshotCpmPhotoStatusIdentity(original);
  const status = decodeCpmPhotoWriteStatus(
    await initialAbortable(
      signal,
      () => bridge.readStatus(identity, null, signal),
    ),
    identity,
  );
  const attempt = status.attempt;
  if (
    !attempt?.write_closed || attempt.attempt_id !== attemptID ||
    attempt.state !== "may_have_issued"
  ) throw initialMediaUnavailable();
  const receipt = decodeCpmWriteClosureReceipt(
    await initialAbortable(
      signal,
      () => bridge.readReceipt(attemptID, "live_object", signal),
    ),
    attemptID,
    "live_object",
  );
  const live = snapshotCpmWriteClosureInput(
    await initialAbortable(
      signal,
      () => bridge.load(attemptID, "live_object", signal),
    ),
    attemptID,
    "live_object",
  );
  const b = live.binding, t = live.target;
  const observed = Date.parse(receipt.observed_at);
  if (
    t.outcome !== "live_object" || b.scan_id !== identity.scan ||
    b.object_id !== identity.object ||
    b.assignment_digest !== identity.assignment_digest ||
    b.verification_policy_digest !== receipt.policy_digest ||
    live.admission_expires_at_ms !== identity.allocation_expires_at_ms ||
    b.issued_at_ms < attempt.created_at_ms ||
    b.issued_at_ms > attempt.capability_expires_at_ms ||
    observed < b.issued_at_ms || observed >= live.admission_expires_at_ms ||
    Date.now() >= live.admission_expires_at_ms
  ) throw initialMediaUnavailable();
  checkInitialDeadline(signal);
  return Object.freeze({
    version: 2,
    outcome: "live_role_observed",
    authority: "none",
    owner_id: identity.owner,
    scan_id: b.scan_id,
    assignment_digest: b.assignment_digest,
    object_id: b.object_id,
    attempt_id: attemptID,
    role: t.role,
    byte_count: t.byte_count,
    content_type: t.content_type,
    sha256: t.sha256,
    backend_generation: b.backend_generation,
    backend_configuration_digest: b.backend_configuration_digest,
    policy_digest: receipt.policy_digest,
    observed_at: receipt.observed_at,
  });
}
