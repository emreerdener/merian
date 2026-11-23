/** Prepared service composition, not an installed route. Source-proof admission,
 * typed finalization and original release remain separate owners. Only this
 * composition may attest a receipt, after the actual bounded byte verifier. */
import {
  type CapturePromotionBinding,
  type CapturePromotionStorageDependencies,
  snapshotCapturePromotionBinding,
  transferVerifiedCapturePromotion,
  verifyCapturePromotionDestination,
} from "./capturePromotionStorage.ts";
import { MEDIA_BUDGETS } from "./mediaBudgets.ts";
import { fetchWithDeadline } from "./outbound.ts";
import {
  requireServerApiKeyFromEnvironment,
  serviceRoleRequestHeaders,
} from "./serviceRoleAuth.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "./initialAnalysis/transport.ts";

type Storage = Omit<CapturePromotionStorageDependencies, "authorize">;
export interface CapturePromotionTransfer {
  readonly cohortId: string;
  readonly manifestSHA256: string;
  readonly requestSHA256: string;
  /** Complete saved storage inventory, in ingestion manifest order. */
  readonly bindings: readonly CapturePromotionBinding[];
  /** Exactly one member to transfer; never invent a replacement ID on retry. */
  readonly operationId: string;
}
export interface CapturePromotionRecovery {
  readonly cohortId: string;
  readonly binding: CapturePromotionBinding;
}
export interface CapturePromotionReceipt {
  readonly operationId: string;
  readonly cohortId: string;
  readonly verifiedAt: string;
  readonly origin:
    | "write_acknowledged"
    | "write_precondition_failed"
    | "destination_recovery";
}
export type CapturePromotionResult =
  | { readonly outcome: "verified"; readonly receipt: CapturePromotionReceipt }
  | { readonly outcome: "held" };

const unavailable = () => new Error("capture_promotion_unavailable");
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const digest = /^[0-9a-f]{64}$/;
function scalar(value: unknown, pattern: RegExp): string {
  if (typeof value !== "string" || !pattern.test(value)) throw unavailable();
  return value;
}
function record(value: unknown, keys: string[]): Record<string, unknown> {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(value, key))
  ) throw unavailable();
  return value as Record<string, unknown>;
}
function binding(value: CapturePromotionBinding) {
  const b = snapshotCapturePromotionBinding(value);
  if (
    !["free", "pro"].some((tier) =>
      b.destinationKey ===
        `public_uploads/${tier}/${b.ownerId}/capture-promotion-${b.operationId}`
    )
  ) throw unavailable();
  return b;
}
function storageSnapshot(value: Storage): Storage {
  return Object.freeze({
    backend: Object.freeze({ ...value.backend }),
    sign: value.sign.bind(value),
    fetch: value.fetch.bind(value),
  });
}
function validCalendarDate(value: string): boolean {
  const time = Date.parse(`${value}T00:00:00Z`);
  return Number.isFinite(time) &&
    new Date(time).toISOString().slice(0, 10) === value;
}
function receipt(
  value: unknown,
  b: CapturePromotionBinding,
  cohort: string,
): CapturePromotionReceipt {
  const r = record(value, ["operationId", "cohortId", "verifiedAt", "origin"]);
  if (
    r.operationId !== b.operationId || r.cohortId !== cohort ||
    typeof r.verifiedAt !== "string" || r.verifiedAt.length > 40 ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
      .test(r.verifiedAt) ||
    !Number.isFinite(Date.parse(r.verifiedAt)) ||
    !validCalendarDate(r.verifiedAt.slice(0, 10)) ||
    typeof r.origin !== "string" ||
    !["write_acknowledged", "write_precondition_failed", "destination_recovery"]
      .includes(String(r.origin))
  ) {
    throw unavailable();
  }
  // A valid previous origin may differ: SQL preserves the first observation.
  return Object.freeze({
    operationId: b.operationId,
    cohortId: cohort,
    verifiedAt: r.verifiedAt,
    origin: r.origin as CapturePromotionReceipt["origin"],
  });
}

/** Environment-owned credentials and four fixed RPC names. No generic SQL/RPC
 * capability, public receipt attestation, retries or direct ledger access. */
