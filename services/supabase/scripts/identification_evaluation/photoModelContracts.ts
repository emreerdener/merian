/** A new preparation contract; historical evaluation/run IDs remain closed. */
import {
  OPENAI_PHOTO_MODEL_PROFILES,
  OPENAI_PHOTO_MODELS,
  type OpenAIPhotoBaselineModelProfile,
  type OpenAIPhotoModelProfile,
} from "../../functions/_shared/ai/openaiPhotoModels.ts";
import { OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE } from "../../functions/_shared/ai/openaiLunaEvidenceLimits.ts";
import { type FactCard, parseFactCards } from "./explanationContracts.ts";
import { hash, number, timestamp, unique } from "./runContracts.ts";
import {
  array,
  fields,
  id,
  requireCondition as check,
  token,
} from "./validation.ts";

export interface PhotoModelPlan {
  version:
    | "photo_model_plan_v1"
    | "photo_model_plan_v2"
    | "photo_model_plan_v3";
  id: string;
  corpusDigest: string;
  taxonomyDigest: string;
  factsDigest: string;
  pricingDigest: string;
  screenCaseIds: string[];
  challengeCaseIds: string[];
  maxCalls: 18;
  attemptsPerAssignment: 1;
  budgetUsd: number;
  inputApproval: null | {
    provider: "openai";
    corpusDigest: string;
    caseIds: string[];
    recordRef: string;
  };
}
export function parsePhotoModelPlan(value: unknown): PhotoModelPlan {
  const v = fields(value, [
    "version",
    "id",
    "corpusDigest",
    "taxonomyDigest",
    "factsDigest",
    "pricingDigest",
    "screenCaseIds",
    "challengeCaseIds",
    "maxCalls",
    "attemptsPerAssignment",
    "budgetUsd",
    "inputApproval",
  ]);
  check(
    v.version === "photo_model_plan_v1" ||
      v.version === "photo_model_plan_v2" ||
      v.version === "photo_model_plan_v3",
  );
  token(v.id);
  for (
    const key of [
      "corpusDigest",
      "taxonomyDigest",
      "factsDigest",
      "pricingDigest",
    ]
  ) hash(v[key]);
  const screen = array(v.screenCaseIds, 6, 6),
    challenge = array(v.challengeCaseIds, 6, 6);
  const cases = [...screen, ...challenge];
  cases.forEach((c) => id(c, "c"));
  unique(cases);
  check(v.maxCalls === 18 && v.attemptsPerAssignment === 1);
  // A plan is not spending authority; live execution also requires a bound approval.
  number(v.budgetUsd, 0.01, v.version === "photo_model_plan_v1" ? 5 : 40);
  if (v.inputApproval !== null) {
    const a = fields(v.inputApproval, [
      "provider",
      "corpusDigest",
      "caseIds",
      "recordRef",
    ]);
    check(a.provider === "openai" && a.corpusDigest === v.corpusDigest);
    token(a.recordRef);
    const approved = array(a.caseIds, 12, 12);
    approved.forEach((c) => id(c, "c"));
    unique(approved);
    check(approved.every((c) => cases.includes(c)));
  }
  return structuredClone(v) as unknown as PhotoModelPlan;
}

export function parsePhotoModelFacts(value: unknown): {
  version: "photo_model_facts_v1";
  cards: FactCard[];
} {
  const v = fields(value, ["version", "cards"]);
  check(v.version === "photo_model_facts_v1");
  // Reuse the reviewed card semantics without broadening the historical eight-card contract.
  const cards = array(v.cards, 12, 12).map((card) =>
    parseFactCards({ version: "explanation_facts_v1", cards: [card] }).cards[0]
  );
  unique(cards.map((c) => c.caseId));
  return { version: "photo_model_facts_v1", cards: structuredClone(cards) };
}

/** Full-context reservation, not expected spend or a measured per-scan price. */
export const PHOTO_MODEL_TOKEN_CEILINGS = {
  input: 1_050_000,
  output: 8_192,
} as const;
const PRICE_FLOORS = {
  // Includes the largest published long-context/cache-write input rate.
  openai_photo_luna_low_v1: { input: 0.25, output: 0.75 },
  openai_photo_sol_low_v1: { input: 5, output: 15 },
} as const;
interface ProfilePrice {
  model: string;
  source: string;
  inputCeilingUsdPerMillion: number;
  outputCeilingUsdPerMillion: number;
}
export interface PhotoModelPricing {
  version: "photo_model_pricing_v1";
  retrievedAt: string;
  reviewRef: string;
  currency: "USD";
  billing: "paid_standard_synchronous";
  profiles: Record<OpenAIPhotoBaselineModelProfile, ProfilePrice>;
}
export function parsePhotoModelPricing(value: unknown): PhotoModelPricing {
  const v = fields(value, [
    "version",
    "retrievedAt",
    "reviewRef",
    "currency",
    "billing",
    "profiles",
  ]);
  check(
    v.version === "photo_model_pricing_v1" && v.currency === "USD" &&
      v.billing === "paid_standard_synchronous",
  );
  timestamp(v.retrievedAt);
  token(v.reviewRef);
  const profiles = fields(v.profiles, OPENAI_PHOTO_MODEL_PROFILES);
  for (const profile of OPENAI_PHOTO_MODEL_PROFILES) {
    const p = fields(profiles[profile], [
      "model",
      "source",
      "inputCeilingUsdPerMillion",
      "outputCeilingUsdPerMillion",
    ]);
    check(
      p.model === OPENAI_PHOTO_MODELS[profile] &&
        p.source === `https://developers.openai.com/api/docs/models/${p.model}`,
    );
    number(p.inputCeilingUsdPerMillion, PRICE_FLOORS[profile].input, 100);
    number(p.outputCeilingUsdPerMillion, PRICE_FLOORS[profile].output, 100);
  }
  return structuredClone(v) as unknown as PhotoModelPricing;
}
/** Prompt variants of the exact same model retain the reviewed model tariff. */
export function photoModelPrice(
  profile: OpenAIPhotoModelProfile,
  pricing: PhotoModelPricing,
): ProfilePrice {
  const billingProfile = profile === OPENAI_LUNA_EVIDENCE_LIMITS_PROFILE
    ? "openai_photo_luna_low_v1"
    : profile;
  const price = pricing.profiles[billingProfile];
  check(price !== undefined && price.model === OPENAI_PHOTO_MODELS[profile]);
  return price;
}
export function photoModelReservationNanoUsd(
  profile: OpenAIPhotoModelProfile,
  pricing: PhotoModelPricing,
): number {
  const p = photoModelPrice(profile, pricing);
  return Math.ceil(
    (PHOTO_MODEL_TOKEN_CEILINGS.input * p.inputCeilingUsdPerMillion +
      PHOTO_MODEL_TOKEN_CEILINGS.output * p.outputCeilingUsdPerMillion) * 1000,
  );
}
