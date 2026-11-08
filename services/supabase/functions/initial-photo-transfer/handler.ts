import {
  type CohortAdmissionRuntime,
  parseCohortVerification,
  verifyCohort,
} from "./verifyCohort.ts";
/** Dormant authenticated facade. No entrypoint, signer profile or activation. */
import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";
import { historyUUID } from "../_shared/analysisHistory/contract.ts";
import {
  type AllocationRequest,
  projectAllocationReceipt,
} from "../initial-photo-allocation/contract.ts";
import { matchesInitialSchema } from "../_shared/initialAnalysis/schema.ts";
import allocationSchema from "../initial-photo-allocation/schema-v3.json" with {
  type: "json",
};
import { initialMediaUnavailable } from "../_shared/initialAnalysis/mediaBinding.ts";
import {
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
} from "../_shared/initialAnalysis/transport.ts";
import {
  type CpmPhotoIssuanceBridge,
  issueInitialCpmPhotoUpload,
} from "../_shared/initialAnalysis/cpmPhotoUploadIssuer.ts";
import {
  type CpmPhotoStatusBridge,
  decodeCpmPhotoWriteStatus,
} from "../_shared/initialAnalysis/cpmPhotoWriteStatus.ts";
import {
  parseTransferRequest,
  statusIdentity,
  TRANSFER_REPLY_LIMIT,
  type TransferRequest,
} from "./contract.ts";
import type { TransferPolicyCatalog } from "./catalog.ts";
import { initialCanonicalText } from "../_shared/initialAnalysis/canonical.ts";
import { snapshotCpmWriteClosureInput } from "../_shared/initialAnalysis/cpmPhotoWriteClosure.ts";
import {
  mediaRecord,
  mediaUUID,
} from "../_shared/initialAnalysis/mediaBinding.ts";

import {
  readLiveRoleProgress,
  type RoleProgressBridge,
} from "./roleProgress.ts";

export interface TransferDependencies {
  recover(
    owner: string,
    request: AllocationRequest,
    signal: AbortSignal,
  ): Promise<unknown>;
  bridge: CpmPhotoIssuanceBridge & CpmPhotoStatusBridge;
  progress?: RoleProgressBridge;
  admission?: CohortAdmissionRuntime;
  catalog: TransferPolicyCatalog;
}

