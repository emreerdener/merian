/** Invented contract fixtures only; these are not identification references. */
import type { PrimaryResolution } from "../openaiSolPrimaryContract.ts";
import { openAIDraftFixture } from "./openaiFixtures.ts";

export function solPrimaryDraftFixture(
  resolution: PrimaryResolution = "species",
): Record<string, unknown> {
  const names = {
    species: ["Syntheticus example", "Synthetic species"],
    genus: ["Syntheticus", "Synthetic group"],
    family: ["Syntheticaceae", "Synthetic family"],
    unresolved_biological: [null, "Unresolved organism"],
    non_biological: ["Quartz", "Quartz"],
  } as const;
  return {
    ...openAIDraftFixture(),
    resolution,
    scientific_name: names[resolution][0],
    common_name: names[resolution][1],
    is_biological_subject: resolution !== "non_biological",
    candidates: resolution === "species" ? [] : null,
    ai_reasoning: "Invented explanation for contract testing only.",
  };
}

export function solPrimaryAlternativeFixture() {
  return {
    scientific_name: "Syntheticus secunda",
    confidence_score: 0.4,
    distinguishing_feature: "A distinguishing structure is not shown.",
    taxon_rank: "species",
  };
}