export function createCapturePromotionDb(fetcher: typeof fetch = fetch) {
  const base = new URL(Deno.env.get("SUPABASE_URL") ?? "");
  if (
    base.username || base.password || base.pathname !== "/" || base.search ||
    base.hash ||
    !(base.protocol === "https:" || (base.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname)))
  ) throw unavailable();
  const headers = Object.freeze({
    ...serviceRoleRequestHeaders(requireServerApiKeyFromEnvironment()),
    "Content-Type": "application/json",
    "Accept": "application/json",
  });
  async function call(
    name:
      | "register_capture_promotion_ingestion"
      | "authorize_capture_promotion_action"
      | "authorize_capture_promotion_recovery"
      | "record_capture_promotion_verification",
    args: Record<string, unknown>,
    signal: AbortSignal,
  ): Promise<unknown> {
    const body = JSON.stringify(args);
    if (new TextEncoder().encode(body).length > 32768) throw unavailable();
    return await initialDeadline(signal, 5000, async (phase) => {
      const response = await initialAbortable(phase, () =>
        fetchWithDeadline(
          new URL(`/rest/v1/rpc/${name}`, base),
          {
            method: "POST",
            headers,
            body,
            signal: phase,
            redirect: "error",
            cache: "no-store",
            credentials: "omit",
          },
          { fetcher, timeoutMs: 5000 },
        ), (late) => cancelInitialStream(late.body));
      if (
        response.status !== 200 || response.headers.has("content-encoding") ||
        !/^application\/json(?:;\s*charset=utf-8)?$/i.test(
          response.headers.get("content-type") ?? "",
        )
      ) {
        cancelInitialStream(response.body);
        throw unavailable();
      }
      const bytes = await readInitialStream(response.body, 8192, phase);
      const result: unknown = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      );
      checkInitialDeadline(phase);
      return result;
    });
  }
  async function attest(
    b: CapturePromotionBinding,
    cohort: string,
    origin: CapturePromotionReceipt["origin"],
    signal: AbortSignal,
  ) {
    return receipt(
      await call("record_capture_promotion_verification", {
        p_binding: b,
        p_origin: origin,
      }, signal),
      b,
      cohort,
    );
  }
  return Object.freeze({
    async transfer(
      input: CapturePromotionTransfer,
      storage: Storage,
      caller: AbortSignal,
    ): Promise<CapturePromotionResult> {
      try {
        record(input, [
          "cohortId",
          "manifestSHA256",
          "requestSHA256",
          "bindings",
          "operationId",
        ]);
        const cohort = scalar(input.cohortId, uuid);
        const manifest = scalar(input.manifestSHA256, digest);
        const request = scalar(input.requestSHA256, digest);
        const operation = scalar(input.operationId, uuid);
        if (
          !Array.isArray(input.bindings) || input.bindings.length < 1 ||
          input.bindings.length > MEDIA_BUDGETS.maxStagingFiles
        ) throw unavailable();
        const members = Object.freeze(input.bindings.map(binding));
        for (
          const key of [
            "operationId",
            "assetId",
            "sourceKey",
            "destinationKey",
          ] as const
        ) {
          if (new Set(members.map((b) => b[key])).size !== members.length) {
            throw unavailable();
          }
        }
        if (
          members.some((b) =>
            b.ownerId !== members[0].ownerId ||
            b.scanId !== members[0].scanId ||
            b.backendSHA256 !== members[0].backendSHA256
          )
        ) throw unavailable();
        const b = members.find((member) => member.operationId === operation);
        if (!b) throw unavailable();
        const savedStorage = storageSnapshot(storage);
        return await initialDeadline(caller, 60_000, async (signal) => {
          const registration = record(
            await call("register_capture_promotion_ingestion", {
              p_cohort: cohort,
              p_manifest: manifest,
              p_request: request,
              p_bindings: members,
            }, signal),
            ["cohortId", "jobId", "cohortSHA256"],
          );
          if (registration.cohortId !== cohort) throw unavailable();
          scalar(registration.jobId, uuid);
          scalar(registration.cohortSHA256, digest);
          const result = await transferVerifiedCapturePromotion(b, {
            ...savedStorage,
            async authorize(saved, action, phase) {
              if (
                await call("authorize_capture_promotion_action", {
                  p_binding: saved,
                  p_action: action,
                }, phase) !== true
              ) throw unavailable();
            },
          }, signal);
          if (result.outcome !== "verified") return { outcome: "held" };
          const verified = await attest(
            b,
            cohort,
            result.write === "acknowledged"
              ? "write_acknowledged"
              : "write_precondition_failed",
            signal,
          );
          checkInitialDeadline(signal);
          return { outcome: "verified", receipt: verified };
        });
      } catch {
        return { outcome: "held" };
      }
    },
    async recover(
      input: CapturePromotionRecovery,
      storage: Storage,
      caller: AbortSignal,
    ): Promise<CapturePromotionResult> {
      try {
        record(input, ["cohortId", "binding"]);
        const cohort = scalar(input.cohortId, uuid), b = binding(input.binding);
        const savedStorage = storageSnapshot(storage);
        return await initialDeadline(caller, 60_000, async (signal) => {
          const result = await verifyCapturePromotionDestination(b, {
            ...savedStorage,
            async authorize(saved, action, phase) {
              if (
                action !== "read_destination" ||
                await call("authorize_capture_promotion_recovery", {
                    p_binding: saved,
                  }, phase) !== true
              ) throw unavailable();
            },
          }, signal);
          if (result.outcome !== "verified") return { outcome: "held" };
          const verified = await attest(
            b,
            cohort,
            "destination_recovery",
            signal,
          );
          checkInitialDeadline(signal);
          return { outcome: "verified", receipt: verified };
        });
      } catch {
        return { outcome: "held" };
      }
    },
  });
}
