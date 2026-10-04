import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../http.ts";

export function hasControl(value: string): boolean {
  return Array.from(value).some((character) => {
    const code = character.charCodeAt(0);
    return code < 32 || code === 127;
  });
}
export function isScientificName(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= 160 &&
    value === value.trim() && !hasControl(value);
}

export async function admitReview(
  admin: SupabaseClient,
  userID: string,
): Promise<void> {
  const { error } = await admin.rpc("admit_species_dictionary_resolution", {
    viewer_id: userID,
  });
  if (error?.message === "species_resolution_rate_limited") {
    throw publicHttpError(429, "Please try again later.", "rate_limited");
  }
  if (error) throw new Error("Species review admission failed.");
}
