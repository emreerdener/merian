import { Schema, Type } from "@google/genai";
import { SupabaseClient, User } from "@supabase/supabase-js";
import { recordAIUsageBestEffort } from "./aiUsage.ts";
import { createFlashModel, extractJson } from "./gemini.ts";
import { trackPostHogEvent } from "./posthog.ts";
import { normalizeTaxonomyValue } from "./taxonomy.ts";

// Alias for backward compat within this file
type ResponseSchema = Schema;
const SchemaType = Type;
// Local usage metadata shape — avoids coupling return types to the SDK's internal type name.
// thoughtsTokenCount is the new field exposed by @google/genai for thinking token accounting.
type UsageMetadata = {
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  totalTokenCount?: number;
  thoughtsTokenCount?: number;
};

// --- ENCYCLOPEDIC DATA LOGIC --- //

export interface EncyclopedicData {
  taxonomy: {
    kingdom: string | null;
    phylum: string | null;
    class: string | null;
    order: string | null;
    family: string | null;
    genus: string | null;
  };
  iucn_red_list_status: string;
  habitat_description: string;
  hazard_type: string;
  colors: string[];
  usage?: UsageMetadata;
}

export async function fetchStaticEncyclopedicData(
  user: User | string,
  scientificName: string,
  locale: string,
  model: string,
): Promise<EncyclopedicData> {
  const textModel = createFlashModel(
    `# Role
You are a world-class encyclopedic biologist and taxonomist.

# Task
Given a species scientific name, provide the following data fields: taxonomy, habitat description, hazard classification, generalized physical colors, IUCN conservation status, and global distribution.

# Rules
- **Conciseness:** Keep all text descriptions concise and factual.
- **Locale:** ALL text responses (habitat_description) MUST be returned in the following ISO language locale: ${locale}.
- **Accuracy:** Base all fields on authoritative sources (GBIF, IUCN Red List, Catalogue of Life). Never fabricate data.`,
    1500,
    model,
  );

  const cacheSchema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      taxonomy: {
        type: SchemaType.OBJECT,
        properties: {
          kingdom: { type: SchemaType.STRING },
          phylum: { type: SchemaType.STRING },
          class: { type: SchemaType.STRING },
          order: { type: SchemaType.STRING },
          family: { type: SchemaType.STRING },
          genus: { type: SchemaType.STRING },
        },
        required: ["kingdom", "phylum", "class", "order", "family", "genus"],
      },
      iucn_red_list_status: {
        type: SchemaType.STRING,
        enum: [
          "not_evaluated",
          "data_deficient",
          "least_concern",
          "near_threatened",
          "vulnerable",
          "endangered",
          "critically_endangered",
          "extinct_in_the_wild",
          "extinct",
        ],
      },
      habitat_description: { type: SchemaType.STRING },
      hazard_type: {
        type: SchemaType.STRING,
        enum: ["none", "poisonous", "venomous", "allergenic", "irritant"],
        description: "Generalized hazard type for this species.",
      },
      colors: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description:
          "1-3 generalized physical colors that typically identify this species.",
      },
    },
    required: [
      "taxonomy",
      "iucn_red_list_status",
      "habitat_description",
      "hazard_type",
      "colors",
    ],
  };

  try {
    const result = await textModel.generateContent({
      contents: [
        {
          role: "user",
          parts: [
            { text: `Generate metadata for the species: ${scientificName}` },
          ],
        },
      ],
      config: {
        responseMimeType: "application/json",
        responseSchema: cacheSchema as unknown as ResponseSchema,
      },
    });

    const usage = result.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [Encyclopedic | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "EncyclopedicLLMCompleted", {
        scientific_name: scientificName,
        llm_model: model,
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      }).catch((e) =>
        console.error("PostHog EncyclopedicLLMCompleted failed:", e)
      );
    }

    const extracted = extractJson<EncyclopedicData>(result.text ?? "");
    if (usage) {
      extracted.usage = usage;
    }
    return extracted;
  } catch (e) {
    console.error("Encyclopedic inference failed:", e);
    throw e;
  }
}

// --- SIMILAR SPECIES LOGIC --- //

