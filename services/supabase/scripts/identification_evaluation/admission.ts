import { isOpenAIProfile } from "../../functions/_shared/ai/openaiRequest.ts";
import {
  corpusRetention,
  fingerprintRunCorpus,
  isSyntheticCorpus,
  parseRunCorpus,
  referenceLabels,
  type RunCorpus,
} from "./exploratory.ts";
import { INPUT_GROUPS } from "./contracts.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import {
  CANDIDATE_SPEC_VERSION,
  type EvaluationPricing,
  type EvaluationReadiness,
  parseEvaluationPricing,
  parseEvaluationReadiness,
  PROVIDER_SPEC_VERSION,
  providerForProfile,
  referenceTaxaExist,
  type RunSpec,
  type Taxonomy,
} from "./runContracts.ts";
import { requireCondition as check } from "./validation.ts";

export async function validateSelectionFacts(
  corpusValue: RunCorpus,
  spec: RunSpec,
  taxonomy: Taxonomy,
): Promise<void> {
  const corpus = parseRunCorpus(corpusValue);
  check(
    await fingerprintRunCorpus(corpus) === spec.corpusDigest &&
      await fingerprintJson(taxonomy) === spec.taxonomyDigest,
  );
  check(corpus.taxonomyVersion === taxonomy.taxonomyVersion);
  check(
    taxonomy.version !== "evaluation_taxonomy_v2" ||
      corpus.kind === "exploratory",
  );
  const selected = corpus.cases.filter((c) =>
    spec.caseIds.includes(c.input.caseId)
  );
  check(
    selected.length === spec.caseIds.length &&
      selected.every((c) => c.input.split === spec.split),
  );
  check(
    referenceTaxaExist(
      taxonomy,
      referenceLabels(corpus).flatMap((r) => [...r.acceptableTaxa]),
    ),
  );
  if (corpus.kind === "exploratory") {
    check(
      spec.stage === "exploratory" && selected.length === corpus.cases.length,
    );
    check(
      spec.mode === "offline"
        ? isSyntheticCorpus(corpus)
        : corpus.evidenceOrigin === "real" && corpus.eligibility !== null,
    );
    return;
  }
  check(spec.stage !== "exploratory");
  if (spec.mode === "offline") {
    check(corpus.kind === "synthetic");
    return;
  }
  check(corpus.kind === "reference" && corpus.approval !== null);
  const groups = spec.version === PROVIDER_SPEC_VERSION
    ? ["photos", "description"] as const
    : INPUT_GROUPS;
  const perGroup = spec.stage === "development"
    ? 10
    : spec.stage === "held_out"
    ? 40
    : 5;
  check(
    groups.every((group) =>
      selected.filter((c) => c.input.inputGroup === group).length === perGroup
    ),
  );
  check(selected.length === perGroup * groups.length);
  if (spec.stage !== "repeatability") {
    check(
      selected.length ===
        corpus.cases.filter((c) =>
          c.input.split === spec.split &&
          groups.some((g) => g === c.input.inputGroup)
        ).length,
    );
  }
}
/** Standalone admission deliberately cannot opt into controlled v2 live runs. */
export async function validateSelection(
  corpus: RunCorpus,
  spec: RunSpec,
  taxonomy: Taxonomy,
): Promise<void> {
  check(spec.version !== CANDIDATE_SPEC_VERSION);
  check(
    taxonomy.version !== "evaluation_taxonomy_v2" || spec.mode === "offline",
    "evaluation_measurement_live_pending",
  );
  await validateSelectionFacts(corpus, spec, taxonomy);
}
export async function validateLiveApproval(
  corpus: RunCorpus,
  spec: RunSpec,
  pricingValue: unknown,
  readinessValue: unknown,
  credential: string,
  now: number,
): Promise<{ pricing: EvaluationPricing; readiness: EvaluationReadiness }> {
  check(spec.mode === "live" && credential.length > 0);
  const pricing = parseEvaluationPricing(pricingValue),
    readiness = parseEvaluationReadiness(readinessValue);
  const openai = spec.profiles.some(isOpenAIProfile);
  check(
    spec.profiles.every((p) =>
      providerForProfile(p) === (openai ? "openai" : "gemini")
    ),
  );
  check(
    (pricing.version === "evaluation_openai_pricing_v1") === openai &&
      (readiness.version === "evaluation_openai_processor_v1") === openai,
  );
  if (readiness.version === "evaluation_openai_processor_v1") {
    check(readiness.inputPermission.corpusDigest === spec.corpusDigest);
    check(
      await fingerprintJson(readiness.inputPermission.caseIds.toSorted()) ===
        await fingerprintJson(spec.caseIds.toSorted()),
    );
  }
  check(
    await fingerprintJson(pricing) === spec.pricingDigest &&
      await fingerprintJson(readiness) === spec.readinessDigest,
  );
  check(
    await fingerprintRunCorpus(corpus) === spec.corpusDigest &&
      readiness.corpusDigest === spec.corpusDigest,
  );
  check(
    await fingerprintBytes(new TextEncoder().encode(credential)) ===
      readiness.credentialSha256,
  );
  check(
    !isSyntheticCorpus(corpus) && corpusRetention(corpus) !== null &&
      Date.parse(corpusRetention(corpus)!) > now,
  );
  check(
    Date.parse(readiness.reviewedAt) <= now &&
      now < Date.parse(readiness.expiresAt) &&
      Date.parse(readiness.reviewedAt) < Date.parse(readiness.expiresAt),
  );
  const age = now - Date.parse(pricing.retrievedAt);
  check(age >= 0 && age <= 7 * 86400000);
  return { pricing, readiness };
}

