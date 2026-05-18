import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  buildIdentifyMultimodalPayload,
  jobStatusForIdentifyResponse,
  queuedJobRow,
  validateShareImportRequest,
} from "./shareImport.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const validated = validateShareImportRequest(body, user.id);
    if (validated.error || !validated.value) {
      return jsonResponse(
        { error: validated.error?.message ?? "Invalid share import request" },
        validated.error?.status ?? 400,
      );
    }

    const request = validated.value;
    const insertResult = await supabaseAdmin
      .from("scan_import_jobs")
      .insert(queuedJobRow(request, user.id));

    if (insertResult.error) {
      logStructuredError("share_import/job_insert_failed", {
        user_id: user.id,
        scan_id: request.scanId,
        error: insertResult.error.message,
      });
      return jsonResponse({ error: "Unable to queue shared image." }, 500);
    }

    const authorization = req.headers.get("Authorization");
    const apikey = req.headers.get("apikey") ??
      Deno.env.get("SUPABASE_ANON_KEY") ??
      "";
    const identifyURL = `${Deno.env.get("SUPABASE_URL")}/functions/v1/identify-multimodal`;
    const identifyPayload = buildIdentifyMultimodalPayload(request, user.id);

    runBackground((async () => {
      await supabaseAdmin
        .from("scan_import_jobs")
        .update({ status: "processing", updated_at: new Date().toISOString() })
        .eq("scan_id", request.scanId)
        .eq("user_id", user.id);

      try {
        const response = await fetch(identifyURL, {
          method: "POST",
          headers: {
            "Authorization": authorization ?? "",
            "apikey": apikey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(identifyPayload),
        });
        const responseText = await response.text();
        await supabaseAdmin
          .from("scan_import_jobs")
          .update(jobStatusForIdentifyResponse(response.status, responseText))
          .eq("scan_id", request.scanId)
          .eq("user_id", user.id);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        logStructuredError("share_import/identify_dispatch_failed", {
          user_id: user.id,
          scan_id: request.scanId,
          error: message,
        });
        await supabaseAdmin
          .from("scan_import_jobs")
          .update({
            status: "failed",
            error_message: message.slice(0, 1_000),
            updated_at: new Date().toISOString(),
          })
          .eq("scan_id", request.scanId)
          .eq("user_id", user.id);
      }
    })());

    return jsonResponse({ success: true, scan_id: request.scanId }, 202);
  })
);
