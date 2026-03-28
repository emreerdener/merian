import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import JSZip from "https://esm.sh/jszip@3.10.1";
import { encodeHex } from "https://deno.land/std@0.224.0/encoding/hex.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import { getR2Config } from "../_shared/aws.ts";
import { corsHeaders } from "../_shared/cors.ts";

function jsonResponse(payload: unknown, status: number = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 1. Authenticate the Webhook via Service Role Key
  const authHeader = req.headers.get("Authorization");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  
  if (!serviceKey || authHeader !== `Bearer ${serviceKey}`) {
    return jsonResponse({ error: "Unauthorized webhook caller" }, 401);
  }

  try {
    const payload = await req.json();
    const { job_id, user_id, export_scope, include_precise_coordinates } = payload;

    if (!job_id || !user_id) {
      return jsonResponse({ error: "Missing job payload" }, 400);
    }

    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceKey
    );

    // Fetch User Email for Delivery
    const { data: { user }, error: userError } = await supabaseAdmin.auth.admin.getUserById(user_id);
    if (userError || !user?.email) {
      throw new Error(`Could not find email to deliver export: ${userError?.message}`);
    }

    // Mark job as processing
    await supabaseAdmin.from("export_jobs").update({ status: "processing" }).eq("id", job_id);

    // 2. Query verified academic captures
    let query = supabaseAdmin
      .from("scans")
      .select(`
        id,
        user_id,
        timestamp,
        gps_lat_exact,
        gps_long_exact,
        gps_lat_public,
        gps_long_public,
        coordinate_uncertainty_in_meters,
        image_storage_urls,
        life_stage,
        reproductive_condition,
        individual_count,
        ecological_interactions,
        ai_confidence_score,
        species_dictionary (
          scientific_name,
          kingdom,
          phylum,
          class,
          "order",
          family,
          genus,
          iucn_red_list_status
        )
      `)
      .eq("is_live_capture", true)
      .neq("ecology_type", "domesticated")
      .order("id", { ascending: true });

    if (export_scope === "global") {
      query = query.eq("geoprivacy", "open");
    } else {
      query = query.eq("user_id", user_id);
    }

    const secretHashSalt = Deno.env.get("SUPABASE_JWT_SECRET") || "salt";
    const occurrenceRows = [
      "coreid,basisOfRecord,recordedBy,eventDate,scientificName,kingdom,phylum,class,order,family,genus,decimalLatitude,decimalLongitude,coordinateUncertaintyInMeters,lifeStage,reproductiveCondition,individualCount,associatedTaxa,identificationVerificationStatus"
    ];
    const multimediaRows = ["coreid,identifier,format"];

    let hasMore = true;
    let start = 0;
    const PAGE_SIZE = 1000;

    while (hasMore) {
      const { data, error } = await query.range(start, start + PAGE_SIZE - 1);
      if (error) throw new Error(`Failed to fetch records: ${error.message}`);
      if (!data || data.length === 0) {
        hasMore = false;
        break;
      }

      const batchResults = [];
      const SUB_BATCH_SIZE = 50;

      for (let i = 0; i < data.length; i += SUB_BATCH_SIZE) {
        const subBatch = data.slice(i, i + SUB_BATCH_SIZE);
        const subBatchResults = await Promise.all(
          subBatch.map(async (row: any) => {
            const scan = row;
            const species = scan.species_dictionary || {};
            const date = scan.timestamp ? new Date(scan.timestamp).toISOString() : "";
            const isTombstoned = scan.user_id === "00000000-0000-0000-0000-000000000000";
            let recordedBy = "Merian Citizen Scientist";

            if (!isTombstoned) {
              if (export_scope === "global") {
                const hashData = new TextEncoder().encode(scan.user_id + secretHashSalt);
                const hashBuffer = await crypto.subtle.digest("SHA-256", hashData);
                recordedBy = `merian_user_${encodeHex(new Uint8Array(hashBuffer)).substring(0, 16)}`;
              } else {
                recordedBy = scan.user_id;
              }
            }

            const isProtected = ["vulnerable", "endangered", "critically_endangered", "near_threatened"]
              .includes(species.iucn_red_list_status || "");
            const canAccessPrecise = include_precise_coordinates && (scan.user_id === user_id);

            let lat: number | string | undefined | null = canAccessPrecise && !isProtected ? scan.gps_lat_exact : scan.gps_lat_public;
            let lon: number | string | undefined | null = canAccessPrecise && !isProtected ? scan.gps_long_exact : scan.gps_long_public;
            const uncertainty = canAccessPrecise && !isProtected ? scan.coordinate_uncertainty_in_meters || "" : "50000";

            if (isProtected && typeof lat === "number" && typeof lon === "number") {
              lat = Math.round(lat * 10) / 10;
              lon = Math.round(lon * 10) / 10;
            }

            if (lat == null) lat = "";
            if (lon == null) lon = "";

            const lifeStage = scan.life_stage || "unknown";
            const reproductiveCondition = scan.reproductive_condition || "not_applicable";
            const individualCount = scan.individual_count != null ? scan.individual_count : "";
            const associatedTaxa = scan.ecological_interactions && scan.ecological_interactions.length > 0
              ? scan.ecological_interactions.join(" | ").replace(/,/g, ";").replace(/"/g, "")
              : "";
            const verificationStatus = scan.ai_confidence_score != null ? scan.ai_confidence_score.toFixed(2) : "";

            const occurrenceRow = `${scan.id},HumanObservation,${recordedBy},${date},${species.scientific_name || ""},${species.kingdom || ""},${species.phylum || ""},${species.class || ""},${species.order || ""},${species.family || ""},${species.genus || ""},${lat},${lon},${uncertainty},${lifeStage},${reproductiveCondition},${individualCount},"${associatedTaxa}",${verificationStatus}`;
            const urls = scan.image_storage_urls || [];
            const mRows = urls.map((url: string) => `${scan.id},${url},image/webp`);
            return { occurrenceRow, mRows };
          })
        );
        batchResults.push(...subBatchResults);
      }

      for (const res of batchResults) {
        occurrenceRows.push(res.occurrenceRow);
        if (res.mRows.length > 0) multimediaRows.push(res.mRows.join("\n"));
      }

      // @ts-ignore
      globalThis.gc?.();

      if (data.length < PAGE_SIZE || occurrenceRows.length >= 10000) {
        hasMore = false;
      } else {
        start += PAGE_SIZE;
      }
    }

    const metaXml = `<?xml version="1.0" encoding="UTF-8"?>
<archive xmlns="http://rs.tdwg.org/dwc/text/">
  <core encoding="UTF-8" linesTerminatedBy="\\n" fieldsTerminatedBy="," fieldsEnclosedBy="" ignoreHeaderLines="1" rowType="http://rs.tdwg.org/dwc/terms/Occurrence">
    <files><location>occurrence.csv</location></files>
    <id index="0" />
    <field index="1" term="http://rs.tdwg.org/dwc/terms/basisOfRecord" />
    <field index="2" term="http://rs.tdwg.org/dwc/terms/recordedBy" />
    <field index="3" term="http://rs.tdwg.org/dwc/terms/eventDate" />
    <field index="4" term="http://rs.tdwg.org/dwc/terms/scientificName" />
    <field index="5" term="http://rs.tdwg.org/dwc/terms/kingdom" />
    <field index="6" term="http://rs.tdwg.org/dwc/terms/phylum" />
    <field index="7" term="http://rs.tdwg.org/dwc/terms/class" />
    <field index="8" term="http://rs.tdwg.org/dwc/terms/order" />
    <field index="9" term="http://rs.tdwg.org/dwc/terms/family" />
    <field index="10" term="http://rs.tdwg.org/dwc/terms/genus" />
    <field index="11" term="http://rs.tdwg.org/dwc/terms/decimalLatitude" />
    <field index="12" term="http://rs.tdwg.org/dwc/terms/decimalLongitude" />
    <field index="13" term="http://rs.tdwg.org/dwc/terms/coordinateUncertaintyInMeters" />
    <field index="14" term="http://rs.tdwg.org/dwc/terms/lifeStage" />
    <field index="15" term="http://rs.tdwg.org/dwc/terms/reproductiveCondition" />
    <field index="16" term="http://rs.tdwg.org/dwc/terms/individualCount" />
    <field index="17" term="http://rs.tdwg.org/dwc/terms/associatedTaxa" />
    <field index="18" term="http://rs.tdwg.org/dwc/terms/identificationVerificationStatus" />
  </core>
  <extension encoding="UTF-8" linesTerminatedBy="\\n" fieldsTerminatedBy="," fieldsEnclosedBy="" ignoreHeaderLines="1" rowType="http://rs.gbif.org/terms/1.0/Multimedia">
    <files><location>multimedia.csv</location></files>
    <coreid index="0" />
    <field index="1" term="http://purl.org/dc/terms/identifier" />
    <field index="2" term="http://purl.org/dc/terms/format" />
  </extension>
</archive>`;

    const zip = new JSZip();
    zip.file("occurrence.csv", occurrenceRows.join("\n") + "\n");
    zip.file("multimedia.csv", multimediaRows.join("\n") + "\n");
    zip.file("meta.xml", metaXml);
    const zipStream = zip.generateInternalStream({ type: "uint8array", compression: "STORE" });

    const readableZipStream = new ReadableStream({
      start(controller) {
        zipStream.on("data", (data: Uint8Array) => controller.enqueue(data))
                 .on("end", () => controller.close())
                 .on("error", (err: Error) => controller.error(err));
        zipStream.resume();
      }
    });

    const { s3Client, bucketName, endpoint } = getR2Config();
    const timestamp = Date.now();
    const exportKey = `exports/${user_id}/Scans_DwC_Archive_${timestamp}.zip`;
    const urlString = `${endpoint}/${bucketName}/${exportKey}`;

    const putRes = await s3Client.fetch(urlString, {
      method: "PUT",
      headers: { "Content-Type": "application/zip" },
      body: readableZipStream
    });

    if (!putRes.ok) throw new Error(`Failed to upload to R2: ${putRes.statusText}`);

    const getUrl = new URL(urlString);
    getUrl.searchParams.set("X-Amz-Expires", "86400"); // 24 hours
    const signedGet = await s3Client.sign(getUrl.toString(), {
      method: "GET",
      aws: { signQuery: true },
    });
    
    const signedUrl = signedGet.url;

    // 4. Send Email via Resend
    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (resendKey) {
        const emailRes = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${resendKey}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                from: "Merian Data Exports <exports@merian.app>", // Update domain if needed
                to: [user.email],
                subject: "Your Merian Darwin Core Archive is Ready",
                html: `
                    <h2>Your Export is Ready</h2>
                    <p>Your Darwin Core Archive (DwC-A) containing your scans has finished processing.</p>
                    <p>This secure link will expire in 24 hours.</p>
                    <a href="${signedUrl}" style="display:inline-block;padding:12px 24px;background-color:#007AFF;color:white;text-decoration:none;border-radius:8px;">Download Archive</a>
                    <br><br>
                    <p>Thank you for contributing to Merian!</p>
                `
            })
        });
        
        if (!emailRes.ok) {
            const errBody = await emailRes.text();
            console.error("Failed to send Resend email:", errBody);
        }
    } else {
        console.warn("No RESEND_API_KEY found. Skipping email delivery.");
    }

    // 5. Update DB
    await supabaseAdmin
        .from("export_jobs")
        .update({ status: "completed", file_url: signedUrl, completed_at: new Date().toISOString() })
        .eq("id", job_id);

    return jsonResponse({ success: true }, 200);

  } catch (error: any) {
    console.error("Export Webhook Error:", error);
    try {
        const payload = await req.json();
        if (payload?.job_id) {
            const supabaseAdmin = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey);
            await supabaseAdmin.from("export_jobs").update({ 
                status: "failed", 
                error_message: error.message 
            }).eq("id", payload.job_id);
        }
    } catch (_) {}
    
    return jsonResponse({ error: error.message }, 500);
  }
});