export const SDK_ENVIRONMENT = [
  "GOOGLE_SDK_NODE_LOGGING",
  "GOOGLE_GENAI_DEBUG",
  "WS_NO_BUFFER_UTIL",
  "WS_NO_UTF_8_VALIDATE",
  "GOOGLE_GENAI_USE_ENTERPRISE",
  "GOOGLE_GENAI_USE_VERTEXAI",
  "GOOGLE_CLOUD_PROJECT",
  "GOOGLE_CLOUD_LOCATION",
  "GOOGLE_VERTEX_BASE_URL",
  "GOOGLE_GEMINI_BASE_URL",
  "GOOGLE_API_KEY",
  "GEMINI_API_KEY",
] as const;
/** Require denied broad grants and allow only the reviewed host/key surfaces.
 * Querying permissions does not request or widen them. SDK override variables
 * must be readable AND unset so Deno's Node compatibility behaves predictably.
 */
export async function assertOfflinePermissions(): Promise<void> {
  check((await Deno.permissions.query({ name: "net" })).state === "denied");
  check((await Deno.permissions.query({ name: "env" })).state === "denied");
}
export async function liveCredential(
  provider: "gemini" | "openai" = "gemini",
): Promise<string> {
  check((await Deno.permissions.query({ name: "net" })).state !== "granted");
  check(
    (await Deno.permissions.query({
      name: "net",
      host: provider === "openai"
        ? "api.openai.com:443"
        : "generativelanguage.googleapis.com:443",
    })).state === "granted",
  );
  check((await Deno.permissions.query({ name: "env" })).state !== "granted");
  for (
    const name of [
      "SUPABASE_URL",
      "SUPABASE_SERVICE_ROLE_KEY",
      "R2_ACCESS_KEY_ID",
      "GOOGLE_APPLICATION_CREDENTIALS",
    ]
  ) {
    check(
      (await Deno.permissions.query({ name: "env", variable: name })).state ===
        "denied",
    );
  }
  if (provider === "openai") {
    for (
      const name of [
        ...SDK_ENVIRONMENT,
        "GEMINI_PAID_API_KEY",
        "OPENAI_API_KEY",
      ]
    ) {
      check(
        (await Deno.permissions.query({ name: "env", variable: name }))
          .state === "denied",
      );
    }
    const key = Deno.env.get("OPENAI_EVALUATION_API_KEY")?.trim();
    check(key && key.length <= 512 && !/\s/.test(key));
    return key;
  }
  for (const name of SDK_ENVIRONMENT) {
    check(
      (await Deno.permissions.query({ name: "env", variable: name })).state ===
        "granted",
    );
    check(!Deno.env.get(name));
  }
  const key = Deno.env.get("GEMINI_PAID_API_KEY")?.trim();
  check(key && key.length <= 512);
  return key;
}
