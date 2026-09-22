import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  fetchGroupTags,
  fetchSimilarSpecies,
  fetchStaticEncyclopedicData,
} from "./biology.ts";

import { prepareAIExecution } from "./ai/production.ts";
import type { SpeciesContentAIRequest } from "./ai/contracts.ts";

function assertContent(
  actual: { execution?: Record<string, unknown> } | null,
  expected: Record<string, unknown>,
) {
  assert(actual);
  const { execution, ...value } = actual;
  assert(execution);
  assertEquals(execution.ai_provider, "gemini");
  assertEquals(execution.ai_binding, "gemini_baseline_v1");
  assert(typeof execution.ai_provider_duration_ms === "number");
  assertEquals(value, expected);
}

// Exercise the preserved helpers through the shared adapter and installed SDK.
// All HTTP is intercepted. The system label cannot trigger user analytics.
Deno.test("biology helpers preserve their Gemini requests and results", async (t) => {
  const environment = [
    "GEMINI_PAID_API_KEY",
    "GOOGLE_GENAI_USE_VERTEXAI",
    "GOOGLE_GENAI_USE_ENTERPRISE",
    "GOOGLE_GEMINI_BASE_URL",
  ];
  const savedEnvironment = new Map(
    environment.map((key) => [key, Deno.env.get(key)]),
  );
  const originalFetch = globalThis.fetch;
  const originalTimeout = globalThis.setTimeout;
  const originalError = console.error;
  const timers: ReturnType<typeof setTimeout>[] = [];
  const system = "system:provider-baseline";
  const species = "Synthetic species";
  const usage = {
    promptTokenCount: 12,
    candidatesTokenCount: 8,
    thoughtsTokenCount: 3,
    totalTokenCount: 23,
  };
  const overview = {
    taxonomy: {
      kingdom: null,
      phylum: null,
      class: null,
      order: null,
      family: null,
      genus: null,
    },
    iucn_red_list_status: "not_evaluated",
    habitat_description: "Synthetic habitat",
    hazard_type: "none",
    colors: ["green"],
  };
  let selectedModel = "gemini-2.5-flash";
  function prepare(
    input:
      | Omit<
        Extract<SpeciesContentAIRequest, { task: "species_overview" }>,
        "variant" | "scientificName"
      >
      | Omit<
        Extract<SpeciesContentAIRequest, { task: "lookalikes" }>,
        "variant" | "scientificName"
      >
      | { task: "group_tags" },
    service = false,
  ) {
    const operations = {
      species_overview: "scan_overview_enrichment",
      lookalikes: "scan_lookalike_enrichment",
      group_tags: "scan_group_tag_enrichment",
    };
    return prepareAIExecution(
      { ...input, variant: "species_content", scientificName: species },
      service
        ? {
          kind: "service_job",
          task: input.task,
          purpose: "public_species_facts",
          jobId: "synthetic-job",
          attemptCount: 1,
          maxAttempts: 5,
          model: selectedModel,
        }
        : {
          kind: "user_request",
          userId: "synthetic-owner",
          permission: "google_gemini",
          operation: operations[input.task],
          reservation: {
            id: "synthetic-reservation",
            requestId: "synthetic-request",
            attemptCount: 1,
            policyVersion: 1,
            model: selectedModel,
          },
        },
    );
  }
  let requests = 0;
  let inspect: (body: Record<string, unknown>) => void = () => {};
  let respond: () => Response;

  function reply(
    value: unknown,
    includeUsage = true,
    finishReason = "STOP",
  ): Response {
    return Response.json({
      candidates: [{
        content: {
          role: "model",
          parts: [{ text: JSON.stringify(value) }],
        },
        finishReason,
      }],
      ...(includeUsage ? { usageMetadata: usage } : {}),
    });
  }

  function inspectTask(
    body: Record<string, unknown>,
    maxOutputTokens: number,
    required: string[],
  ): string {
    const config = body.generationConfig as Record<string, unknown>;
    assertEquals(
      Object.keys(config).sort(),
      [
        "maxOutputTokens",
        "responseMimeType",
        "responseSchema",
        "temperature",
        "thinkingConfig",
      ].sort(),
    );
    assertEquals(body.safetySettings, undefined);
    assertEquals(config.temperature, 0.1);
    assertEquals(config.maxOutputTokens, maxOutputTokens);
    assertEquals(config.thinkingConfig, { thinkingBudget: 0 });
    assertEquals(config.responseMimeType, "application/json");
    const schema = config.responseSchema as Record<string, unknown>;
    assertEquals(schema.required, required);
    const instruction = body.systemInstruction as {
      parts: { text: string }[];
    };
    assertEquals(instruction.parts.length, 1);
    return instruction.parts[0].text;
  }

  async function step(name: string, run: () => Promise<void>) {
    await t.step(name, async () => {
      const before = requests;
      try {
        await run();
        assertEquals(requests - before, 1);
      } finally {
        for (const timer of timers.splice(0)) clearTimeout(timer);
      }
    });
  }

  try {
    for (const key of environment) Deno.env.delete(key);
    Deno.env.set("GEMINI_PAID_API_KEY", "synthetic-test-key");
    globalThis.fetch = (input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      assertEquals(url.origin, "https://generativelanguage.googleapis.com");
      assertEquals(
        url.pathname,
        `/v1beta/models/${selectedModel}:generateContent`,
      );
      assertEquals(init?.method, "POST");
      assert(init?.signal instanceof AbortSignal);
      assertEquals(typeof init.body, "string");
      requests++;
      inspect(JSON.parse(init.body as string));
      return Promise.resolve(respond());
    };
    globalThis.setTimeout = ((
      handler: Parameters<typeof setTimeout>[0],
      timeout?: number,
      ...args: unknown[]
    ) => {
      const timer = originalTimeout(handler, timeout, ...args);
      timers.push(timer);
      return timer;
    }) as typeof setTimeout;

    await step(
      "overview preserves locale, schema, token budget and usage",
      async () => {
        inspect = (body) => {
          const instruction = inspectTask(body, 1500, [
            "taxonomy",
            "iucn_red_list_status",
            "habitat_description",
            "hazard_type",
            "colors",
          ]);
          assert(instruction.includes("locale: fr."));
          assertEquals(body.contents, [{
            role: "user",
            parts: [{ text: `Generate metadata for the species: ${species}` }],
          }]);
        };
        respond = () => reply(overview);
        assertContent(
          await fetchStaticEncyclopedicData(
            system,
            species,
            prepare({ task: "species_overview", locale: "fr" }),
          ),
          { ...overview, usage },
        );
      },
    );

    await step(
      "lookalikes forward the selected model and normalize the result",
      async () => {
        selectedModel = "gemini-2.5-pro";
        inspect = (body) => {
          const instruction = inspectTask(body, 300, ["similar_species"]);
          assert(instruction.includes("Kingdom: Animalia, Order: Lepidoptera"));
          assertEquals(body.contents, [{
            role: "user",
            parts: [{
              text:
                `Identify up to 3 genuine lookalike species for: ${species} (Kingdom: Animalia, Order: Lepidoptera)`,
            }],
          }]);
        };
        respond = () =>
          reply({
            similar_species: [{
              scientific_name: "Synthetic lookalike",
              common_name: "",
              reason: "  Shared   markings  ",
              visual_traits: ["Spots", " spots ", "", 4, " Pale   wings "],
              confidence: 1.2,
            }, {
              scientific_name: "Second synthetic lookalike",
              confidence: -0.2,
            }],
          });
        assertContent(
          await fetchSimilarSpecies(
            system,
            species,
            prepare({
              task: "lookalikes",
              taxonomy: {
                kingdom: " Animalia ",
                class: "unknown",
                order: "Lepidoptera",
                family: null,
              },
            }),
          ),
          {
            similar_species: [{
              scientific_name: "Synthetic lookalike",
              common_name: null,
              reason: "Shared markings",
              visual_traits: ["Spots", "Pale wings"],
              confidence: 1,
            }, {
              scientific_name: "Second synthetic lookalike",
              common_name: null,
              reason: null,
              visual_traits: [],
              confidence: 0,
            }],
            usage,
          },
        );
      },
    );

    await step(
      "group tags preserve service usage attribution without user quota",
      async () => {
        selectedModel = "gemini-2.5-flash";
        const ledgerCalls: { name: string; args: Record<string, unknown> }[] =
          [];
        const database = {
          rpc(name: string, args: Record<string, unknown>) {
            ledgerCalls.push({ name, args });
            return {
              abortSignal: () => Promise.resolve({ data: null, error: null }),
            };
          },
        } as unknown as SupabaseClient;
        inspect = (body) => {
          assert(inspectTask(body, 100, ["group_tags"]).length > 0);
          assertEquals(body.contents, [{
            role: "user",
            parts: [{ text: `Group tags for: ${species}` }],
          }]);
        };
        respond = () => reply({ group_tags: ["animal", "insect"] });
        assertContent(
          await fetchGroupTags(
            system,
            species,
            prepare({ task: "group_tags" }, true),
            database,
          ),
          { group_tags: ["animal", "insect"], usage },
        );
        assertEquals(ledgerCalls.map((call) => call.name), [
          "record_ai_usage_event",
        ]);
        const recorded = ledgerCalls[0].args;
        assertEquals(recorded.p_operation, "scan_group_tag_enrichment");
        assertEquals(recorded.p_model, selectedModel);
        assertEquals(recorded.p_user_id, null);
        assertEquals(recorded.p_input_modality, "text");
        assertEquals(recorded.p_total_tokens, usage.totalTokenCount);
      },
    );

    await step("missing provider usage remains unknown", async () => {
      inspect = () => {};
      respond = () => reply(overview, false);
      const result = await fetchStaticEncyclopedicData(
        system,
        species,
        prepare({ task: "species_overview", locale: "en" }),
      );
      const { execution, ...legacyResult } = result;
      assertEquals(legacyResult, overview);
      assertEquals(execution?.ai_task, "species_overview");
      assertEquals(execution?.ai_provider, "gemini");
      assertEquals(result.usage, undefined);
    });

    const callers = [
      {
        name: "overview",
        task: "species_overview",
        limit: 1500,
        required: [
          "taxonomy",
          "iucn_red_list_status",
          "habitat_description",
          "hazard_type",
          "colors",
        ],
        text: `Generate metadata for the species: ${species}`,
        draft: overview,
        call: () =>
          fetchStaticEncyclopedicData(
            system,
            species,
            prepare({ task: "species_overview", locale: "en" }),
          ),
      },
      {
        name: "lookalikes",
        task: "lookalikes",
        limit: 300,
        required: ["similar_species"],
        text: `Identify up to 3 genuine lookalike species for: ${species}`,
        draft: { similar_species: [] },
        call: () =>
          fetchSimilarSpecies(
            system,
            species,
            prepare({ task: "lookalikes", taxonomy: null }),
          ),
      },
      {
        name: "group tags",
        task: "group_tags",
        limit: 100,
        required: ["group_tags"],
        text: `Group tags for: ${species}`,
        draft: { group_tags: ["animal"] },
        call: () =>
          fetchGroupTags(system, species, prepare({ task: "group_tags" })),
      },
    ];
    for (const model of ["gemini-2.5-flash", "gemini-2.5-pro"]) {
      selectedModel = model;
      for (const caller of callers) {
        await step(
          `${caller.name} preserves the complete ${model} generation options`,
          async () => {
            inspect = (body) => {
              inspectTask(body, caller.limit, caller.required);
              assertEquals(body.contents, [{
                role: "user",
                parts: [{ text: caller.text }],
              }]);
            };
            respond = () => reply(caller.draft);
            const result = await caller.call();
            assertEquals(result?.execution?.ai_prompt, `${caller.task}_v1`);
          },
        );
      }
    }
    // Expected synthetic failures are asserted, not logged as diagnostics.
    console.error = () => {};
    for (const caller of callers) {
      await step(
        `${caller.name} preserves legacy JSON parsing with non-STOP finish`,
        async () => {
          inspect = () => {};
          respond = () => reply(caller.draft, true, "MAX_TOKENS");
          const result = await caller.call();
          assertEquals(result?.execution?.ai_outcome, "draft");
        },
      );
      await step(
        `${caller.name} does not gain identification's first-part fallback`,
        async () => {
          respond = () =>
            Response.json({
              candidates: [{
                content: {
                  role: "model",
                  parts: [{
                    thought: true,
                    text: JSON.stringify(caller.draft),
                  }],
                },
                finishReason: "STOP",
              }],
            });
          await assertRejects(caller.call, Error, "ai_content_invalid_output");
        },
      );
    }
    for (const caller of callers) {
      await step(
        `${caller.name} rejects unusable output without retry`,
        async () => {
          respond = () =>
            Response.json({
              candidates: [{
                content: {
                  role: "model",
                  parts: [{ text: "unusable synthetic output" }],
                },
                finishReason: "STOP",
              }],
            });
          await assertRejects(caller.call, Error, "ai_content_invalid_output");
        },
      );
      await step(
        `${caller.name} propagates provider failure without retry`,
        async () => {
          respond = () =>
            Response.json({
              error: {
                code: 503,
                message: "Synthetic outage",
                status: "UNAVAILABLE",
              },
            }, { status: 503 });
          await assertRejects(caller.call, Error);
        },
      );
    }
  } finally {
    globalThis.fetch = originalFetch;
    globalThis.setTimeout = originalTimeout;
    console.error = originalError;
    for (const timer of timers) clearTimeout(timer);
    for (const [key, value] of savedEnvironment) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
});
