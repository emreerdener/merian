import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "../_shared/http.ts";
import type { VerifiedLookalikeTaxon } from "../_shared/verifiedSpecies.ts";

export interface ResolvedSpecies {
  species_id: string;
  scientific_name: string;
}

export async function findSpecies(
  admin: SupabaseClient,
  name: string,
): Promise<ResolvedSpecies | null> {
  const { data, error } = await admin.from("species_dictionary")
    .select("id, scientific_name, is_public_biological")
    .eq("scientific_name", name).limit(1).maybeSingle();
  if (error) throw new Error("Species identity lookup failed.");
  if (!data) return null;
  // An existing nonpublic row is never replaced or bypassed through GBIF.
  if (!data.is_public_biological) {
    throw publicHttpError(
      404,
      "This species cannot be resolved.",
      "species_not_available",
    );
  }
  return { species_id: data.id, scientific_name: data.scientific_name };
}

export async function admitResolution(
  admin: SupabaseClient,
  userID: string,
): Promise<void> {
  const { error } = await admin.rpc("admit_species_dictionary_resolution", {
    viewer_id: userID,
  });
  if (error) {
    if (error.message.includes("species_resolution_rate_limited")) {
      throw publicHttpError(
        429,
        "Please try again later.",
        "rate_limited",
      );
    }
    throw new Error("Species resolution admission failed.");
  }
}

export async function persistSpecies(
  admin: SupabaseClient,
  taxon: VerifiedLookalikeTaxon,
): Promise<ResolvedSpecies> {
  const { data, error } = await admin.rpc(
    "resolve_verified_dictionary_species",
    { taxon },
  );
  if (
    error && [
      "species_resolution_identity_conflict",
      "species_resolution_ambiguous_identity",
    ].includes(error.message)
  ) {
    throw publicHttpError(
      404,
      "This species cannot be resolved.",
      "species_not_available",
    );
  }
  if (error || typeof data !== "string") {
    throw new Error("Species resolution persistence failed.");
  }
  const { data: row, error: readError } = await admin.from("species_dictionary")
    .select("id, scientific_name, is_public_biological, gbif_taxon_key")
    .eq("id", data).limit(1).maybeSingle();
  if (
    readError || !row || row.id !== data || !row.is_public_biological ||
    row.gbif_taxon_key !== taxon.gbif_taxon_key
  ) {
    throw new Error("Species resolution identity mismatch.");
  }
  return { species_id: row.id, scientific_name: row.scientific_name };
}
