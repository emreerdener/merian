import { assertEquals, assertThrows } from "@std/assert";
import {
  assertGeminiContentDraft,
  buildGeminiContent,
} from "./geminiContent.ts";
import type { SpeciesContentAIRequest } from "./contracts.ts";
import { resolveAIClaim } from "./registry.ts";
import { geminiAdapter } from "./gemini.ts";

const request: SpeciesContentAIRequest = {
  task: "group_tags",
  variant: "species_content",
  scientificName: "Synthetic species",
};
Deno.test("species content validates closed provider schema and independent value limits", () => {
  const validate = (request: SpeciesContentAIRequest, value: unknown) =>
    assertGeminiContentDraft(
      value,
      buildGeminiContent(request).responseSchema,
      request.task,
    );
  validate(request, { group_tags: ["animal", "bird"] });
  for (
    const value of [{}, { group_tags: [1] }, {
      group_tags: ["animal"],
      extra: true,
    }, { group_tags: Array(6).fill("animal") }]
  ) assertThrows(() => validate(request, value));
  const similar: SpeciesContentAIRequest = {
    ...request,
    task: "lookalikes",
    taxonomy: null,
  };
  validate(similar, { similar_species: [] });
  const candidate = {
    scientific_name: "Synthetic lookalike",
    common_name: "Synthetic",
    reason: "Similar shape",
    visual_traits: ["shape"],
    confidence: .8,
  };
  validate(similar, { similar_species: [candidate] });
  for (
    const value of [{ similar_species: [{}] }, {
      similar_species: [{ ...candidate, confidence: 2 }],
    }, { similar_species: [candidate], extra: true }]
  ) assertThrows(() => validate(similar, value));
  const overview: SpeciesContentAIRequest = {
    ...request,
    task: "species_overview",
    locale: "en",
  };
  const data = {
    taxonomy: {
      kingdom: "Animalia",
      phylum: "Chordata",
      class: "Aves",
      order: "Synthetic",
      family: "Synthetic",
      genus: "Synthetic",
    },
    iucn_red_list_status: "not_evaluated",
    habitat_description: "Synthetic habitat",
    hazard_type: "none",
    colors: ["brown"],
  };
  validate(overview, data);
  for (
    const value of [{}, { ...data, hazard_type: "safe_to_eat" }, {
      ...data,
      taxonomy: {},
    }, { ...data, colors: [1] }]
  ) assertThrows(() => validate(overview, value));
});
Deno.test("SDK shared content persists response facts before strict success or error outcome", async () => {
  const names = [
    "GEMINI_PAID_API_KEY",
    "GOOGLE_GENAI_USE_VERTEXAI",
    "GOOGLE_GENAI_USE_ENTERPRISE",
    "GOOGLE_GEMINI_BASE_URL",
  ];
  const saved = new Map(names.map((name) => [name, Deno.env.get(name)]));
  const fetcher = globalThis.fetch;
  try {
    for (const name of names) Deno.env.delete(name);
    Deno.env.set("GEMINI_PAID_API_KEY", "synthetic-test-key");
    const snapshot = resolveAIClaim(request, {
      kind: "service_job",
      purpose: "public_species_facts",
      task: "group_tags",
      jobId: "synthetic-job",
      attemptCount: 1,
      maxAttempts: 5,
      model: "gemini-3.5-flash-lite",
    });
    for (
      const [body, expected] of [[{ group_tags: ["animal"] }, "success"], [{
        unexpected: true,
      }, "error"]] as const
    ) {
      const events: string[] = [];
      globalThis.fetch = () =>
        Promise.resolve(Response.json({
          modelVersion: snapshot.model,
          candidates: [{
            finishReason: "STOP",
            content: {
              role: "model",
              parts: [{
                text: JSON.stringify(body),
                thoughtSignature: "opaque",
              }],
            },
          }],
          usageMetadata: {
            promptTokenCount: 10,
            candidatesTokenCount: 2,
            thoughtsTokenCount: 3,
            cachedContentTokenCount: 0,
            toolUsePromptTokenCount: 0,
            totalTokenCount: 15,
          },
        }));
      const result = await geminiAdapter.prepare(request, snapshot)({
        beforeTransport: () => {
          events.push("dispatch");
          return Promise.resolve();
        },
        recordResponse: (receipt) => {
          assertEquals(receipt.usage?.totalTokens, 15);
          assertEquals(receipt.failure, null);
          events.push("receipt");
          return Promise.resolve();
        },
        recordApplicationOutcome: (outcome) => {
          events.push(outcome);
          return Promise.resolve();
        },
      });
      assertEquals(
        result.kind,
        expected === "success" ? "draft" : "invalid_output",
      );
      assertEquals(events, ["dispatch", "receipt", expected]);
    }
  } finally {
    globalThis.fetch = fetcher;
    for (const [name, value] of saved) {
      value === undefined ? Deno.env.delete(name) : Deno.env.set(name, value);
    }
  }
});
