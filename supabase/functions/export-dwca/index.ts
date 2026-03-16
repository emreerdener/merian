import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import JSZip from "https://esm.sh/jszip@3.10.1";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";
import * as jose from "https://deno.land/x/jose@v5.2.2/index.ts";
import { encodeHex } from "https://deno.land/std@0.224.0/encoding/hex.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseKey);

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { includePreciseCoordinates = false, exportScope = "user" } = await req.json();

    const authHeader = req.headers.get("Authorization")?.replace("Bearer ", "");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized: Missing token" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    // Phase 3: Network Round-Trip Latency - Validate JWT signature locally bypassing Auth round-trip
    let userId: string;
    try {
      const jwtSecret = Deno.env.get("SUPABASE_JWT_SECRET")!;
      const secretKey = new TextEncoder().encode(jwtSecret);
      const { payload } = await jose.jwtVerify(authHeader, secretKey);
      if (!payload.sub) throw new Error("No subject in JWT");
      userId = payload.sub;
    } catch (_e) {
      return new Response(JSON.stringify({ error: "Unauthorized: Invalid token signature" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 401,
      });
    }

    // 1. Query verified academic captures
    let query = supabase
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
      .neq("ecology_type", "domesticated");

    if (exportScope === "global") {
      query = query.eq("geoprivacy", "open");
    } else {
      query = query.eq("user_id", userId);
    }

    const { data: scans, error } = await query.limit(5000);
    if (error) {
      throw new Error(`Failed to fetch academic records: ${error.message}`);
    }

    // Phase 3: Cryptographic grouping without leaking Supabase identites.
    const secretHashSalt = Deno.env.get("SUPABASE_JWT_SECRET") || "salt";
    
    // 2. Build occurrence.csv
    const occurrenceHeader = "coreid,basisOfRecord,recordedBy,eventDate,scientificName,kingdom,phylum,class,order,family,genus,decimalLatitude,decimalLongitude,coordinateUncertaintyInMeters\n";
    const occurrenceRows: string[] = [];
    const BATCH_SIZE = 250;

    for (let i = 0; i < scans.length; i += BATCH_SIZE) {
      const batch = scans.slice(i, i + BATCH_SIZE);
      // deno-lint-ignore no-explicit-any
      const batchResults = await Promise.all(batch.map(async (scan: any) => {
        const species = scan.species_dictionary || {};
        const date = scan.timestamp ? new Date(scan.timestamp).toISOString() : "";
        
        const isTombstoned = scan.user_id === "00000000-0000-0000-0000-000000000000";
        let recordedBy = "Merian Citizen Scientist";
        
        if (!isTombstoned) {
            if (exportScope === "global") {
               // Hash to maintain contributor isolation anonymously
               const data = new TextEncoder().encode(scan.user_id + secretHashSalt);
               const hashBuffer = await crypto.subtle.digest("SHA-256", data);
               recordedBy = `merian_user_${encodeHex(new Uint8Array(hashBuffer)).substring(0, 16)}`;
            } else {
               recordedBy = scan.user_id;
            }
        }

        const isProtected = species.iucn_red_list_status === "vulnerable" || 
                            species.iucn_red_list_status === "endangered" || 
                            species.iucn_red_list_status === "critically_endangered" || 
                            species.iucn_red_list_status === "near_threatened";

        const canAccessPrecise = includePreciseCoordinates && (scan.user_id === userId);

        let lat = canAccessPrecise && !isProtected ? scan.gps_lat_exact : scan.gps_lat_public;
        let lon = canAccessPrecise && !isProtected ? scan.gps_long_exact : scan.gps_long_public;
        const uncertainty = canAccessPrecise && !isProtected ? scan.coordinate_uncertainty_in_meters || "" : "50000";

        if (isProtected && lat !== null && lon !== null) {
          lat = Math.round(lat * 10) / 10;
          lon = Math.round(lon * 10) / 10;
        }

        if (lat === null || lat === undefined) lat = "";
        if (lon === null || lon === undefined) lon = "";

        return `${scan.id},HumanObservation,${recordedBy},${date},${species.scientific_name || ""},${species.kingdom || ""},${species.phylum || ""},${species.class || ""},${species.order || ""},${species.family || ""},${species.genus || ""},${lat},${lon},${uncertainty}`;
      }));
      
      occurrenceRows.push(...batchResults);
    }
    
    const occurrenceCsv = occurrenceHeader + occurrenceRows.join("\n");

    // 3. Build multimedia.csv 
    const multimediaHeader = "coreid,identifier,format\n";
    // deno-lint-ignore no-explicit-any
    const multimediaRows = scans.flatMap((scan: any) => {
      const urls = scan.image_storage_urls || [];
      if (urls.length === 0) return []; 
      return urls.map((url: string) => `${scan.id},${url},image/jpeg`);
    });
    const multimediaCsv = multimediaHeader + multimediaRows.join("\n");

    // 4. Build meta.xml
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
  </core>
  <extension encoding="UTF-8" linesTerminatedBy="\\n" fieldsTerminatedBy="," fieldsEnclosedBy="" ignoreHeaderLines="1" rowType="http://rs.gbif.org/terms/1.0/Multimedia">
    <files><location>multimedia.csv</location></files>
    <coreid index="0" />
    <field index="1" term="http://purl.org/dc/terms/identifier" />
    <field index="2" term="http://purl.org/dc/terms/format" />
  </extension>
</archive>`;

    // 5. Zip it up (Phase 2: Use streaming internal representation to bypass 256MB V8 limit)
    const zip = new JSZip();
    zip.file("occurrence.csv", occurrenceCsv);
    zip.file("multimedia.csv", multimediaCsv);
    zip.file("meta.xml", metaXml);

    const zipStream = new ReadableStream({
      start(controller) {
        zip.generateInternalStream({ type: "uint8array" })
          .on('data', (data: Uint8Array) => controller.enqueue(data))
          .on('error', (err: Error) => controller.error(err))
          .on('end', () => controller.close());
      }
    });

    // 6. Upload to R2 and Generate Download URL
    const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID")!;
    const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME")!;
    const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID")!;
    const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY")!;

    const aws = new AwsClient({
      accessKeyId: R2_ACCESS_KEY_ID,
      secretAccessKey: R2_SECRET_ACCESS_KEY,
      service: "s3",
      region: "auto",
    });

    const timestamp = Date.now();
    const endpoint = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
    const exportKey = `exports/${userId}/LifeList_DwC_Archive_${timestamp}.zip`;
    const urlString = `${endpoint}/${R2_BUCKET_NAME}/${exportKey}`;

    // Sign securely with UNSIGNED-PAYLOAD since body length is streaming
    const putUrl = new URL(urlString);
    const signedPut = await aws.sign(putUrl.toString(), {
      method: "PUT",
      headers: {
        "x-amz-content-sha256": "UNSIGNED-PAYLOAD"
      }
    });
    
    // Inject streaming ReadableStream into generated aws4fetch standard signed Request
    const putRes = await fetch(signedPut.url, {
      method: "PUT",
      headers: signedPut.headers,
      body: zipStream,
      // @ts-ignore: Required configuration to enable modern standard Duplex Request streaming over Deno edge
      duplex: 'half'
    });

    if (!putRes.ok) {
      throw new Error(`Failed to upload streaming archive to R2: ${putRes.statusText}`);
    }

    const getUrl = new URL(urlString);
    getUrl.searchParams.set("X-Amz-Expires", "86400");
    const signedGet = await aws.sign(getUrl.toString(), {
      method: "GET",
      aws: { signQuery: true },
    });

    return new Response(JSON.stringify({ downloadUrl: signedGet.url }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
