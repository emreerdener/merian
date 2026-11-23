/** Capture V9 sealed-result recovery only. Absence is held, never a permit. */
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  exactObject,
  invalidHistory,
} from "../_shared/analysisHistory/contract.ts";
import {
  initialCapturePlanValue,
  parseInitialEvidenceCapturePlan,
} from "../_shared/analysisHistory/initialEvidenceCapturePlan.ts";
import { recoverPrivateCaptureCompletion } from "../_shared/analysisHistory/privateCaptureCompletion.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialDeadline,
  readInitialStream,
} from "../_shared/initialAnalysis/transport.ts";

export const captureCompletionRequestBytes = 1_048_576;
export const captureCompletionResponseBytes = 1_052_672;

export function decodeCaptureCompletion(body: unknown, owner: string) {
  const outer = exactObject(body, ["initial_recovery"]);
  const value = exactObject(outer.initial_recovery, [
    "version",
    "phase",
    "capture_plan",
  ]);
  if (value.version !== 1 || value.phase !== "capture-completion") {
    return invalidHistory();
  }
  return parseInitialEvidenceCapturePlan(owner, value.capture_plan);
}

/** No admission, media preparation, funding mutation, finalization or provider
 * dependency. The existing finalize-only worker owns accepted unsealed results.
 * This deadline bounds waiting after authentication, not database cancellation. */
export async function readCaptureCompletionHttp(
  request: Request,
  authenticatedOwnerID: string,
  client: SupabaseClient,
): Promise<Response> {
  const response = (body: string, status: number) =>
    new Response(body, {
      status,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  const refused = () =>
    response('{"error":"capture_completion_unavailable"}', 503);
  if (
    request.method !== "POST" ||
    request.headers.get("x-merian-initial-recovery") !==
      "capture-completion-v1" ||
    request.headers.get("content-type")?.split(";", 1)[0].trim()
        .toLowerCase() !== "application/json" ||
    request.headers.has("content-encoding")
  ) {
    cancelInitialStream(request.body);
    return refused();
  }
  const declared = request.headers.get("content-length");
  const length = declared === null ? null : Number(declared);
  if (
    declared !== null && (!/^(0|[1-9][0-9]*)$/.test(declared) ||
      !Number.isSafeInteger(length) || length! > captureCompletionRequestBytes)
  ) {
    cancelInitialStream(request.body);
    return refused();
  }
  try {
    return await initialDeadline(request.signal, 5000, async (signal) => {
      const bytes = await readInitialStream(
        request.body,
        captureCompletionRequestBytes,
        signal,
      );
      checkInitialDeadline(signal);
      if (length !== null && bytes.byteLength !== length) {
        return invalidHistory();
      }
      const plan = decodeCaptureCompletion(
        JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
        authenticatedOwnerID,
      );
      const completion = await recoverPrivateCaptureCompletion(
        client,
        authenticatedOwnerID,
        initialCapturePlanValue(plan),
        signal,
      );
      checkInitialDeadline(signal);
      const body = JSON.stringify({
        version: 1,
        phase: "capture-completion",
        owner_id: authenticatedOwnerID,
        scan_id: plan.scanID,
        generation: plan.generation,
        status: completion === null ? "held" : "completed",
        completion,
      });
      if (
        new TextEncoder().encode(body).byteLength >
          captureCompletionResponseBytes
      ) return invalidHistory();
      checkInitialDeadline(signal);
      return response(body, 200);
    });
  } catch {
    cancelInitialStream(request.body);
    return refused();
  }
}
