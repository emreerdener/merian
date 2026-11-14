import type { FrozenGeminiSmokeCase } from "./geminiSmoke.ts";
import {
  GEMINI_CANDIDATE_PROFILES,
  GEMINI_PROFILE_VERSION,
} from "./geminiProfiles.ts";
import type { AIRequest, SpeciesContentAIRequest } from "./contracts.ts";
import { identificationInputProfile } from "./identificationInput.ts";
import { decodeBase64 } from "../encoding.ts";

const syntheticId = "00000000-0000-4000-8000-000000000001";
const system =
  "You are a nature field assistant. Use only the supplied synthetic observation. Give one short factual sentence. Return the required JSON, with is_refusal false and refusal_reason null.";
const question =
  "Synthetic observation: a plant has a green leaf. What color is the leaf?";
// Public-domain synthetic 1x1 PNG. No private media, location or user material.
const png =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j16kAAAAASUVORK5CYII=";
export async function geminiSmokeDigest(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(
    (v) => v.toString(16).padStart(2, "0"),
  ).join("");
}
/** Closed server catalog. Callers choose identifiers only, never inputs or settings.
 * Bundle identity additionally binds builders, parsers and adapter implementation. */
export async function geminiSmokeCatalog(): Promise<
  ReadonlyMap<string, FrozenGeminiSmokeCase>
> {
  const cases: FrozenGeminiSmokeCase[] = [];
  async function add(
    id: string,
    operation: keyof typeof GEMINI_CANDIDATE_PROFILES,
    input: unknown,
    execute: FrozenGeminiSmokeCase["execute"],
  ) {
    const profile = GEMINI_CANDIDATE_PROFILES[operation];
    // At most 16K synthetic input tokens, full output, Jan-2027 upper tariff.
    // This is reservation evidence, not a claim about actual billed usage.
    const reservationMicrousd = Math.ceil(
      16384 * (profile.model === "gemini-3.8-flash" ? 1.5 : 0.3) +
        profile.maxOutputTokens *
          (profile.model === "gemini-3.8-flash" ? 7.5 : 2.5),
    );
    cases.push(
      Object.freeze({
        id,
        model: profile.model,
        reservationMicrousd,
        digest: await geminiSmokeDigest({
          version: 1,
          id,
          profileVersion: GEMINI_PROFILE_VERSION,
          profile,
          input,
          reservationMicrousd,
        }),
        execute,
      }),
    );
  }
  const requests: AIRequest[] = [
    {
      task: "identify",
      variant: "description_compat",
      evidence: [{
        kind: "text",
        source: "description",
        order: 0,
        text:
          "A synthetic nature description: a broad green leaf. Evidence is insufficient for species identification; express uncertainty.",
      }],
    },
    {
      task: "identify",
      variant: "multimodal",
      evidence: [{
        kind: "text",
        source: "observation_context",
        order: 0,
        text:
          "Synthetic test: a broad green leaf, no location or other evidence. Express uncertainty.",
      }],
      capture: {
        hasVideo: false,
        videoClipCount: 0,
        declaredVideoFrameCount: 0,
        videoInferenceFrameCount: 0,
      },
    },
  ];
  for (const request of requests) {
    await add(
      `identify_${request.variant}`,
      "identify",
      request,
      async (hooks) => {
        const { prepareAIExecution } = await import("./production.ts");
        const result = await prepareAIExecution(request, {
          kind: "user_request",
          userId: syntheticId,
          permission: "google_gemini",
          operation: "scan_identification",
          reservation: {
            id: syntheticId,
            requestId: syntheticId,
            attemptCount: 1,
            policyVersion: 1,
            model: "gemini-3.8-flash",
            tier: { effective_tier: "pro" },
            assignment: {
              provider: "gemini",
              binding: "gemini_generation3_v1",
              permission: "google_gemini",
              inputProfile: identificationInputProfile(request),
            },
          },
        }, hooks).invoke();
        if (result.kind !== "draft") {
          throw new Error("gemini_smoke_answer_invalid");
        }
      },
    );
  }
  const contents: SpeciesContentAIRequest[] = [
    {
      task: "species_overview",
      variant: "species_content",
      scientificName: "Bellis perennis",
      locale: "en",
    },
    {
      task: "lookalikes",
      variant: "species_content",
      scientificName: "Bellis perennis",
      taxonomy: {
        kingdom: "Plantae",
        class: "Magnoliopsida",
        order: "Asterales",
        family: "Asteraceae",
      },
    },
    {
      task: "group_tags",
      variant: "species_content",
      scientificName: "Bellis perennis",
    },
  ];
  for (const request of contents) {
    await add(request.task, request.task, request, async (hooks) => {
      const { prepareAIExecution } = await import("./production.ts");
      const result = await prepareAIExecution(request, {
        kind: "service_job",
        task: request.task,
        purpose: "public_species_facts",
        jobId: syntheticId,
        attemptCount: 1,
        maxAttempts: 1,
        model: "gemini-3.5-flash-lite",
      }, hooks).invoke();
      if (result.kind !== "draft") {
        throw new Error("gemini_smoke_answer_invalid");
      }
    });
  }
  await add(
    "field_chat_sdk",
    "field_chat",
    { system, question },
    async (hooks) => {
      const { generateGeminiContent } = await import("../gemini.ts");
      const { buildFieldChatReplyRequest } = await import(
        "../fieldChat/reply.ts"
      );
      const { decodeProtectedChatProvider } = await import(
        "../../insight-chat/protectedProvider.ts"
      );
      const result = await generateGeminiContent(
        buildFieldChatReplyRequest(system, question, "gemini-3.5-flash-lite"),
        hooks,
      );
      // Same closed application decoder as protected production replies.
      decodeProtectedChatProvider({
        modelVersion: result.modelVersion,
        usageMetadata: result.usageMetadata,
        candidates: [{
          finishReason: "STOP",
          content: { role: "model", parts: [{ text: result.text }] },
        }],
      }, "gemini-3.5-flash-lite");
    },
  );
  await add(
    "field_chat_rest",
    "field_chat",
    { system, question },
    async (hooks) => {
      const { prepareProtectedChatProvider } = await import(
        "../../insight-chat/protectedProvider.ts"
      );
      await prepareProtectedChatProvider(
        system,
        question,
        "gemini-3.5-flash-lite",
        { transport: hooks },
      )(AbortSignal.timeout(90000));
    },
  );
  await add(
    "photo_moderation_rest",
    "photo_moderation",
    { png },
    async (hooks) => {
      const bytes = decodeBase64(png);
      const sha256 = [
        ...new Uint8Array(
          await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
        ),
      ].map((v) => v.toString(16).padStart(2, "0")).join("");
      const { preparePublicationPhotoClassifier } = await import(
        "../analysisHistory/photoClassifier.ts"
      );
      const prepared = await preparePublicationPhotoClassifier({
        media_id: syntheticId,
        object_id: "00000000-0000-4000-8000-000000000002",
        content_type: "image/png",
        byte_count: bytes.length,
        sha256,
      }, {
        model: "gemini-3.5-flash-lite",
        readSource: () => Promise.resolve(bytes),
        transport: hooks,
      });
      await prepared.invoke();
    },
  );
  return new Map(cases.map((c) => [c.id, c]));
}
