import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import JSZip from "https://esm.sh/jszip@3.10.1";
import { encodeHex } from "https://deno.land/std@0.224.0/encoding/hex.ts";

import { getR2Config } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const { includePreciseCoordinates = false, exportScope = "user" } = await req.json();
    const userId = user.id;

    // 1. Query verified academic captures
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

    if (exportScope === "global") {
      query = query.eq("geoprivacy", "open");
    } else {
      query = query.eq("user_id", userId);
    }

    // Hash user IDs for global exports to avoid leaking Supabase identities
    const secretHashSalt = Deno.env.get("SUPABASE_JWT_SECRET") || "salt";

    const occurrenceRows = [
      "coreid,basisOfRecord,recordedBy,eventDate,scientificName,kingdom,phylum,class,order,family,genus,decimalLatitude,decimalLongitude,coordinateUncertaintyInMeters"
    ];

    const multimediaRows = ["coreid,identifier,format"];

    let hasMore = true;
    let start = 0;
    const PAGE_SIZE = 1000;

    while (hasMore) {
      const { data, error } = await query.range(start, start + PAGE_SIZE - 1);

      if (error) {
        throw new Error(`Failed to fetch records: ${error.message}`);
      }

      if (!data || data.length === 0) {
        hasMore = false;
        break;
      }

      // Process in sub-batches to avoid V8 starvation on large exports
      const batchResults = [];
      const SUB_BATCH_SIZE = 50;

      interface SpeciesDictionary {
        scientific_name?: string;
        kingdom?: string;
        phylum?: string;
        class?: string;
        order?: string;
        family?: string;
        genus?: string;
        iucn_red_list_status?: string;
      }

      interface ScanRow {
        id: string;
        user_id: string;
        timestamp?: string;
        gps_lat_exact?: number;
        gps_long_exact?: number;
        gps_lat_public?: number;
        gps_long_public?: number;
        coordinate_uncertainty_in_meters?: number;
        image_storage_urls?: string[];
        species_dictionary?: SpeciesDictionary;
      }

      for (let i = 0; i < data.length; i += SUB_BATCH_SIZE) {
        const subBatch = data.slice(i, i + SUB_BATCH_SIZE);
        const subBatchResults = await Promise.all(
          subBatch.map(async (row) => {
            const scan = row as ScanRow;
            const species = scan.species_dictionary || {};
            const date = scan.timestamp ? new Date(scan.timestamp).toISOString() : "";

            const isTombstoned = scan.user_id === "00000000-0000-0000-0000-000000000000";
            let recordedBy = "Merian Citizen Scientist";

            if (!isTombstoned) {
              if (exportScope === "global") {
                const hashData = new TextEncoder().encode(scan.user_id + secretHashSalt);
                const hashBuffer = await crypto.subtle.digest("SHA-256", hashData);
                recordedBy = `merian_user_${encodeHex(new Uint8Array(hashBuffer)).substring(0, 16)}`;
              } else {
                recordedBy = scan.user_id;
              }
            }

            const isProtected = ["vulnerable", "endangered", "critically_endangered", "near_threatened"]
              .includes(species.iucn_red_list_status || "");

            const canAccessPrecise = includePreciseCoordinates && (scan.user_id === userId);

            let lat: number | string | undefined | null = canAccessPrecise && !isProtected ? scan.gps_lat_exact : scan.gps_lat_public;
            let lon: number | string | undefined | null = canAccessPrecise && !isProtected ? scan.gps_long_exact : scan.gps_long_public;
            const uncertainty = canAccessPrecise && !isProtected ? scan.coordinate_uncertainty_in_meters || "" : "50000";

            // Round to ~11km resolution for protected species
            if (isProtected && typeof lat === "number" && typeof lon === "number") {
              lat = Math.round(lat * 10) / 10;
              lon = Math.round(lon * 10) / 10;
            }

            if (lat === null || lat === undefined) lat = "";
            if (lon === null || lon === undefined) lon = "";

            const occurrenceRow = `${scan.id},HumanObservation,${recordedBy},${date},${species.scientific_name || ""},${species.kingdom || ""},${species.phylum || ""},${species.class || ""},${species.order || ""},${species.family || ""},${species.genus || ""},${lat},${lon},${uncertainty}`;

            const urls = scan.image_storage_urls || [];
            const mRows = urls.map((url: string) => `${scan.id},${url},image/jpeg`);

            return { occurrenceRow, mRows };
          })
        );
        batchResults.push(...subBatchResults);
      }

      for (const res of batchResults) {
        occurrenceRows.push(res.occurrenceRow);
        if (res.mRows.length > 0) {
          multimediaRows.push(res.mRows.join("\n"));
        }
      }

      // Hint the GC to reclaim page data before loading the next page
      // @ts-ignore: Deno globalThis supports gc when run with --v8-flags=--expose-gc
      globalThis.gc?.();

      if (data.length < PAGE_SIZE || occurrenceRows.length >= 10000) {
        hasMore = false;
      } else {
        start += PAGE_SIZE;
      }
    }

    // 2. Build meta.xml
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

    // 3. Zip and stream directly to R2 to stay under the 256MB V8 heap limit
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

    // 4. Upload to R2 and generate a signed download URL
    const { s3Client, bucketName, endpoint } = getR2Config();

    const timestamp = Date.now();
    const exportKey = `exports/${userId}/Scans_DwC_Archive_${timestamp}.zip`;
    const urlString = `${endpoint}/${bucketName}/${exportKey}`;

    const putRes = await s3Client.fetch(urlString, {
      method: "PUT",
      headers: { "Content-Type": "application/zip" },
      body: readableZipStream
    });

    if (!putRes.ok) {
      throw new Error(`Failed to upload archive to R2: ${putRes.statusText}`);
    }

    const getUrl = new URL(urlString);
    getUrl.searchParams.set("X-Amz-Expires", "86400");

    const signedGet = await s3Client.sign(getUrl.toString(), {
      method: "GET",
      aws: { signQuery: true },
    });

    return jsonResponse({ exportUrl: signedGet.url }, 200);
  })
);
