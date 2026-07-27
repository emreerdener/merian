/**
 * Dry-run-first repair for scans where a processed/manufactured object was
 * accidentally linked to a biological species dictionary row.
 *
 * Required env:
 *   SUPABASE_URL
 *   SUPABASE_SERVER_API_KEY, deploy-synchronized
 *   MERIAN_SUPABASE_SERVER_API_KEY, or a platform-managed/legacy fallback
 *
 * Dry run:
 *   deno run --allow-net --allow-env \
 *     services/supabase/scripts/repair_processed_material_scan_pollution.ts
 *
 * Apply:
 *   deno run --allow-net --allow-env \
 *     services/supabase/scripts/repair_processed_material_scan_pollution.ts --apply
 */

import { createServiceRoleClientFromEnvironment } from "../functions/_shared/serviceRoleClient.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

interface RepairArgs {
  apply: boolean;
  limit: number;
}

interface SpeciesRow {
  id: string;
  scientific_name: string;
  common_names: Record<string, string> | null;
}

interface CandidateScanRow {
  id: string;
  species_id: string | null;
  confirmed_species_id?: string | null;
  ai_reasoning?: string | null;
  extracted_visual_traits?: string[] | null;
  candidates?: unknown[] | null;
  species_dictionary?: SpeciesRow | null;
}

interface PlannedScanRepair {
  scanId: string;
  speciesId: string;
  scientificName: string;
  currentEnglishName: string | null;
  evidence: string;
  dictionaryCommonNamesPatch: Record<string, string> | null;
}

const ARTIFACT_TERMS = [
  "rug",
  "kilim",
  "wool carpet",
  "textile",
  "fabric",
  "cloth",
  "flat-woven",
  "woven textile",
  "processed wool",
  "leather goods",
  "leather jacket",
  "wooden furniture",
  "paper bag",
  "paper sheet",
  "paper print",
  "cardboard",
  "furniture",
  "toy",
  "artwork",
  "painting",
  "sculpture",
  "printed depiction",
  "species depiction",
  "prepared food",
  "man-made",
  "man made",
  "human-made",
  "manufactured",
  "processed",
  "inanimate",
];

const KNOWN_CANONICAL_ENGLISH_NAMES: Record<string, string> = {
  "Ovis aries": "Domestic Sheep",
};

if (import.meta.main) {
  const exitCode = await runRepair(Deno.args);
  Deno.exit(exitCode);
}

export async function runRepair(rawArgs: string[]): Promise<number> {
  const args = parseArgs(rawArgs);
  const supabase = createServiceRoleClientFromEnvironment();

  const candidates = await fetchCandidateScans(
    supabase,
    args.limit,
  );
  const plannedRepairs = candidates.flatMap(planRepairForScan);

  printPlannedRepairs(plannedRepairs, args.apply);

  if (!args.apply) {
    console.log("dry_run: no rows changed. Re-run with --apply to patch rows.");
    return 0;
  }

  for (const repair of plannedRepairs) {
    await applyScanRepair(supabase, repair);
    if (repair.dictionaryCommonNamesPatch) {
      await applyDictionaryRepair(supabase, repair);
    }
  }

  console.log(`applied_repairs: ${plannedRepairs.length}`);
  return 0;
}

export function planRepairForScan(row: CandidateScanRow): PlannedScanRepair[] {
  if (!row.species_id || !row.species_dictionary) return [];

  const evidence = [
    row.ai_reasoning,
    ...(row.extracted_visual_traits ?? []),
  ]
    .filter((value): value is string => typeof value === "string")
    .join(" ")
    .toLowerCase();
  if (!containsArtifactEvidence(evidence)) return [];

  const species = row.species_dictionary;
  const currentEnglishName = species.common_names?.en?.trim() || null;
  const dictionaryCommonNamesPatch = repairedCommonNames(species);

  return [{
    scanId: row.id,
    speciesId: species.id,
    scientificName: species.scientific_name,
    currentEnglishName,
    evidence: evidence.slice(0, 240),
    dictionaryCommonNamesPatch,
  }];
}

function containsArtifactEvidence(value: string): boolean {
  return ARTIFACT_TERMS.some((term) => value.includes(term));
}

function repairedCommonNames(
  species: SpeciesRow,
): Record<string, string> | null {
  const commonNames = { ...(species.common_names ?? {}) };
  const englishName = commonNames.en?.trim();
  if (!englishName || !containsArtifactEvidence(englishName.toLowerCase())) {
    return null;
  }

  const canonicalName = KNOWN_CANONICAL_ENGLISH_NAMES[species.scientific_name];
  if (canonicalName) {
    return { ...commonNames, en: canonicalName };
  }

  delete commonNames.en;
  return commonNames;
}

async function fetchCandidateScans(
  supabase: SupabaseClient,
  limit: number,
): Promise<CandidateScanRow[]> {
  const { data, error } = await supabase
    .from("scans")
    .select(
      "id,species_id,confirmed_species_id,ai_reasoning,extracted_visual_traits,candidates,species_dictionary!species_id(id,scientific_name,common_names)",
    )
    .eq("is_biological_subject", true)
    .not("species_id", "is", null)
    .order("timestamp", { ascending: false })
    .limit(limit);

  if (error) {
    throw new Error(
      `Failed to fetch candidate scans: ${error.message} (Code: ${error.code})`,
    );
  }
  return data as unknown as CandidateScanRow[];
}

async function applyScanRepair(
  supabase: SupabaseClient,
  repair: PlannedScanRepair,
): Promise<void> {
  const { error } = await supabase
    .from("scans")
    .update({
      species_id: null,
      confirmed_species_id: null,
      is_biological_subject: false,
      ecology_type: "unknown",
      is_invasive: false,
      invasive_status_region: null,
      invasive_rationale: null,
      invasive_confidence: null,
      life_stage: "unknown",
      reproductive_condition: "not_applicable",
      sex: null,
      sex_confidence: null,
      sex_evidence: null,
      individual_count: null,
      ecological_interactions: [],
      candidates: null,
    })
    .eq("id", repair.scanId);

  if (error) {
    throw new Error(`Failed to apply scan repair: ${error.message}`);
  }
}

async function applyDictionaryRepair(
  supabase: SupabaseClient,
  repair: PlannedScanRepair,
): Promise<void> {
  const { error } = await supabase
    .from("species_dictionary")
    .update({ common_names: repair.dictionaryCommonNamesPatch })
    .eq("id", repair.speciesId);

  if (error) {
    throw new Error(`Failed to apply dictionary repair: ${error.message}`);
  }
}

function printPlannedRepairs(
  repairs: PlannedScanRepair[],
  apply: boolean,
): void {
  console.log(`mode: ${apply ? "apply" : "dry-run"}`);
  console.log(`planned_repairs: ${repairs.length}`);
  for (const repair of repairs) {
    console.log(JSON.stringify({
      scan_id: repair.scanId,
      scientific_name: repair.scientificName,
      current_english_name: repair.currentEnglishName,
      dictionary_common_names_patch: repair.dictionaryCommonNamesPatch,
      evidence: repair.evidence,
    }));
  }
}

function parseArgs(rawArgs: string[]): RepairArgs {
  const args: RepairArgs = { apply: false, limit: 500 };
  for (let i = 0; i < rawArgs.length; i++) {
    const arg = rawArgs[i];
    if (arg === "--apply") {
      args.apply = true;
    } else if (arg === "--limit") {
      const value = Number(rawArgs[++i]);
      if (!Number.isFinite(value) || value <= 0) {
        throw new Error("--limit must be a positive number.");
      }
      args.limit = Math.trunc(value);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return args;
}
