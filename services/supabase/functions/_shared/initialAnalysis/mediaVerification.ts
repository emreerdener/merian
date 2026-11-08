import { initialCanonicalText } from "./canonical.ts";
import {
  decodeInitialMediaBackend,
  type InitialMediaBinding,
  type InitialMediaBuffers,
  type InitialMediaScope,
  initialMediaUnavailable,
  mediaRecord,
  mediaTime,
  mediaUUID,
  snapshotInitialMedia,
  verifyInitialMediaSnapshot,
} from "./mediaBinding.ts";
import {
  type InitialMediaStorageDependencies,
  markInitialMediaErased,
  retainInitialMediaObject,
} from "./mediaStorage.ts";
import {
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
} from "./transport.ts";

export type InitialMediaOperation =
  | "claim_initial_media_preparation"
  | "settle_initial_media_verification"
  | "get_initial_media_verification"
  | "get_initial_media_backend"
  | "claim_initial_analysis_media_erasure"
  | "finish_initial_analysis_media_erasure";
export interface InitialMediaDependencies
  extends InitialMediaStorageDependencies {
  /** Fixed service operations only. The production composition is deliberately
   * not installed; no caller route or media URL is accepted by this owner. */
  call(
    operation: InitialMediaOperation,
    args: Record<string, unknown>,
    signal: AbortSignal,
  ): Promise<unknown>;
}
export type InitialMediaResult =
  | { version: 1; outcome: "held"; reason: string }
  | {
    version: 1;
    outcome: "verified" | "replay";
    receipt: Record<string, unknown>;
  };
function closed(value: unknown): unknown {
  const text = initialCanonicalText(value);
  if (new TextEncoder().encode(text).length > 65_536) {
    throw initialMediaUnavailable();
  }
  return JSON.parse(text);
}
function result(
  value: unknown,
  binding: InitialMediaBinding,
  reasons: readonly string[],
  first: boolean,
): InitialMediaResult {
  const envelope = value as Record<string, unknown>;
  if (envelope?.outcome === "held") {
    mediaRecord(envelope, ["version", "outcome", "reason"]);
    if (
      envelope.version !== 1 || !reasons.includes(envelope.reason as string)
    ) throw initialMediaUnavailable();
    return envelope as InitialMediaResult;
  }
  mediaRecord(envelope, ["version", "outcome", "receipt"]);
  if (
    envelope.version !== 1 ||
    (envelope.outcome !== "replay" &&
      !(first && envelope.outcome === "verified"))
  ) throw initialMediaUnavailable();
  const receipt = mediaRecord(envelope.receipt, [
    "version",
    "owner_id",
    "scan_id",
    "submission_digest",
    "manifest_digest",
    "backend_generation",
    "verified_at",
  ]);
  for (
    const key of [
      "version",
      "owner_id",
      "scan_id",
      "submission_digest",
      "manifest_digest",
      "backend_generation",
    ] as const
  ) if (receipt[key] !== binding[key]) throw initialMediaUnavailable();
  mediaTime(receipt.verified_at);
  return envelope as InitialMediaResult;
}
function args(binding: InitialMediaBinding): Record<string, unknown> {
  return {
    p_owner: binding.owner_id,
    p_scan: binding.scan_id,
    p_submission_digest: binding.submission_digest,
    p_manifest_digest: binding.manifest_digest,
  };
}
async function call(
  deps: InitialMediaDependencies,
  op: InitialMediaOperation,
  parameters: Record<string, unknown>,
  signal: AbortSignal,
): Promise<unknown> {
  return closed(
    await initialAbortable(signal, () => deps.call(op, parameters, signal)),
  );
}
/** One bounded storage attempt. Unknown settlement permits exact receipt read
 * only; callbacks arriving after abort never begin settlement or new I/O. */