export interface SimilarSpeciesEntry {
  scientific_name: string;
  common_name: string | null;
  reason?: string | null;
  visual_traits?: string[];
  confidence?: number | null;
}

export interface SpeciesTaxonomy {
  kingdom?: string | null;
  class?: string | null;
  order?: string | null;
  family?: string | null;
}

export async function fetchSimilarSpecies(
  user: User | string,
  scientificName: string,
  taxonomy: SpeciesTaxonomy | null | undefined,
  modelName: string,
): Promise<
  { similar_species: SimilarSpeciesEntry[]; usage?: UsageMetadata } | null
> {
  const normalizedKingdom = normalizeTaxonomyValue(taxonomy?.kingdom);
  const normalizedClass = normalizeTaxonomyValue(taxonomy?.class);
  const normalizedOrder = normalizeTaxonomyValue(taxonomy?.order);
  const normalizedFamily = normalizeTaxonomyValue(taxonomy?.family);

  // Build a taxonomic context string so Flash is grounded in the correct kingdom/class/order.
  // Without this, the model can hallucinate cross-kingdom suggestions (e.g. plants for insects).
  const taxonomicContext = [
    normalizedKingdom ? `Kingdom: ${normalizedKingdom}` : null,
    normalizedClass ? `Class: ${normalizedClass}` : null,
    normalizedOrder ? `Order: ${normalizedOrder}` : null,
    normalizedFamily ? `Family: ${normalizedFamily}` : null,
  ]
    .filter(Boolean)
    .join(", ");

  const taxonomyLine = taxonomicContext
    ? `\n\nThe species belongs to: ${taxonomicContext}. ALL lookalikes MUST belong to the same kingdom AND the same order or family as the primary species. If no suitable lookalikes exist at that rank, return fewer entries rather than suggesting unrelated species.`
    : "";

  const model = createFlashModel(
    `# Role
You are a world-class field biologist specializing in species misidentification and visual lookalikes.

# Task
Given a species scientific name, identify up to 3 species that a non-expert field observer could plausibly misidentify it as based purely on visual appearance in the field.${taxonomyLine}

For each lookalike, provide the exact formally recognized scientific name, the widely recognised English common name, a concise explanation of the visual confusion, the concrete visible traits shared by both species, and a calibrated relation confidence.

# Rules
1. **Taxonomic Constraint:** Every lookalike MUST be from the same taxonomic order or family as the primary species — never suggest species from a different order.
2. **Visual Similarity:** Lookalikes must be genuinely visually similar in the field (similar flower shape, leaf morphology, growth habit, plumage, etc.) — not merely distantly related.
3. **Name Accuracy:** Never hallucinate scientific names. Every entry must be a verified, extant species recognized by GBIF or Catalogue of Life.
4. **No Padding:** If fewer than 3 genuine same-order lookalikes exist, return only the valid ones — do not pad with unrelated species.
5. **No Self-Reference:** Do not return the primary species itself as a lookalike.
6. **Explainability:** Reasons must be species-level visual explanations, not user-specific observations. Do not mention scans, photos, people, locations, dates, or field notes.
7. **Confidence:** Confidence is relation quality from 0.0 to 1.0, where 1.0 means a very strong field-confusion relationship and 0.5 means weak but plausible.`,
    300,
    modelName,
  );

  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      similar_species: {
        type: SchemaType.ARRAY,
        items: {
          type: SchemaType.OBJECT,
          properties: {
            scientific_name: { type: SchemaType.STRING },
            common_name: { type: SchemaType.STRING },
            reason: {
              type: SchemaType.STRING,
              description:
                "One concise sentence explaining why field observers may confuse the two species visually.",
            },
            visual_traits: {
              type: SchemaType.ARRAY,
              items: { type: SchemaType.STRING },
              description:
                "Two to four concrete shared visual traits, such as wing pattern, flower shape, bark texture, silhouette, or growth habit.",
            },
            confidence: {
              type: SchemaType.NUMBER,
              description:
                "0.0 to 1.0 confidence that this is a strong visual lookalike relation.",
            },
          },
          required: [
            "scientific_name",
            "common_name",
            "reason",
            "visual_traits",
            "confidence",
          ],
        },
        description:
          `Up to 3 closely related but genuinely visually similar lookalike species from the same kingdom${
            normalizedClass ? ` and class (${normalizedClass})` : ""
          }, each with a real, formally recognized scientific name, English common name, visual reason, shared traits, and relation confidence.`,
      },
    },
    required: ["similar_species"],
  };

  const userPrompt = taxonomicContext
    ? `Identify up to 3 genuine lookalike species for: ${scientificName} (${taxonomicContext})`
    : `Identify up to 3 genuine lookalike species for: ${scientificName}`;

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: userPrompt }],
        },
      ],
      config: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });
    const usage = result.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [SimilarSpecies | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "SimilarSpeciesLLMCompleted", {
        scientific_name: scientificName,
        llm_model: modelName,
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      }).catch((e) =>
        console.error("PostHog SimilarSpeciesLLMCompleted failed:", e)
      );
    }
    const raw = extractJson<{
      similar_species: Array<{
        scientific_name: string;
        common_name?: string;
        reason?: string;
        visual_traits?: unknown[];
        confidence?: number;
      }>;
    }>(result.text ?? "");
    const normalized: {
      similar_species: SimilarSpeciesEntry[];
      usage?: UsageMetadata;
    } = {
      similar_species: (raw.similar_species ?? []).map((e) => ({
        scientific_name: e.scientific_name,
        common_name: e.common_name || null,
        reason: sanitizeLookalikeReason(e.reason),
        visual_traits: sanitizeLookalikeTraits(e.visual_traits),
        confidence: normalizeLookalikeConfidence(e.confidence),
      })),
    };
    if (usage) normalized.usage = usage;
    return normalized;
  } catch (e) {
    console.error("fetchSimilarSpecies failed:", e);
    throw e;
  }
}

