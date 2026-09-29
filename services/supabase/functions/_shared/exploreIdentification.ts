/** Public allowlist: label semantics only, never scan/review authority or model metrics. */
export interface ExploreIdentification {
  version: 1;
  rank: "species" | "genus" | "family" | "unresolved_biological";
  label_source: "ai_primary" | "verified_selection" | "community";
  original_rank:
    | "species"
    | "genus"
    | "family"
    | "unresolved_biological"
    | null;
  original_scientific_name: string | null;
  original_common_name: string | null;
}
