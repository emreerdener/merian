import {
  assert,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const guardedRoutes = new Map<string, string[]>([
  ["../identify/index.ts", ["scan_identification"]],
  ["../identify-describe/index.ts", ["scan_identification"]],
  ["../identify-multimodal/index.ts", ["scan_identification"]],
  ["../audio-spec/index.ts", ["scan_audio_identification"]],
  [
    "../enrich-scan/index.ts",
    ["scan_overview_enrichment", "scan_lookalike_enrichment"],
  ],
  [
    "../insight-chat/index.ts",
    [
      "insight_chat_reply",
      "insight_chat_prompt_suggestions",
      "insight_chat_summary",
    ],
  ],
  ["../explore-post-chat/index.ts", ["explore_post_chat_reply"]],
  ["../share-scan-to-explore/index.ts", ["explore_audio_moderation"]],
  [
    "../request-community-identification/index.ts",
    ["explore_audio_moderation"],
  ],
  ["../update-explore-field-notes/index.ts", ["explore_audio_moderation"]],
]);

Deno.test("every public paid-model route declares a server quota operation", async () => {
  for (const [path, operations] of guardedRoutes) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(
      source,
      "reserveAIProviderCall",
      `${path} does not import the authoritative quota boundary`,
    );
    for (const operation of operations) {
      assertStringIncludes(
        source,
        `operation: "${operation}"`,
        `${path} is missing quota operation ${operation}`,
      );
    }
  }
});

Deno.test("database-selected models reach every paid provider family", async () => {
  for (
    const path of [
      "../identify/index.ts",
      "../identify-describe/index.ts",
      "../identify-multimodal/index.ts",
      "../audio-spec/index.ts",
      "../enrich-scan/index.ts",
      "../insight-chat/index.ts",
      "../explore-post-chat/index.ts",
      "../_shared/audioModeration.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assert(
      /reservation[.]model/.test(source),
      `${path} does not use the model selected by the quota policy`,
    );
  }

  const biology = await Deno.readTextFile(
    new URL("../_shared/biology.ts", import.meta.url),
  );
  assert(
    !/model(?:Name)?\s*=\s*"gemini-2[.]5-flash"/.test(biology),
    "public enrichment helpers must require an explicit policy-selected model",
  );
});

Deno.test("provider attempts consume quota while pre-provider no-ops can refund", async () => {
  for (
    const path of [
      "../identify/index.ts",
      "../identify-describe/index.ts",
      "../identify-multimodal/index.ts",
      "../audio-spec/index.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assert(
      /await quotaLease[.]commit[(][)];\s+const result = await _genAI[.]models[.]generateContent/
        .test(source),
      `${path} must commit immediately before dispatching paid provider work`,
    );
  }

  const multimodal = await Deno.readTextFile(
    new URL("../identify-multimodal/index.ts", import.meta.url),
  );
  assertStringIncludes(multimodal, "await quotaLease.refund();");

  const moderation = await Deno.readTextFile(
    new URL("../_shared/audioModeration.ts", import.meta.url),
  );
  assertStringIncludes(moderation, "await quotaLease?.refund();");
  assertStringIncludes(moderation, "await quotaLease?.commit();");

  const share = await Deno.readTextFile(
    new URL("../share-scan-to-explore/index.ts", import.meta.url),
  );
  assertStringIncludes(share, "deriveAIRequestId(");
  assertStringIncludes(share, "checksumSha256");
  assert(!share.includes("requestId: crypto.randomUUID()"));

  const communityRequest = await Deno.readTextFile(
    new URL("../request-community-identification/index.ts", import.meta.url),
  );
  assertStringIncludes(communityRequest, "deriveAIRequestId(");
  assertStringIncludes(communityRequest, "checksumSha256");
  assert(!communityRequest.includes("requestId: crypto.randomUUID()"));

  const exploreEdit = await Deno.readTextFile(
    new URL("../update-explore-field-notes/index.ts", import.meta.url),
  );
  assertStringIncludes(exploreEdit, "deriveAIRequestId(");
  assertStringIncludes(exploreEdit, "checksumSha256");
  assert(!exploreEdit.includes("requestId: crypto.randomUUID()"));
});

Deno.test("public dictionary fallback and webhook contain no hidden isolate authorization", async () => {
  const dictionary = await Deno.readTextFile(
    new URL("../species-dictionary/db.ts", import.meta.url),
  );
  assert(!dictionary.includes('import("../_shared/biology.ts")'));
  assert(!dictionary.includes("fetchModelSimilarSpecies"));

  const webhook = await Deno.readTextFile(
    new URL("../revenuecat-webhook/index.ts", import.meta.url),
  );
  assert(!webhook.includes("setTierCache"));
  assert(!webhook.includes("clearTierCache"));

  await assertRejects(
    () => Deno.stat(new URL("../_shared/tierCache.ts", import.meta.url)),
    Deno.errors.NotFound,
  );
});