export async function verifyAndRetainInitialMedia(
  deps: InitialMediaDependencies,
  bindingValue: unknown,
  input: unknown,
  scope: InitialMediaScope,
  buffers: readonly InitialMediaBuffers[],
  caller: AbortSignal,
): Promise<InitialMediaResult> {
  const started = performance.now();
  caller.throwIfAborted();
  const snapshot = snapshotInitialMedia(bindingValue, input, scope, buffers);
  const binding = snapshot.binding;
  return await initialDeadline(
    caller,
    Math.max(0, 20_000 - (performance.now() - started)),
    async (signal) => {
      await initialAbortable(
        signal,
        () => verifyInitialMediaSnapshot(snapshot),
      );
      const requestStarted = performance.now();
      const envelope = await call(
        deps,
        "claim_initial_media_preparation",
        args(binding),
        signal,
      ) as Record<string, unknown>;
      if (envelope.outcome !== "claimed") {
        return result(envelope, binding, [
          "missing",
          "busy",
          "retired",
          "expired",
          "disabled",
          "in_use",
        ], false);
      }
      mediaRecord(envelope, ["version", "outcome", "binding", "claim"]);
      if (
        envelope.version !== 1 ||
        initialCanonicalText(envelope.binding) !== initialCanonicalText(binding)
      ) throw initialMediaUnavailable();
      const claim = mediaRecord(envelope.claim, [
        "token",
        "issued_at",
        "expires_at",
      ]);
      const token = mediaUUID(claim.token),
        issued = mediaTime(claim.issued_at),
        expires = mediaTime(claim.expires_at);
      if (
        expires <= issued || expires - issued > 60_000 ||
        expires > binding.expires_at
      ) throw initialMediaUnavailable();
      // Subtract the entire claim round trip: conservative even if local/server
      // wall clocks differ. SQL independently checks actual server expiry.
      const remaining = Math.min(
        expires - Date.now(),
        expires - issued - (performance.now() - requestStarted),
        20_000 - (performance.now() - started),
      );
      if (remaining <= 5_000) {
        return {
          version: 1,
          outcome: "held",
          reason: "budget",
        };
      }
      return await initialDeadline(signal, remaining, async (leaseSignal) => {
        await initialDeadline(
          leaseSignal,
          remaining - 5_000,
          async (storageSignal) => {
            const backend = decodeInitialMediaBackend(
              await call(deps, "get_initial_media_backend", {
                p_generation: binding.backend_generation,
              }, storageSignal),
              binding.backend_generation,
            );
            for (const object of snapshot.objects) {
              checkInitialDeadline(storageSignal);
              await retainInitialMediaObject(
                deps,
                backend,
                binding.scan_id,
                object.role,
                object.bytes,
                storageSignal,
              );
            }
          },
        );
        checkInitialDeadline(leaseSignal);
        try {
          return result(
            await call(deps, "settle_initial_media_verification", {
              ...args(binding),
              p_preparation_token: token,
            }, leaseSignal),
            binding,
            ["missing", "retired", "in_use", "stale"],
            true,
          );
        } catch {
          checkInitialDeadline(leaseSignal);
          return result(
            await call(
              deps,
              "get_initial_media_verification",
              args(binding),
              leaseSignal,
            ),
            binding,
            ["missing", "retired"],
            false,
          );
        }
      });
    },
  );
}
/** The cleanup claim identifies an already permanently retired destination.
 * Unknown acknowledgement stays unknown; an empty next claim is not success. */
export async function eraseOneInitialMediaObject(
  deps: InitialMediaDependencies,
  caller: AbortSignal,
): Promise<"empty" | "acknowledged" | "stale"> {
  const started = performance.now();
  return await initialDeadline(caller, 20_000, async (signal) => {
    const envelope = await call(
      deps,
      "claim_initial_analysis_media_erasure",
      {},
      signal,
    ) as Record<string, unknown>;
    if (envelope.outcome === "empty") {
      mediaRecord(envelope, ["version", "outcome"]);
      if (envelope.version !== 1) throw initialMediaUnavailable();
      return "empty";
    }
    mediaRecord(envelope, ["version", "outcome", "object"]);
    if (envelope.version !== 1 || envelope.outcome !== "claimed") {
      throw initialMediaUnavailable();
    }
    const object = mediaRecord(envelope.object, [
      "scan_id",
      "object_id",
      "backend_generation",
      "claim_token",
      "claim_expires_at",
    ]);
    const scan = mediaUUID(object.scan_id),
      id = mediaUUID(object.object_id),
      generation = mediaUUID(object.backend_generation),
      token = mediaUUID(object.claim_token);
    const remaining = Math.min(
      20_000 - (performance.now() - started),
      mediaTime(object.claim_expires_at) - Date.now(),
    );
    if (remaining <= 5_000) throw initialMediaUnavailable();
    return await initialDeadline(signal, remaining, async (leaseSignal) => {
      await initialDeadline(
        leaseSignal,
        remaining - 5_000,
        async (storageSignal) => {
          const backend = decodeInitialMediaBackend(
            await call(deps, "get_initial_media_backend", {
              p_generation: generation,
            }, storageSignal),
            generation,
          );
          await markInitialMediaErased(deps, backend, scan, id, storageSignal);
        },
      );
      const ack = mediaRecord(
        await call(deps, "finish_initial_analysis_media_erasure", {
          p_object: id,
          p_claim: token,
          p_success: true,
        }, leaseSignal),
        ["version", "outcome"],
      );
      if (
        ack.version !== 1 ||
        (ack.outcome !== "acknowledged" && ack.outcome !== "stale")
      ) throw initialMediaUnavailable();
      return ack.outcome;
    });
  });
}
