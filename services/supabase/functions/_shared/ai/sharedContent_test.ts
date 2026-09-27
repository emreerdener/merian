import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import type {
  AIExecutionAuthority,
  SpeciesContentAIRequest,
} from "./contracts.ts";
import { resolveAIClaim } from "./registry.ts";
import {
  assertSharedSpeciesContentSnapshot,
  prepareSharedSpeciesContent,
  sharedSpeciesContentKey,
} from "./sharedContent.ts";

const requests: SpeciesContentAIRequest[] = [
  {
    task: "species_overview",
    variant: "species_content",
    scientificName: "Synthetic species",
    locale: "en",
  },
  {
    task: "lookalikes",
    variant: "species_content",
    scientificName: "Synthetic species",
    taxonomy: {
      kingdom: "Animalia",
      order: "SyntheticOrder",
      family: "SyntheticFamily",
    },
  },
  {
    task: "group_tags",
    variant: "species_content",
    scientificName: "Synthetic species",
  },
];
const operation = {
  species_overview: "scan_overview_enrichment",
  lookalikes: "scan_lookalike_enrichment",
  group_tags: "scan_group_tag_enrichment",
};
function authority(
  request: SpeciesContentAIRequest,
  model = "gemini-2.5-flash",
): AIExecutionAuthority {
  return {
    kind: "user_request",
    userId: "synthetic-owner",
    permission: "google_gemini",
    operation: operation[request.task],
    reservation: {
      id: "synthetic-lease",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model,
    },
  };
}
Deno.test("shared content accepts actual baseline profiles but rejects unqualified configuration changes", () => {
  for (const request of requests) {
    for (const model of ["gemini-2.5-flash"]) {
      const snapshot = resolveAIClaim(request, authority(request, model));
      assertSharedSpeciesContentSnapshot(snapshot, request.task);
      for (
        const changed of [
          { ...snapshot, provider: "other-provider" },
          { ...snapshot, model: "unqualified-model" },
          { ...snapshot, model: "gemini-2.5-pro" },
          { ...snapshot, binding: "other_binding" },
          { ...snapshot, prompt: "unqualified_prompt" },
          { ...snapshot, schema: "unqualified_schema" },
          { ...snapshot, confidence: "unqualified_confidence" },
          { ...snapshot, extra: true },
          { ...snapshot, permission: null },
          { ...snapshot, policyVersion: 0 },
          { ...snapshot, contextKind: "unknown" },
          {
            ...snapshot,
            generation: { ...snapshot.generation, temperature: 0.2 },
          },
          { ...snapshot, generation: { ...snapshot.generation, seed: 42 } },
          {
            ...snapshot,
            generation: { ...snapshot.generation, thinkingBudget: 1024 },
          },
          {
            ...snapshot,
            generation: { ...snapshot.generation, maxOutputTokens: 500 },
          },
        ]
      ) {
        assertThrows(
          () => assertSharedSpeciesContentSnapshot(changed, request.task),
          Error,
          "ai_shared_content_profile_unqualified",
        );
      }
    }
    const publicClaim = resolveAIClaim(request, {
      kind: "service_job",
      task: request.task,
      purpose: "public_species_facts",
      jobId: "synthetic-job",
      attemptCount: 1,
      maxAttempts: 3,
      model: "gemini-2.5-flash",
    });
    assertSharedSpeciesContentSnapshot(publicClaim, request.task);
  }
});
Deno.test("unsupported shared locale is rejected before adapter preparation", () => {
  const request = { ...requests[0], locale: "fr" } as SpeciesContentAIRequest;
  let prepared = false;
  assertThrows(
    () =>
      prepareSharedSpeciesContent(request, authority(request), () => {
        prepared = true;
        throw new Error("must not prepare");
      }),
    Error,
    "ai_shared_content_profile_unqualified",
  );
  assertEquals(prepared, false);
});
Deno.test("singleflight identity includes task, canonical species, language and exact taxonomy evidence", () => {
  const keys = requests.map((request) =>
    sharedSpeciesContentKey(request, "synthetic-species-id")
  );
  assertEquals(new Set(keys).size, requests.length);
  assertNotEquals(
    keys[0],
    sharedSpeciesContentKey(requests[0], "other-species-id"),
  );
  assertNotEquals(
    keys[0],
    sharedSpeciesContentKey({
      ...requests[0],
      scientificName: "Different species",
    }, "synthetic-species-id"),
  );
  const lookalikes = requests[1] as Extract<
    SpeciesContentAIRequest,
    { task: "lookalikes" }
  >;
  assertNotEquals(
    keys[1],
    sharedSpeciesContentKey({
      ...lookalikes,
      taxonomy: { ...lookalikes.taxonomy, order: "NewOrder" },
    }, "synthetic-species-id"),
  );
  assertEquals(
    keys[1],
    sharedSpeciesContentKey({
      ...lookalikes,
      taxonomy: {
        family: "SyntheticFamily",
        order: "SyntheticOrder",
        kingdom: "Animalia",
      },
    }, "synthetic-species-id"),
  );
  assertThrows(() =>
    sharedSpeciesContentKey(
      { ...requests[0], locale: "fr" } as SpeciesContentAIRequest,
      "synthetic-species-id",
    )
  );
});
