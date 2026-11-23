import {
  deleteR2ObjectIfPresent,
  getR2Config,
  headR2Object,
  type R2Config,
} from "./aws.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

/** Bind exact keys to the configured backend, without persisting credentials. */
export async function captureObjectBackendDigest(
  config: Pick<R2Config, "endpoint" | "bucketName">,
): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify([
    "capture-r2-backend-v1",
    config.endpoint,
    config.bucketName,
  ]));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((v) => v.toString(16).padStart(2, "0"))
    .join("");
}

type Claim = {
  backend_sha256: string;
  object_key: string;
  owner_id: string;
  issued_until: string;
};
type Services = {
  config: R2Config;
  deleteObject: typeof deleteR2ObjectIfPresent;
  headObject: typeof headR2Object;
  now: () => number;
};
export type CaptureRetirementResult = {
  claimed: number;
  observedAbsent: number;
  deferred: number;
  /** Every claim remains durably unresolved; absence is not quiescence. */
  unresolved: number;
};

export async function captureRetirementHealth(
  client: SupabaseClient,
): Promise<Record<string, number>> {
  const { data, error } = await client.rpc("capture_object_retirement_health");
  const fields = [
    "unresolved_count",
    "due_count",
    "leased_count",
    "error_count",
    "oldest_retired_age_seconds",
  ];
  if (
    error || !data || typeof data !== "object" || Array.isArray(data) ||
    fields.some((field) =>
      !Number.isSafeInteger(data[field]) || data[field] < 0
    )
  ) {
    throw new Error("Capture retirement health unavailable.");
  }
  return Object.fromEntries(fields.map((field) => [field, data[field]]));
}

function claims(value: unknown): Claim[] {
  if (!Array.isArray(value) || value.length > 25) {
    throw new Error("Invalid capture retirement batch.");
  }
  const keys = new Set<string>();
  return value.map((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new Error("Invalid capture retirement claim.");
    }
    const row = item as Claim;
    if (
      typeof row.backend_sha256 !== "string" ||
      !/^[a-f0-9]{64}$/.test(row.backend_sha256) ||
      typeof row.owner_id !== "string" ||
      !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(row.owner_id) ||
      typeof row.object_key !== "string" ||
      !new RegExp(`^staging/${row.owner_id}/[A-Za-z0-9_.-]{1,255}$`).test(
        row.object_key,
      ) || typeof row.issued_until !== "string" ||
      !Number.isFinite(Date.parse(row.issued_until))
    ) throw new Error("Invalid capture retirement identity.");
    const key = `${row.backend_sha256}:${row.object_key}`;
    if (keys.has(key)) throw new Error("Duplicate capture retirement claim.");
    keys.add(key);
    return { ...row };
  });
}

/** One bounded pass of permanently retired staging objects; no scan row needed.
 * Expired claims are coordination only: the immutable retirement authorizes
 * deletion. Unknown I/O/acknowledgement stays discoverable for the next pass.
 */
export async function reconcileCaptureObjectRetirements(
  client: SupabaseClient,
  overrides: Partial<Services> = {},
): Promise<CaptureRetirementResult> {
  const services: Services = {
    config: overrides.config ?? getR2Config(),
    deleteObject: deleteR2ObjectIfPresent,
    headObject: headR2Object,
    now: Date.now,
    ...overrides,
  };
  const token = crypto.randomUUID();
  const deadline = services.now() + 40_000;
  const { data, error } = await client.rpc("claim_capture_object_retirements", {
    p_token: token,
    p_limit: 25,
  });
  if (error) throw new Error("Capture retirement claim unavailable.");
  const batch = claims(data);
  const backend = await captureObjectBackendDigest(services.config);
  let observedAbsent = 0;
  for (const row of batch) {
    if (services.now() >= deadline) break;
    let absent = false;
    let errorCode: "object_io_failed" | "backend_unavailable" | null =
      "backend_unavailable";
    if (row.backend_sha256 === backend) {
      errorCode = "object_io_failed";
      try {
        await services.deleteObject(row.object_key, services.config);
        const response = await services.headObject(
          row.object_key,
          services.config,
        );
        try {
          absent = response.status === 404;
        } finally {
          await response.body?.cancel().catch(() => undefined);
        }
        if (absent) errorCode = null;
      } catch {
        /* Preserve exact obligation; never log a private object key. */
      }
    }
    try {
      const reply = await client.rpc("observe_capture_object_retirement", {
        p_backend: row.backend_sha256,
        p_key: row.object_key,
        p_token: token,
        p_absent: absent,
        p_error: errorCode,
      });
      if (!reply.error && reply.data === true && absent) observedAbsent++;
    } catch { /* Lost acknowledgement is retried after the saved lease. */ }
  }
  return {
    claimed: batch.length,
    observedAbsent,
    deferred: batch.length - observedAbsent,
    unresolved: batch.length,
  };
}
