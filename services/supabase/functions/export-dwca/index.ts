import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import { corsHeaders } from "../_shared/http.ts";
import {
  fetchAndFormatScans,
  fetchUserEmail,
  updateExportJobStatus,
} from "./db.ts";
import { zipAndUploadToR2 } from "./storage.ts";
import { sendExportEmail } from "./mail.ts";

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 1. Authenticate the Webhook via Service Role Key
  const authHeader = req.headers.get("Authorization");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!serviceKey || authHeader !== `Bearer ${serviceKey}`) {
    return jsonResponse({ error: "Unauthorized webhook caller" }, 401);
  }

  let currentJobId: string | undefined = undefined;

  try {
    const payload = await req.json();
    const { job_id, user_id, export_scope, include_precise_coordinates } =
      payload;
    currentJobId = job_id;

    if (!job_id || !user_id) {
      return jsonResponse({ error: "Missing job payload" }, 400);
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceKey,
    );

    // 2. Fetch User Email for Delivery
    const userEmail = await fetchUserEmail(user_id, supabaseAdmin);

    // 3. Mark job as processing
    await updateExportJobStatus(job_id, "processing", supabaseAdmin);

    // 4. Query verified academic captures & Format DwC-A strings
    const secretHashSalt = Deno.env.get("SUPABASE_JWT_SECRET") || "salt";
    const { occurrenceCsv, multimediaCsv, metaXml } = await fetchAndFormatScans(
      user_id,
      export_scope,
      include_precise_coordinates,
      supabaseAdmin,
      secretHashSalt,
    );

    // 5. Zip streams and Upload to R2
    const signedUrl = await zipAndUploadToR2(
      occurrenceCsv,
      multimediaCsv,
      metaXml,
      user_id,
    );

    // 6. Send Email via Resend
    await sendExportEmail(userEmail, signedUrl);

    // 7. Update DB Completed Status
    await updateExportJobStatus(
      job_id,
      "completed",
      supabaseAdmin,
      undefined,
      signedUrl,
    );

    return jsonResponse({ success: true }, 200);
  } catch (error: unknown) {
    const err = error as Error;
    console.error("Export Webhook Error:", err);
    try {
      if (currentJobId) {
        const supabaseAdmin = createClient(
          Deno.env.get("SUPABASE_URL") ?? "",
          serviceKey ?? "",
        );
        await updateExportJobStatus(
          currentJobId,
          "failed",
          supabaseAdmin,
          err.message,
        );
      }
    } catch (_) {
      // no-op to avoid crashing during error fallback execution
    }

    return jsonResponse({ error: err.message }, 500);
  }
});
