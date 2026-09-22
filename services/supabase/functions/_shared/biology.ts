import { SupabaseClient, User } from "@supabase/supabase-js";
import {
  type GeminiUsageMetadata,
  recordAIUsageBestEffort,
} from "./aiUsage.ts";
import type {
  AIExecutionOutcome,
  AIUsage,
  PreparedAIExecution,
} from "./ai/contracts.ts";
import { trackPostHogEvent } from "./posthog.ts";
import { aiExecutionMetadata } from "./ai/execution.ts";

// Compatibility projection for existing usage ledgers and helper consumers.
type UsageMetadata = GeminiUsageMetadata;
function legacyUsage(usage: AIUsage | null): UsageMetadata | undefined {
  if (!usage) return undefined;
  const result: UsageMetadata = {};
  const counts = {
    promptTokenCount: usage.promptTokens,
    candidatesTokenCount: usage.candidateTokens,
    totalTokenCount: usage.totalTokens,
    thoughtsTokenCount: usage.thinkingTokens,
    cachedContentTokenCount: usage.cachedTokens,
    toolUsePromptTokenCount: usage.toolTokens,
  };
  for (const [key, value] of Object.entries(counts)) {
    if (value != null) Object.assign(result, { [key]: value });
  }
  for (
    const [key, kind] of [
      ["promptTokensDetails", "prompt"],
      ["cacheTokensDetails", "cached"],
      ["candidatesTokensDetails", "candidates"],
      ["toolUsePromptTokensDetails", "tool"],
    ]
  ) {
    const counts = usage.modalityBreakdown[kind];
    if (counts && typeof counts === "object" && !Array.isArray(counts)) {
      const entries = Object.entries(counts);
      if (entries.length) {
        Object.assign(result, {
          [key]: entries.map(([modality, tokenCount]) => ({
            modality,
            tokenCount,
          })),
        });
      }
    }
  }
  return result;
}

function requireDraft<T>(result: AIExecutionOutcome): T {
  if (result.kind !== "draft") throw new Error(`ai_content_${result.kind}`);
  return result.draft as T;
}

function assertTask(
  execution: PreparedAIExecution,
  task: "species_overview" | "lookalikes" | "group_tags",
) {
  if (execution.snapshot.task !== task) {
    throw new Error("ai_content_task_mismatch");
  }
}

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
  execution?: Record<string, unknown>;
}

export async function fetchStaticEncyclopedicData(
  user: User | string,
  scientificName: string,
  execution: PreparedAIExecution,
): Promise<EncyclopedicData> {
  assertTask(execution, "species_overview");
  const modelName = execution.snapshot.model;
  try {
    const result = await execution.invoke();
    const usage = legacyUsage(result.usage);
    if (usage) {
      console.log(
        `Token Usage [Encyclopedic | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "EncyclopedicLLMCompleted", {
        ...aiExecutionMetadata(result),
        scientific_name: scientificName,
        llm_model: modelName,
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      }).catch((e) =>
        console.error("PostHog EncyclopedicLLMCompleted failed:", e)
      );
    }

    const extracted = requireDraft<EncyclopedicData>(result);
    extracted.execution = aiExecutionMetadata(result);
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

export async function fetchSimilarSpecies(
  user: User | string,
  scientificName: string,
  execution: PreparedAIExecution,
): Promise<
  {
    similar_species: SimilarSpeciesEntry[];
    usage?: UsageMetadata;
    execution?: Record<string, unknown>;
  } | null
> {
  assertTask(execution, "lookalikes");
  const modelName = execution.snapshot.model;
  try {
    const result = await execution.invoke();
    const usage = legacyUsage(result.usage);
    if (usage) {
      console.log(
        `Token Usage [SimilarSpecies | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "SimilarSpeciesLLMCompleted", {
        ...aiExecutionMetadata(result),
        scientific_name: scientificName,
        llm_model: modelName,
        llm_prompt_tokens: usage.promptTokenCount,
        llm_candidate_tokens: usage.candidatesTokenCount,
        llm_total_tokens: usage.totalTokenCount,
      }).catch((e) =>
        console.error("PostHog SimilarSpeciesLLMCompleted failed:", e)
      );
    }
    const raw = requireDraft<{
      similar_species: Array<{
        scientific_name: string;
        common_name?: string;
        reason?: string;
        visual_traits?: unknown[];
        confidence?: number;
      }>;
    }>(result);
    const normalized: {
      similar_species: SimilarSpeciesEntry[];
      usage?: UsageMetadata;
      execution?: Record<string, unknown>;
    } = {
      execution: aiExecutionMetadata(result),
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
  execution: PreparedAIExecution,
  supabaseAdmin?: SupabaseClient,
): Promise<
  {
    group_tags: string[] | null;
    usage?: UsageMetadata;
    execution?: Record<string, unknown>;
  } | null
> {
  assertTask(execution, "group_tags");
  const modelName = execution.snapshot.model;
  try {
    const result = await execution.invoke();
    const usage = legacyUsage(result.usage);
    if (usage) {
      console.log(
        `Token Usage [GroupTags | ${scientificName}]: Sent: ${usage.promptTokenCount} | Received: ${usage.candidatesTokenCount} | Total: ${usage.totalTokenCount}`,
      );
      trackPostHogEvent(user, "GroupTagsLLMCompleted", {
        ...aiExecutionMetadata(result),
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
          metadata: aiExecutionMetadata(result),
          inputModality: "text",
          userId: typeof user === "string" ? null : user.id,
        });
      }
    }

    const parsed = requireDraft<{ group_tags: string[] }>(result);
    return {
      group_tags: parsed.group_tags ?? null,
      usage,
      execution: aiExecutionMetadata(result),
    };
  } catch (e) {
    console.error("fetchGroupTags failed:", e);
    throw e;
  }
}