async function issue(
  request: TransferRequest,
  owner: string,
  deps: TransferDependencies,
  signal: AbortSignal,
) {
  if (request.allocation === null) throw initialMediaUnavailable();
  const recovery = await initialAbortable(
    signal,
    () => deps.recover(owner, request.allocation!, signal),
  );
  const recovered: unknown = JSON.parse(initialCanonicalText(recovery));
  const projected = await initialAbortable(
    signal,
    () => projectAllocationReceipt(request.allocation!, recovered),
  );
  if (!matchesInitialSchema(projected, allocationSchema.allocated)) {
    throw initialMediaUnavailable();
  }
  const receipt = projected as {
    backend_generation: string;
    backend_configuration_digest: string;
    created_at_ms: number;
    expires_at_ms: number;
    role_mapping: { object_id: string }[];
  };
  if (
    receipt.created_at_ms !== request.created ||
    receipt.expires_at_ms !== request.expires ||
    receipt.role_mapping.filter((entry) => entry.object_id === request.object)
        .length !== 1
  ) throw initialMediaUnavailable();
  const policy = deps.catalog.resolve(
    receipt.backend_generation,
    receipt.backend_configuration_digest,
  );
  // projectAllocationReceipt validated the entire private canonical assignment.
  // Bind the issuer's observation to that exact selected role before signing.
  const assignment = JSON.parse(
    (recovered as { assignment_canonical: string }).assignment_canonical,
  ) as {
    preparation: {
      role_mapping: {
        object_id: string;
        role: string;
        declaration: {
          byte_count: number;
          declared_content_type: string;
          sha256: string;
        };
      }[];
    };
  };
  const selected = assignment.preparation.role_mapping.find((entry) =>
    entry.object_id === request.object
  )!;
  const bridge: CpmPhotoIssuanceBridge = {
    async begin(identity, phase) {
      const raw: unknown = JSON.parse(
        initialCanonicalText(await deps.bridge.begin(identity, phase)),
      );
      if (
        typeof raw === "object" && raw !== null && "outcome" in raw &&
        raw.outcome === "held"
      ) return raw;
      const row = mediaRecord(raw, [
        "outcome",
        "attempt_id",
        "observation",
        "created_at_ms",
        "capability_expires_at_ms",
      ]);
      const observation = snapshotCpmWriteClosureInput(
        row.observation,
        mediaUUID(row.attempt_id),
        "live_object",
      );
      if (
        observation.binding.backend_generation !== receipt.backend_generation ||
        observation.binding.backend_configuration_digest !==
          receipt.backend_configuration_digest ||
        observation.admission_expires_at_ms !== request.expires ||
        typeof row.created_at_ms !== "number" ||
        row.created_at_ms < request.created ||
        observation.target.outcome !== "live_object" ||
        observation.target.role !== selected.role ||
        observation.target.byte_count !== selected.declaration.byte_count ||
        observation.target.content_type !==
          selected.declaration.declared_content_type ||
        observation.target.sha256 !== selected.declaration.sha256
      ) throw initialMediaUnavailable();
      return raw;
    },
    requireCurrent: (input, phase) => deps.bridge.requireCurrent(input, phase),
  };
  checkInitialDeadline(signal);
  // Only the issuer's fresh committed begin acknowledgement can reach signing.
  return await issueInitialCpmPhotoUpload(
    bridge,
    {
      owner,
      scan: request.scan,
      assignment_digest: request.assignmentDigest,
      object: request.object,
      policy: policy.policy_digest,
    },
    [policy.profile],
    signal,
  );
}

export async function initialPhotoTransfer(
  req: Request,
  body: unknown,
  owner: string,
  dependencies: () => TransferDependencies,
): Promise<Response> {
  let request: TransferRequest | ReturnType<typeof parseCohortVerification>;
  try {
    request = (body as { action?: unknown } | null)?.action === "verify_cohort"
      ? parseCohortVerification(body)
      : parseTransferRequest(body);
  } catch {
    return publicErrorResponse(
      req,
      400,
      "initial_photo_transfer_invalid",
      "Invalid photo transfer request.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
  try {
    const authenticatedOwner = historyUUID(owner);
    const deps = dependencies();
    const result = await initialDeadline(
      req.signal,
      request.action === "verify_cohort" ? 35_000 : 25_000,
      async (signal) => {
        if (request.action === "verify_cohort") {
          return await verifyCohort(request, authenticatedOwner, deps, signal);
        }
        const identity = statusIdentity(authenticatedOwner, request);
        // Historical status never loads a signing profile or falls through to issue.
        if (request.action === "status") {
          const observed = await initialAbortable(
            signal,
            () => deps.bridge.readStatus(identity, null, signal),
          );
          return decodeCpmPhotoWriteStatus(observed, identity);
        }
        if (request.action === "role_progress") {
          if (!deps.progress || !request.attempt) {
            throw initialMediaUnavailable();
          }
          return await readLiveRoleProgress(
            deps.progress,
            identity,
            request.attempt,
            signal,
          );
        }
        return await issue(request, identity.owner, deps, signal);
      },
    );
    checkInitialDeadline(req.signal);
    if (
      new TextEncoder().encode(JSON.stringify(result)).length >
        TRANSFER_REPLY_LIMIT
    ) {
      throw initialMediaUnavailable();
    }
    return jsonResponse(result, 200, { "Cache-Control": "private, no-store" });
  } catch {
    // Capability/SQL/provider data must never enter diagnostics or public errors.
    return publicErrorResponse(
      req,
      503,
      "initial_photo_transfer_unavailable",
      "Photo transfer is unavailable. Recover the original operation.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
}
