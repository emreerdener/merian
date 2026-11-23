import type { SupabaseClient } from "@supabase/supabase-js";

interface PersistenceErrorLike {
  message: string;
  code?: string;
}

export interface ScanWriteResponse {
  error: PersistenceErrorLike | null;
  status?: number;
}

export interface PersistOwnedScanRowOptions {
  scanId: string;
  userId: string;
  operationName: string;
  supabaseAdmin: SupabaseClient;
  write: () => Promise<ScanWriteResponse>;
  /**
   * Delay before each verification attempt. Tests pass zeroes; production
   * uses short bounded polls so a request whose response was lost while its
   * transaction finished can become observable before cleanup is considered.
   */
  verificationDelaysMs?: readonly number[];
}

export type ScanWriteOutcome = "acknowledged" | "rejected" | "unknown";

// Only a recognized PostgreSQL rejection over a non-gateway HTTP response is
// positive evidence. SDK transport errors are returned values too (status 0).
const REJECTION_CODES = new Set([
  "22001",
  "22003",
  "22P02",
  "23502",
  "23503",
  "23505",
  "23514",
  "23P01",
  "42501",
  "42P01",
  "42703",
  "42804",
  "42883",
]);
export function classifyScanWrite(
  response: ScanWriteResponse,
): ScanWriteOutcome {
  if (
    response.status === undefined || response.status === 0 ||
    response.status === 408 || response.status === 429
  ) return "unknown";
  if (
    response.status >= 200 && response.status < 300 && response.error === null
  ) {
    return "acknowledged";
  }
  return response.status >= 400 && response.status < 500 &&
      response.error != null && REJECTION_CODES.has(response.error.code ?? "")
    ? "rejected"
    : "unknown";
}

const DEFAULT_VERIFICATION_DELAYS_MS = [0, 25, 75] as const;

/**
 * A scan write may have committed, but the service could not prove the exact
 * owner row because either the write response or all follow-up reads were
 * lost. Callers must treat this as retryable and must not release quota or
 * delete media that a committed row could reference.
 */
export class ScanPersistenceOutcomeUnknownError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ScanPersistenceOutcomeUnknownError";
  }
}

export function isScanPersistenceOutcomeUnknown(
  error: unknown,
): error is ScanPersistenceOutcomeUnknownError {
  return error instanceof ScanPersistenceOutcomeUnknownError;
}

function asError(value: unknown, fallback: string): Error {
  if (value instanceof Error) return value;
  if (
    value != null &&
    typeof value === "object" &&
    typeof (value as { message?: unknown }).message === "string"
  ) {
    return new Error((value as { message: string }).message);
  }
  return new Error(fallback);
}

function sleep(milliseconds: number): Promise<void> {
  if (milliseconds <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

/**
 * Execute an idempotent scan insert and settle it only through an exact
 * (scan_id, user_id) owner read.
 *
 * A recognized database rejection plus an exact missing-owner read is a known
 * rejection and can use normal rollback. A thrown/lost write response, a
 * reported-success response with no owner row, or an unreadable verification
 * remains ambiguous and is surfaced through the typed error above.
 */
export async function persistOwnedScanRow(
  options: PersistOwnedScanRowOptions,
): Promise<void> {
  let writeOutcome: ScanWriteOutcome = "unknown";
  let writeFailure: Error | null = null;

  try {
    const response = await options.write();
    writeOutcome = classifyScanWrite(response);
    const { error } = response;
    if (error) {
      writeFailure = new Error(
        `${options.operationName}: ${error.message}`,
      );
    }
  } catch (error) {
    writeOutcome = "unknown";
    writeFailure = asError(
      error,
      `${options.operationName}: database write response was lost`,
    );
  }

  const delays = options.verificationDelaysMs ??
    DEFAULT_VERIFICATION_DELAYS_MS;
  if (delays.length === 0) {
    throw new TypeError("At least one persistence verification is required.");
  }

  let sawDefinitiveMissingOwner = false;
  let verificationFailure: Error | null = null;

  for (const delayMs of delays) {
    await sleep(delayMs);
    try {
      const { data: persistedScan, error: readError } = await options
        .supabaseAdmin
        .from("scans")
        .select("id")
        .eq("id", options.scanId)
        .eq("user_id", options.userId)
        .maybeSingle();

      if (readError) {
        verificationFailure = new Error(
          `${options.operationName} verification: ${readError.message}`,
        );
        continue;
      }

      if (persistedScan) return;
      sawDefinitiveMissingOwner = true;

      // Only a recognized database rejection proves this statement failed. Once a
      // same-primary read also proves there is no idempotent owner row, normal
      // rollback is safe and additional polls cannot change that conclusion.
      if (writeOutcome === "rejected") break;
    } catch (error) {
      verificationFailure = asError(
        error,
        `${options.operationName} verification response was lost`,
      );
    }
  }

  if (
    writeOutcome === "rejected" &&
    sawDefinitiveMissingOwner &&
    writeFailure
  ) {
    throw writeFailure;
  }

  const reason = verificationFailure?.message ??
    writeFailure?.message ??
    "the exact owner row was not observable";
  throw new ScanPersistenceOutcomeUnknownError(
    `${options.operationName}: scan persistence outcome is unknown (${reason})`,
  );
}
