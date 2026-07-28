import type { SupabaseClient } from "@supabase/supabase-js";

/** Canonical server release state shared by intake-adjacent Edge routes. */
export interface DwcaExportReleaseState {
  enabled: boolean;
}

export function parseDwcaExportReleaseState(
  value: unknown,
): DwcaExportReleaseState {
  if (
    value === null ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    typeof (value as Record<string, unknown>).enabled !== "boolean"
  ) {
    throw new Error("The DwC-A release state is invalid.");
  }
  return { enabled: (value as Record<string, boolean>).enabled };
}

export async function fetchDwcaExportReleaseState(
  supabaseAdmin: SupabaseClient,
): Promise<DwcaExportReleaseState> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_dwca_export_release_state",
  );
  if (error) {
    throw new Error("The DwC-A release state is unavailable.");
  }
  return parseDwcaExportReleaseState(data);
}
