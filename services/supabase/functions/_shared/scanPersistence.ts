import type { SupabaseClient } from "@supabase/supabase-js";

interface PersistenceErrorLike {
  message: string;
}

export interface PersistOwnedScanRowOptions {
  scanId: string;
  userId: string;
  operationName: string;
  supabaseAdmin: SupabaseClient;
  write: () => Promise<{ error: PersistenceErrorLike | null }>;
  /**
   * Delay before each verification attempt. Tests pass zeroes; production
   * uses short bounded polls so a request whose response was lost while its
   * transaction finished can become observable before cleanup is considered.
   */
  verificationDelaysMs?: readonly number[];
}

type WriteOutcome = "reported_success" | "reported_rejected" | "unknown";

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
 * A returned PostgREST error plus a definitive missing-owner read is a known
 * rejection and can use normal rollback. A thrown/lost write response, a
 * reported-success response with no owner row, or an unreadable verification
 * remains ambiguous and is surfaced through the typed error above.
 */
export async function persistOwnedScanRow(
  options: PersistOwnedScanRowOptions,
): Promise<void> {
  let writeOutcome: WriteOutcome = "reported_success";
  let writeFailure: Error | null = null;

  try {
    const { error } = await options.write();
    if (error) {
      writeOutcome = "reported_rejected";
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

      // A database error response proves this statement was rejected. Once a
      // same-primary read also proves there is no idempotent owner row, normal
      // rollback is safe and additional polls cannot change that conclusion.
      if (writeOutcome === "reported_rejected") break;
    } catch (error) {
      verificationFailure = asError(
        error,
        `${options.operationName} verification response was lost`,
      );
    }
  }

  if (
    writeOutcome === "reported_rejected" &&
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
