import { jsonResponse, publicErrorResponse } from "../_shared/http.ts";
import { historyUUID } from "../_shared/analysisHistory/contract.ts";
import { checkInitialDeadline } from "../_shared/initialAnalysis/transport.ts";
import {
  type AllocationRequest,
  parseAllocationRequest,
  projectAllocationReceipt,
} from "./contract.ts";

export async function initialPhotoAllocation(
  req: Request,
  body: unknown,
  owner: string,
  deps: {
    call(
      owner: string,
      request: AllocationRequest,
      signal: AbortSignal,
    ): Promise<unknown>;
  },
): Promise<Response> {
  let request: AllocationRequest;
  try {
    request = parseAllocationRequest(body);
  } catch {
    return publicErrorResponse(
      req,
      400,
      "initial_photo_allocation_invalid",
      "Invalid photo allocation request.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
  try {
    const authenticatedOwner = historyUUID(owner);
    checkInitialDeadline(req.signal);
    const privateReply = await deps.call(
      authenticatedOwner,
      request,
      req.signal,
    );
    checkInitialDeadline(req.signal);
    const receipt = await projectAllocationReceipt(request, privateReply);
    checkInitialDeadline(req.signal);
    return jsonResponse(receipt, 200, { "Cache-Control": "private, no-store" });
  } catch {
    // Never return SQL/provider diagnostics or log private user content.
    return publicErrorResponse(
      req,
      503,
      "initial_photo_allocation_unavailable",
      "Photo allocation is unavailable. Recover the original operation.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
}
