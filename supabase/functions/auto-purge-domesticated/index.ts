import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { getR2Config, deleteR2Objects } from "../_shared/aws.ts";
import { timingSafeCompare } from "../_shared/security.ts";

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method Not Allowed" }), {
      status: 405, headers: { "Content-Type": "application/json" }
    });
  }

  const expectedAuth = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  const providedAuth = req.headers.get("Authorization") ?? "";

  if (!timingSafeCompare(providedAuth, expectedAuth)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401, headers: { "Content-Type": "application/json" }
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    // 1. Query free tier domesticated scans older than 90 days (limit 500 to prevent memory pressure)
    const ninetyDaysAgo = new Date();
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

    const { data: scans, error: fetchError } = await supabaseAdmin
      .from("scans")
      .select("id, image_storage_urls, users!inner(subscription_tier)")
      .eq("ecology_type", "domesticated")
      .eq("users.subscription_tier", "free")
      .lt("timestamp", ninetyDaysAgo.toISOString())
      .not("image_storage_urls", "eq", "{}")
      .limit(500);

    if (fetchError) {
      throw fetchError;
    }

    if (!scans || scans.length === 0) {
      return new Response(JSON.stringify({ message: "No expired domesticated scans to purge." }), {
        status: 200,
        headers: { "Content-Type": "application/json" }
      });
    }

    const r2Config = getR2Config();
    const idsToUpdate: string[] = [];

    // 2. Delete R2 images for each scan
    for (const scan of scans) {
      idsToUpdate.push(scan.id);
      const urls: string[] = scan.image_storage_urls || [];
      if (urls.length > 0) {
        await deleteR2Objects(urls, r2Config);
      }
    }

    // 3. Zero-out the image URLs in the database (preserve row offline data)
    if (idsToUpdate.length > 0) {
      const { error: updateError } = await supabaseAdmin
        .from("scans")
        .update({ image_storage_urls: [] })
        .in("id", idsToUpdate);

      if (updateError) {
        throw updateError;
      }
    }

    return new Response(JSON.stringify({ success: true, count: idsToUpdate.length }), {
      status: 200,
      headers: { "Content-Type": "application/json" }
    });

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
});
