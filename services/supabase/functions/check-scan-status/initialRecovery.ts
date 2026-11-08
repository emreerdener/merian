/** Prepared branch only: index.ts rejects this request until serving controls
 * are installed. The caller must authenticate and bound raw bytes before JSON
 * parsing. This owner has no legacy repair, execution or retry dependency. */
import {
  decodeInitialStatusRecoveryRequest,
  initialStatusAdmissionRequestBytes,
  initialStatusCompletionRequestBytes,
} from "../_shared/initialAnalysis/completionStatusRequest.ts";
import { encodeInitialCompletionStatus } from "../_shared/initialAnalysis/completionStatusResponse.ts";
import {
  createInitialCompletionAcquisition,
  createInitialSavedAdmissionAcquisition,
} from "../_shared/initialAnalysis/resultStore.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialDeadline,
  readInitialStream,
} from "../_shared/initialAnalysis/transport.ts";

export async function readInitialRecovery(
  body: unknown,
  authenticatedOwnerID: string,
  signal: AbortSignal,
  options: { origin: string; serverApiKey: string; fetcher?: typeof fetch },
  expectedPhase?: "admission" | "completion",
): Promise<Uint8Array> {
  const transport = {
    origin: options.origin,
    serverApiKey: options.serverApiKey,
    fetcher: options.fetcher,
  };
  return await initialDeadline(signal, 5000, async (phase) => {
    checkInitialDeadline(phase);
    // The decoder snapshots all request facts synchronously before digest awaits.
    const request = await decodeInitialStatusRecoveryRequest(
      body,
      authenticatedOwnerID,
    );
    checkInitialDeadline(phase);
    if (expectedPhase !== undefined && request.phase !== expectedPhase) {
      throw new Error("initial_status_recovery_request_invalid");
    }
    if (request.phase === "admission") {
      const reader = await createInitialSavedAdmissionAcquisition({
        ...transport,
        original: request.original,
        authenticatedOwnerID,
      });
      checkInitialDeadline(phase);
      const value = await reader.read(phase);
      checkInitialDeadline(phase);
      return new TextEncoder().encode(value.canonical);
    }
    const reader = createInitialCompletionAcquisition({
      ...transport,
      admission: request.original,
    });
    const value = await reader.read(phase);
    checkInitialDeadline(phase);
    const bytes = encodeInitialCompletionStatus(request.original, value);
    checkInitialDeadline(phase);
    return bytes;
  });
}

/** Prepared HTTP entry point, deliberately not installed by index.ts. The
 * authenticated owner comes from the existing handler, never the body/header.
 * The phase header selects only a fixed byte ceiling, not read authority. */
export async function readInitialRecoveryHttp(
  request: Request,
  authenticatedOwnerID: string,
  options: { origin: string; serverApiKey: string; fetcher?: typeof fetch },
): Promise<Response> {
  const transport = { ...options };
  const response = (bytes: BodyInit, status: number) =>
    new Response(bytes, {
      status,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  const invalid = () =>
    response('{"error":"initial_recovery_unavailable"}', 503);
  const header = request.headers.get("x-merian-initial-recovery");
  const phase = header === "admission-v1"
    ? "admission"
    : header === "completion-v1"
    ? "completion"
    : null;
  if (
    request.method !== "POST" || phase === null ||
    request.headers.get("content-type")?.split(";", 1)[0].trim()
        .toLowerCase() !==
      "application/json" ||
    request.headers.has("content-encoding")
  ) {
    cancelInitialStream(request.body);
    return invalid();
  }
  const limit = phase === "admission"
    ? initialStatusAdmissionRequestBytes
    : initialStatusCompletionRequestBytes;
  const declared = request.headers.get("content-length");
  const length = declared === null ? null : Number(declared);
  if (
    declared !== null && (
      !/^(0|[1-9][0-9]*)$/.test(declared) ||
      !Number.isSafeInteger(length) || length! > limit
    )
  ) {
    cancelInitialStream(request.body);
    return invalid();
  }
  try {
    return await initialDeadline(request.signal, 5000, async (signal) => {
      checkInitialDeadline(signal);
      const bytes = await readInitialStream(request.body, limit, signal);
      checkInitialDeadline(signal);
      if (length !== null && bytes.byteLength !== length) {
        throw new Error("length");
      }
      // Bound actual bytes before decoding; malformed UTF-8 never normalizes
      // into different original candidate content.
      const body: unknown = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      );
      checkInitialDeadline(signal);
      const result = await readInitialRecovery(
        body,
        authenticatedOwnerID,
        signal,
        transport,
        phase,
      );
      checkInitialDeadline(signal);
      return response(new Uint8Array(result), 200);
    });
  } catch {
    cancelInitialStream(request.body);
    return invalid();
  }
}
