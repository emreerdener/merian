/** Private, offline-only provider schema. Never changes a legacy model contract. */
import {
  type MerianIdentification,
  merianModelContract,
  normalizePrimaryIdentification,
  type ObjectContract,
  type PrimaryIdentification,
  primaryIdentificationContract,
} from "../identify/contract.ts";
import { decodeOpenAIContract } from "./openaiRequest.ts";

export type PrimaryResolution = PrimaryIdentification["resolution"];
export type SolPrimaryCandidate = MerianIdentification["candidates"][number] & {
  taxon_rank: "species";
};
export type SolPrimaryDraft = Omit<MerianIdentification, "candidates"> & {
  resolution: PrimaryResolution;
  candidates: SolPrimaryCandidate[] | null;
};

const fields = merianModelContract.fields;

export const solPhotoPrimaryModelContract = freeze(
  {
    kind: "object",
    unknownKeys: "reject",
    fields: {
      ...fields,
      resolution: {
        ...primaryIdentificationContract.fields.resolution,
        swift: false,
        contract: {
          ...primaryIdentificationContract.fields.resolution.contract,
          description:
            "Explicit primary answer: species, genus, family, unresolved_biological, or non_biological. Choose the most specific rank supported by visible diagnostic evidence. A broad rank is not a species claim; use unresolved_biological when no supported rank is available.",
        },
      },
      scientific_name: {
        ...fields.scientific_name,
        required: true,
        contract: {
          ...fields.scientific_name.contract,
          description:
            "Accepted name at the declared species, genus or family resolution, without authors or uncertainty qualifiers. Required for those three ranks; null for unresolved_biological. Do not invent a parent by shortening a hybrid, cultivar or infraspecific name. The existing domestic-dog convention Canis lupus familiaris is supported. Non-biological geological naming follows Geological Exceptions.",
        },
      },
      common_name: {
        ...fields.common_name,
        required: true,
        contract: {
          ...fields.common_name.contract,
          description:
            "English name in Title Case matching the declared resolution. Genus and family answers need a group label, never the name of one possible species. An unresolved biological subject may have a broad description or null. Preserve non-biological object/mineral naming.",
        },
      },
      candidates: {
        required: true,
        contract: {
          ...fields.candidates.contract,
          nullable: true,
          maxItems: 2,
          description:
            "For species resolution only, zero to two evidence-supported alternative species with explicit taxon_rank species. Use an empty array when none is supported. For genus, family, unresolved_biological and non_biological, return null.",
          items: {
            ...fields.candidates.contract.items,
            unknownKeys: "reject",
            fields: {
              ...fields.candidates.contract.items.fields,
              taxon_rank: {
                required: true,
                contract: { kind: "string", enum: ["species"] },
              },
              distinguishing_feature: {
                ...fields.candidates.contract.items.fields
                  .distinguishing_feature,
                contract: {
                  ...fields.candidates.contract.items.fields
                    .distinguishing_feature.contract,
                  description:
                    "One concise clause naming an observed distinction, or explicitly a feature that would need to be seen. An unseen feature is unknown, not absent. Never invent observations or repeat the species name.",
                },
              },
            },
          },
        },
      },
    },
  } as const satisfies ObjectContract,
);

/** Name syntax is a rejection guard, never evidence of a taxonomic rank. */
function rejectUnsupportedName(name: string | null | undefined) {
  if (
    name &&
    /[×'‘’"“”]|(?:^|\s)(?:x|var\.|subsp\.|ssp\.|f\.|cv\.|sp\.|spp\.|cf\.|aff\.)(?:\s|$)/i
      .test(name)
  ) throw new Error("sol_primary_unsupported_name");
}

export function decodeSolPhotoPrimaryDraft(value: unknown): SolPrimaryDraft {
  const draft = decodeOpenAIContract(
    value,
    solPhotoPrimaryModelContract,
  ) as SolPrimaryDraft;
  // Validate the declared state before any deterministic subject demotion.
  normalizePrimaryIdentification(draft.resolution, {
    is_biological_subject: draft.is_biological_subject,
    scientific_name: draft.scientific_name ?? null,
    common_name: draft.common_name ?? null,
  });
  if (draft.resolution !== "species") {
    if (draft.candidates !== null || draft.pet_identification != null) {
      throw new Error("sol_primary_species_effects_invalid");
    }
  } else if (draft.candidates === null) {
    throw new Error("sol_primary_species_candidates_invalid");
  }
  if (draft.is_biological_subject) {
    rejectUnsupportedName(draft.scientific_name);
    for (const candidate of draft.candidates ?? []) {
      rejectUnsupportedName(candidate.scientific_name);
    }
  }
  return draft;
}

function freeze<T>(value: T): T {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) freeze(child);
  }
  return value;
}
