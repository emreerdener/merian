import type {
  AIAttemptSnapshot,
  AIExecutionAuthority,
  SpeciesContentAIRequest,
} from "./contracts.ts";

const profiles = {
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

/** Reuse admitted user leases or claimed public jobs; never create admission. */
export function resolveContentClaim(
  request: SpeciesContentAIRequest,
  authority: AIExecutionAuthority,
): AIAttemptSnapshot {
  if (
    request.variant !== "species_content" ||
    !Object.hasOwn(profiles, request.task) ||
    typeof request.scientificName !== "string" ||
    !request.scientificName.trim() ||
    (request.task === "species_overview" &&
      (typeof request.locale !== "string" || !request.locale.trim()))
  ) throw new Error("ai_unsupported_input");
  const profile = profiles[request.task];
  let model: string;
  let policyVersion: number | null = null;
  if (authority.kind === "user_request") {
    if (
      authority.operation !== profile.operation ||
      authority.permission !== "google_gemini" || !authority.userId ||
      !authority.reservation.id || !authority.reservation.requestId ||
      !Number.isSafeInteger(authority.reservation.attemptCount) ||
      authority.reservation.attemptCount < 1 ||
      !Number.isSafeInteger(authority.reservation.policyVersion) ||
      authority.reservation.policyVersion < 1
    ) throw new Error("ai_authority_mismatch");
    model = authority.reservation.model;
    policyVersion = authority.reservation.policyVersion;
  } else if (authority.kind === "service_job") {
    if (
      authority.purpose !== "public_species_facts" ||
      authority.task !== request.task ||
      !authority.jobId || !Number.isSafeInteger(authority.attemptCount) ||
      authority.attemptCount < 1 ||
      !Number.isSafeInteger(authority.maxAttempts) ||
      authority.maxAttempts < authority.attemptCount
    ) throw new Error("ai_authority_mismatch");
    model = authority.model;
    if (model !== "gemini-2.5-flash") throw new Error("ai_model_not_enabled");
  } else throw new Error("ai_authority_mismatch");
  if (model !== "gemini-2.5-flash" && model !== "gemini-2.5-pro") {
    throw new Error("ai_model_not_enabled");
  }
  return Object.freeze({
    provider: "gemini",
    binding: "gemini_baseline_v1",
    task: request.task,
    variant: request.variant,
    model,
    contextKind: authority.kind,
    operation: profile.operation,
    policyVersion,
    permission: authority.kind === "user_request" ? "google_gemini" : null,
    prompt: profile.version,
    schema: profile.version,
    confidence: null,
    timeoutMs: 90000,
    generation: Object.freeze({
      temperature: 0.1,
      maxOutputTokens: profile.maxOutputTokens,
      thinkingBudget: 0,
    }),
  });
}
