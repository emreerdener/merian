import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  DWCA_META_XML,
  generateDwcARow,
  MULTIMEDIA_HEADERS,
  OCCURRENCE_HEADERS,
} from "./dwca.ts";
import { DBScanRow } from "./types.ts";

export async function fetchUserEmail(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<string> {
  const { data: { user }, error: userError } = await supabaseAdmin.auth.admin
    .getUserById(userId);
  if (userError || !user?.email) {
    throw new Error(
      `Could not find email to deliver export: ${userError?.message}`,
    );
  }
  return user.email;
}

export async function updateExportJobStatus(
  jobId: string,
  status: "processing" | "completed" | "failed",
  supabaseAdmin: SupabaseClient,
  errorMessage?: string,
  fileUrl?: string,
) {
  // deno-lint-ignore no-explicit-any
  const payload: any = { status };

  if (status === "failed") {
    payload.error_message = errorMessage;
    payload.completed_at = new Date().toISOString();
  }
  if (status === "completed") {
    payload.file_url = fileUrl;
    payload.completed_at = new Date().toISOString();
  }

  await supabaseAdmin.from("export_jobs").update(payload).eq("id", jobId);
}

export async function fetchAndFormatScans(
  userId: string,
  exportScope: string,
  includePrecise: boolean,
  supabaseAdmin: SupabaseClient,
  secretHashSalt: string,
): Promise<{ occurrenceCsv: string; multimediaCsv: string; metaXml: string }> {
  // Query verified academic captures
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

  if (exportScope === "global") {
    query = query.eq("geoprivacy", "open");
  } else {
    query = query.eq("user_id", userId);
  }

  const occurrenceRows = [OCCURRENCE_HEADERS];
  const multimediaRows = [MULTIMEDIA_HEADERS];

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
        subBatch.map(async (row) => {
          const scan = row as unknown as DBScanRow;
          return await generateDwcARow(
            scan,
            exportScope,
            includePrecise,
            userId,
            secretHashSalt,
          );
        }),
      );
      batchResults.push(...subBatchResults);
    }

    for (const res of batchResults) {
      occurrenceRows.push(res.occurrenceRow);
      if (res.mRows.length > 0) multimediaRows.push(res.mRows.join("\n"));
    }

    // @ts-ignore: Deno garbage collection is manually invoked here
    globalThis.gc?.();

    if (data.length < PAGE_SIZE || occurrenceRows.length >= 10000) {
      hasMore = false;
    } else {
      start += PAGE_SIZE;
    }
  }

  return {
    occurrenceCsv: occurrenceRows.join("\n") + "\n",
    multimediaCsv: multimediaRows.join("\n") + "\n",
    metaXml: DWCA_META_XML,
  };
}
