import { GEMINI_CANDIDATE_PROFILES } from "./geminiProfiles.ts";
import type {
  AIExecutionAuthority,
  GeminiAttemptSnapshot,
  SpeciesContentAIRequest,
} from "./contracts.ts";
import type { prepareAIExecution } from "./production.ts";

type ContentTask = SpeciesContentAIRequest["task"];

// This is an independently reviewed acceptance boundary, not the routing registry.
// Both profiles are explicitly accepted for structured writes. The generation-3
// rollout accepts unmeasured model quality; this is not biological qualification.
const qualified = {
  species_overview: {
    operation: "scan_overview_enrichment",
    version: "species_overview_v1",
    maxOutputTokens: 1500,
  },
  lookalikes: {
    operation: "scan_lookalike_enrichment",
    version: "lookalikes_v1",
    maxOutputTokens: 300,
  },
  group_tags: {
    operation: "scan_group_tag_enrichment",
    version: "group_tags_v1",
    maxOutputTokens: 100,
  },
} as const;
const snapshotKeys = [
  "provider",
  "binding",
  "task",
  "variant",
  "model",
  "contextKind",
  "operation",
  "policyVersion",
  "permission",
  "prompt",
  "schema",
  "confidence",
  "timeoutMs",
  "generation",
];
const generationKeys = ["temperature", "maxOutputTokens", "thinkingBudget"];
const unavailable = () => new Error("ai_shared_content_profile_unqualified");
const record = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
const exactKeys = (value: Record<string, unknown>, keys: readonly string[]) =>
  Object.keys(value).length === keys.length &&
  keys.every((key) => Object.hasOwn(value, key));

export function assertSharedSpeciesContentSnapshot(
  snapshot: unknown,
  task: ContentTask,
): asserts snapshot is GeminiAttemptSnapshot {
  const profile = qualified[task];
  const baseline = record(snapshot) && record(snapshot.generation) &&
    snapshot.binding === "gemini_baseline_v1" &&
    snapshot.model === "gemini-2.5-flash" &&
    exactKeys(snapshot.generation, generationKeys) &&
    snapshot.generation.temperature === 0.1 &&
    snapshot.generation.thinkingBudget === 0 &&
    snapshot.generation.maxOutputTokens === profile?.maxOutputTokens;
  const candidate = record(snapshot) && record(snapshot.generation) &&
    snapshot.binding === "gemini_generation3_v1" &&
    snapshot.model === "gemini-3.5-flash-lite" &&
    exactKeys(snapshot.generation, ["thinkingLevel", "maxOutputTokens"]) &&
    snapshot.generation.thinkingLevel === "minimal" &&
    snapshot.generation.maxOutputTokens ===
      GEMINI_CANDIDATE_PROFILES[task]?.maxOutputTokens;
  if (
    !Object.hasOwn(qualified, task) || !profile || !record(snapshot) ||
    !exactKeys(snapshot, snapshotKeys) ||
    snapshot.provider !== "gemini" ||
    (!baseline && !candidate) ||
    snapshot.task !== task || snapshot.variant !== "species_content" ||
    snapshot.operation !== profile.operation ||
    snapshot.prompt !== profile.version ||
    snapshot.schema !== profile.version || snapshot.confidence !== null ||
    snapshot.timeoutMs !== 90000
  ) throw unavailable();
  const user = snapshot.contextKind === "user_request" &&
    snapshot.permission === "google_gemini" &&
    Number.isSafeInteger(snapshot.policyVersion) &&
    Number(snapshot.policyVersion) > 0;
  const service = snapshot.contextKind === "service_job" &&
    snapshot.permission === null &&
    snapshot.policyVersion === null;
  if (!user && !service) throw unavailable();
}

function assertInput(request: SpeciesContentAIRequest) {
  if (
    request.variant !== "species_content" ||
    !Object.hasOwn(qualified, request.task) ||
    (typeof request.scientificName !== "string" ||
      !request.scientificName.trim()) ||
    (request.task === "species_overview" && request.locale !== "en")
  ) throw unavailable();
}

/** No admission or disclosure: reject before the caller commits its quota lease. */
export function prepareSharedSpeciesContent(
  request: SpeciesContentAIRequest,
  authority: AIExecutionAuthority,
  prepare: typeof prepareAIExecution,
) {
  assertInput(request);
  const execution = prepare(request, authority);
  assertSharedSpeciesContentSnapshot(execution.snapshot, request.task);
  return execution;
}

/** Scope warm-isolate coalescing; never persist this as historical provenance.
 * Existing canonical content is shared under the retained Gemini baseline.
 * A different producer needs separate qualification and storage/promotion rules.
 */
export function sharedSpeciesContentKey(
  request: SpeciesContentAIRequest,
  canonicalIdentity: string,
): string {
  assertInput(request);
  if (!canonicalIdentity.trim()) throw unavailable();
  const taxonomy = request.task === "lookalikes" ? request.taxonomy : null;
  return JSON.stringify([
    "shared_species_gemini_v1",
    request.task,
    qualified[request.task].version,
    canonicalIdentity,
    request.scientificName,
    request.task === "species_overview" ? request.locale : null,
    taxonomy?.kingdom ?? null,
    taxonomy?.class ?? null,
    taxonomy?.order ?? null,
    taxonomy?.family ?? null,
  ]);
}
