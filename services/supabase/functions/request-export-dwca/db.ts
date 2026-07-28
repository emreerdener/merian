// deno-lint-ignore no-import-prefix
import { SupabaseClient } from "@supabase/supabase-js";

export type DwcaExportRequestDisposition =
  | "queued"
  | "disabled"
  | "rate_limited"
  | "already_pending";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function requestDwcaExportJob(
  userId: string,
  exportScope: string,
  includePreciseCoordinates: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<DwcaExportRequestDisposition> {
  const { data, error } = await supabaseAdmin.rpc(
    "request_dwca_export_job",
    {
      p_user_id: userId,
      p_export_scope: exportScope,
      p_include_precise_coordinates: includePreciseCoordinates,
    },
  );
  if (error) {
    throw new Error("Failed to request a DwC-A export.");
  }
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    throw new Error("The DwC-A export request returned an invalid result.");
  }
  const row = data as Record<string, unknown>;
  switch (row.status) {
    case "queued":
      if (typeof row.job_id !== "string" || !UUID_PATTERN.test(row.job_id)) {
        throw new Error("The queued DwC-A export identifier is invalid.");
      }
      return "queued";
    case "disabled":
    case "rate_limited":
    case "already_pending":
      return row.status;
    default:
      throw new Error("The DwC-A export request returned an unknown result.");
  }
}
