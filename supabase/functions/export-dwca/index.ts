import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.31.0";
import JSZip from "https://esm.sh/jszip@3.10.1";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.17";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { userId, includePreciseCoordinates = false } = await req.json();

    if (!userId) {
      throw new Error("Missing userId in request body.");
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // 1. Query verified academic captures
    const { data: scans, error } = await supabase
      .from("scans")
      .select(
        `
        id,
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
          genus
        )
      `,
      )
      .eq("user_id", userId)
      .eq("is_live_capture", true)
      .neq("ecology_type", "domesticated");

    if (error) {
      throw new Error(`Failed to fetch academic records: ${error.message}`);
    }

    // 2. Build occurrence.csv
    const occurrenceHeader =
      "coreid,basisOfRecord,eventDate,scientificName,kingdom,phylum,class,order,family,genus,decimalLatitude,decimalLongitude,coordinateUncertaintyInMeters\n";
    const occurrenceRows = scans.map((scan: any) => {
      const species = scan.species_dictionary || {};
      const date = scan.timestamp ? new Date(scan.timestamp).toISOString() : "";

      let lat = includePreciseCoordinates
        ? scan.gps_lat_exact
        : scan.gps_lat_public;
      let lon = includePreciseCoordinates
        ? scan.gps_long_exact
        : scan.gps_long_public;
      let uncertainty = includePreciseCoordinates
        ? scan.coordinate_uncertainty_in_meters || ""
        : "5000";

      if (lat === null || lat === undefined) lat = "";
      if (lon === null || lon === undefined) lon = "";

      return `${scan.id},HumanObservation,${date},${species.scientific_name || ""},${species.kingdom || ""},${species.phylum || ""},${species.class || ""},${species.order || ""},${species.family || ""},${species.genus || ""},${lat},${lon},${uncertainty}`;
    });
    const occurrenceCsv = occurrenceHeader + occurrenceRows.join("\n");

    // 3. Build multimedia.csv
    const multimediaHeader = "coreid,identifier,format\n";
    const multimediaRows = scans.flatMap((scan: any) => {
      const urls = scan.image_storage_urls || [];
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
    <field index="2" term="http://rs.tdwg.org/dwc/terms/eventDate" />
    <field index="3" term="http://rs.tdwg.org/dwc/terms/scientificName" />
    <field index="4" term="http://rs.tdwg.org/dwc/terms/kingdom" />
    <field index="5" term="http://rs.tdwg.org/dwc/terms/phylum" />
    <field index="6" term="http://rs.tdwg.org/dwc/terms/class" />
    <field index="7" term="http://rs.tdwg.org/dwc/terms/order" />
    <field index="8" term="http://rs.tdwg.org/dwc/terms/family" />
    <field index="9" term="http://rs.tdwg.org/dwc/terms/genus" />
    <field index="10" term="http://rs.tdwg.org/dwc/terms/decimalLatitude" />
    <field index="11" term="http://rs.tdwg.org/dwc/terms/decimalLongitude" />
    <field index="12" term="http://rs.tdwg.org/dwc/terms/coordinateUncertaintyInMeters" />
  </core>
  <extension encoding="UTF-8" linesTerminatedBy="\\n" fieldsTerminatedBy="," fieldsEnclosedBy="" ignoreHeaderLines="1" rowType="http://rs.gbif.org/terms/1.0/Multimedia">
    <files><location>multimedia.csv</location></files>
    <coreid index="0" />
    <field index="1" term="http://purl.org/dc/terms/identifier" />
    <field index="2" term="http://purl.org/dc/terms/format" />
  </extension>
</archive>`;

    // 5. Zip it up
    const zip = new JSZip();
    zip.file("occurrence.csv", occurrenceCsv);
    zip.file("multimedia.csv", multimediaCsv);
    zip.file("meta.xml", metaXml);
    const zipBuffer = await zip.generateAsync({ type: "uint8array" });

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

    // PUT the archive
    const putUrl = new URL(urlString);
    const signedPut = await aws.sign(putUrl, {
      method: "PUT",
      body: zipBuffer,
    });
    const putRes = await fetch(signedPut);
    if (!putRes.ok) {
      throw new Error(`Failed to upload archive to R2: ${putRes.statusText}`);
    }

    // Generate GET URL expiring in 86400 seconds (24 hours)
    const getUrl = new URL(urlString);
    getUrl.searchParams.set("X-Amz-Expires", "86400");
    const signedGet = await aws.sign(getUrl, {
      method: "GET",
      aws: { signQuery: true },
    });

    return new Response(JSON.stringify({ downloadUrl: signedGet.url }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