function sanitizeLookalikeReason(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim().replace(/\s+/g, " ");
  return trimmed.length > 0 ? trimmed.slice(0, 240) : null;
}

function sanitizeLookalikeTraits(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const seen = new Set<string>();
  const traits: string[] = [];

  for (const entry of value) {
    if (typeof entry !== "string") continue;
    const trimmed = entry.trim().replace(/\s+/g, " ");
    if (!trimmed) continue;
    const key = trimmed.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    traits.push(trimmed.slice(0, 80));
    if (traits.length >= 5) break;
  }

  return traits;
}

function normalizeLookalikeConfidence(value: unknown): number | null {
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return Math.max(0, Math.min(1, value));
}

// --- GROUP TAGS LOGIC --- //

export async function fetchGroupTags(
  user: User | string,
  scientificName: string,
  modelName: string,
  supabaseAdmin?: SupabaseClient,
): Promise<{ group_tags: string[] | null; usage?: UsageMetadata } | null> {
  const model = createFlashModel(
    'You are a world-class biologist. Given a species scientific name, return 1–5 categorical group labels ordered from most broad to most specific (e.g. ["animal", "bird", "songbird", "warbler"]). Use plain lowercase English nouns only. Omit proper names and scientific names.',
    100,
    modelName,
  );

  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      group_tags: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description: "1–5 categorical group labels, broad to specific.",
      },
    },
    required: ["group_tags"],
  };

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: `Group tags for: ${scientificName}` }],
        },
      ],
      config: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });

    const usage = result.usageMetadata;
    if (usage) {
      console.log(
        `Token Usage [GroupTags | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "GroupTagsLLMCompleted", {
        scientific_name: scientificName,
        llm_model: modelName,
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      }).catch((e) =>
        console.error("PostHog GroupTagsLLMCompleted failed:", e)
      );
      if (supabaseAdmin) {
        recordAIUsageBestEffort(supabaseAdmin, {
          operation: "scan_group_tag_enrichment",
          model: modelName,
          usage,
          inputModality: "text",
          userId: typeof user === "string" ? null : user.id,
        });
      }
    }

    const parsed = extractJson<{ group_tags: string[] }>(
      result.text ?? "",
    );
    return { group_tags: parsed.group_tags ?? null, usage };
  } catch (e) {
    console.error("fetchGroupTags failed:", e);
    throw e;
  }
}
