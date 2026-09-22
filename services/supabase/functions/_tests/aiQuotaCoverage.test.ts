import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "@std/assert";

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
  [
    "../species-dictionary-chat/index.ts",
    ["species_dictionary_chat_reply"],
  ],
  ["../species-discovery-search/index.ts", ["species_discovery_search"]],
  ["../share-scan-to-explore/index.ts", ["explore_audio_moderation"]],
  [
    "../request-community-identification/index.ts",
    ["explore_audio_moderation"],
  ],
  ["../update-explore-field-notes/index.ts", ["explore_audio_moderation"]],
]);

async function runtimeTypeScriptFiles(directory: URL): Promise<URL[]> {
  const files: URL[] = [];
  for await (const entry of Deno.readDir(directory)) {
    const child = new URL(
      `${entry.name}${entry.isDirectory ? "/" : ""}`,
      directory,
    );
    if (entry.isDirectory) {
      files.push(...await runtimeTypeScriptFiles(child));
    } else if (entry.isFile && entry.name.endsWith(".ts")) {
      files.push(child);
    }
  }
  return files;
}

Deno.test("provider dispatch and SDK imports stay within the adapter and deferred allowlist", async () => {
  const supabaseRoot = new URL("../../", import.meta.url);
  const dispatchFiles: string[] = [];
  const sdkFiles: string[] = [];

  const sources = (await Promise.all(
    ["functions/", "scripts/"].map((directory) =>
      runtimeTypeScriptFiles(new URL(directory, supabaseRoot))
    ),
  )).flat();
  for (const file of sources) {
    const relativePath = decodeURIComponent(
      file.pathname.slice(supabaseRoot.pathname.length),
    );
    if (
      relativePath.startsWith("functions/_tests/") ||
      /(?:^|\/)[^/]*(?:_test|[.]test)[.]ts$/.test(relativePath)
    ) {
      continue;
    }
    const source = await Deno.readTextFile(file);
    if (/\.generateContent\s*\(/.test(source)) {
      dispatchFiles.push(relativePath);
    }
    if (source.includes('from "@google/genai"')) sdkFiles.push(relativePath);
  }

  assertEquals(dispatchFiles.sort(), [
    "functions/_shared/ai/gemini.ts",
    "functions/_shared/audioModeration.ts",
    "functions/explore-post-chat/index.ts",
    "functions/insight-chat/index.ts",
    "functions/species-dictionary-chat/index.ts",
    "functions/species-discovery-search/provider.ts",
    "scripts/benchmark_ai_boundary.ts",
    "scripts/evaluate_field_chat_answers.ts",
  ]);
  assertEquals(sdkFiles.sort(), [
    "functions/_shared/ai/gemini.ts",
    "functions/_shared/ai/geminiContent.ts",
    "functions/_shared/fieldChatReply.ts",
    "functions/_shared/gemini.ts",
    "functions/_shared/identify/googleSchema.ts",
    "functions/_shared/identify/schema.ts",
    "functions/identify-describe/schema.ts",
    "functions/insight-chat/index.ts",
  ]);
  const evaluator = await Deno.readTextFile(
    new URL("scripts/evaluate_field_chat_answers.ts", supabaseRoot),
  );
  assertStringIncludes(evaluator, "if (import.meta.main)");
  assert(
    /if \(Deno.args.length !== 1 \|\| Deno.args\[0\] !== "--live"\) \{[\s\S]*?Deno.exit\(2\);/
      .test(evaluator),
  );
  assert(
    /if \(!Deno.env.get\("GEMINI_PAID_API_KEY"\)\?\.trim\(\)\) \{[\s\S]*?Deno.exit\(2\);/
      .test(evaluator),
  );
  assert(
    evaluator.indexOf('Deno.args[0] !== "--live"') <
      evaluator.indexOf("_genAI.models.generateContent"),
  );
  const benchmark = await Deno.readTextFile(
    new URL("scripts/benchmark_ai_boundary.ts", supabaseRoot),
  );
  assertStringIncludes(benchmark, "if (import.meta.main) await main();");
  assert(
    /if \(\(await Deno.permissions.query\(\{ name: "net" \}\)\)\.state !== "denied"\) \{\s*throw new Error\(/
      .test(benchmark),
  );
  assert(
    benchmark.indexOf('name: "net"') <
      benchmark.indexOf("_genAI.models.generateContent"),
  );
});

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
      "../_shared/groupTagQuota.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assert(
      /reservation[.]model|reservation: quotaLease[.]reservation/.test(source),
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
    const invocation =
      /await quotaLease[.]commit[(][)];\s*providerAttempted = true;\s*(?:const providerStart = performance[.]now[(][)];\s*)?result = await execution[.]invoke[(][)]/;
    assert(
      invocation.test(source),
      `${path} must commit immediately before dispatching paid provider work`,
    );
    assertStringIncludes(
      source,
      "await quotaLease.fail();",
      `${path} must make a charged provider failure safely retryable`,
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
  assertStringIncludes(moderation, "await quotaLease.fail();");

  for (
    const path of [
      "../insight-chat/index.ts",
      "../explore-post-chat/index.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(source, "waitForFieldChatRequestCompletion(");
    assertStringIncludes(source, "fieldChatUserMessageForRequest(");
    assertStringIncludes(source, '"ai_request_already_completed"');
    assertStringIncludes(source, '"ai_request_in_progress"');
    assertStringIncludes(source, '"X-Merian-Idempotent-Replay"');
    assertStringIncludes(source, '"field_chat_send_in_progress"');
    assertStringIncludes(source, '"field_chat_idempotency_conflict"');
    assertStringIncludes(source, "requestId: clientMessageId");
    assertStringIncludes(source, ").toLowerCase();");
    assertStringIncludes(source, "sendsTodayAfterRequest");
    assertStringIncludes(source, "await quotaLease?.fail();");
  }

  const fieldChatResponse = await Deno.readTextFile(
    new URL("../_shared/fieldChatResponse.ts", import.meta.url),
  );
  assertStringIncludes(
    fieldChatResponse,
    "deriveFieldChatAssistantMessageId(",
  );
  assertStringIncludes(
    fieldChatResponse,
    "merian-field-chat-assistant-v1:",
  );

  for (
    const path of [
      "../insight-chat/db.ts",
      "../explore-post-chat/db.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(source, "deriveFieldChatAssistantMessageId(");
    assertStringIncludes(source, "assistantMessageId");
    assertStringIncludes(source, 'error.code === "23505"');
    assertStringIncludes(source, "reserveFieldChatSend<");
  }

  const fieldChatReservation = await Deno.readTextFile(
    new URL("../_shared/fieldChatReservation.ts", import.meta.url),
  );
  assertStringIncludes(fieldChatReservation, '"reserve_field_chat_send"');
  assertStringIncludes(
    fieldChatReservation,
    "message.message_text === input.messageText",
  );
  assertStringIncludes(
    fieldChatReservation,
    "canonicalUuid(message.client_message_id)",
  );
  assertStringIncludes(
    fieldChatReservation,
    '"field_chat_idempotency_conflict"',
  );
  assertStringIncludes(
    fieldChatReservation,
    '"recover_stale_field_chat_quota"',
  );

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

Deno.test("migrated provider composition is fixed to Gemini and excludes test providers", async () => {
  const source = await Deno.readTextFile(
    new URL("../identify-describe/index.ts", import.meta.url),
  );
  const production = await Deno.readTextFile(
    new URL("../_shared/ai/production.ts", import.meta.url),
  );
  const multimodal = await Deno.readTextFile(
    new URL("../identify-multimodal/index.ts", import.meta.url),
  );
  const remaining = await Promise.all(
    ["identify", "audio-spec", "enrich-scan"].map((name) =>
      Deno.readTextFile(new URL(`../${name}/index.ts`, import.meta.url))
    ),
  );
  for (const route of [source, multimodal, ...remaining]) {
    assertStringIncludes(route, 'from "../_shared/ai/production.ts"');
    assertStringIncludes(route, "prepare = prepareAIExecution");
    assert(!route.includes("_genAI"));
    assert(!route.includes("test_only"));
  }
  assertStringIncludes(
    source,
    "handleIdentifyDescribeRequest(req, user, supabaseAdmin)",
  );
  assertStringIncludes(production, "resolveAIClaim(request, authority)");
  assertStringIncludes(
    production,
    "createAIExecution(geminiAdapter, request, snapshot)",
  );
  assert(!production.includes("Deno.env"));
  assert(!production.includes("test_only"));
  for (
    const name of [
      "contracts.ts",
      "registry.ts",
      "contentRegistry.ts",
      "execution.ts",
    ]
  ) {
    const common = await Deno.readTextFile(
      new URL(`../_shared/ai/${name}`, import.meta.url),
    );
    assert(!common.includes('from "@google/genai"'));
  }
});

Deno.test("Field Chat stale quota recovery cannot fall through to the original quota error", async () => {
  for (
    const path of [
      "../insight-chat/index.ts",
      "../explore-post-chat/index.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(source, "await recoverStaleFieldChatQuota(");
    assert(
      /if \(quotaLease === null\) \{[\s\S]{0,800}return publicErrorResponse\([\s\S]{0,800}\);\s*\}\s*\} else \{\s*throw error;\s*\}/
        .test(source),
      `${path} must throw only non-coalescible quota errors after stale recovery`,
    );
    assert(
      !/if \(quotaLease === null\) \{[\s\S]{0,800}return publicErrorResponse\([\s\S]{0,800}\);\s*\}\s*\}\s*throw error;/
        .test(source),
      `${path} rethrows the original quota error after obtaining a recovery lease`,
    );
  }
});

Deno.test("scan audio moderation subcalls retain their original analysis linkage", async () => {
  for (
    const path of [
      "../share-scan-to-explore/index.ts",
      "../update-explore-field-notes/index.ts",
      "../request-community-identification/index.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(source, 'operation: "explore_audio_moderation"');
    assertStringIncludes(source, "originalAnalysisId:");
  }
});

Deno.test("every scan-producing route coalesces quota replays into an owner-scoped success response", async () => {
  for (
    const path of [
      "../identify/index.ts",
      "../identify-describe/index.ts",
      "../identify-multimodal/index.ts",
      "../audio-spec/index.ts",
    ]
  ) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    const completedLookup = source.indexOf(
      "await fetchCompletedIdentifyResponse(",
    );
    const quotaReservation = source.indexOf(
      "await reserveAIProviderCall(",
    );

    assertStringIncludes(source, "resolveAIRequestId(req, client_scan_id)");
    assert(completedLookup >= 0, `${path} has no completed-response lookup`);
    assert(
      completedLookup < quotaReservation,
      `${path} can reserve or dispatch AI before replaying a completed scan`,
    );
    assertStringIncludes(source, "waitForCompletedIdentifyResponse(");
    assertStringIncludes(source, '"ai_request_already_completed"');
    assertStringIncludes(source, '"ai_request_in_progress"');
    assertStringIncludes(source, '"X-Merian-Idempotent-Replay"');
    assertStringIncludes(source, "parseIdentifySuccessEnvelope(");
    assertStringIncludes(source, "responseEnvelope");
  }
});

Deno.test("group-tag cache misses cannot dispatch an unmetered provider call", async () => {
  const publicIdentificationRoutes = [
    "../identify/index.ts",
    "../identify-describe/index.ts",
    "../identify-multimodal/index.ts",
    "../audio-spec/index.ts",
  ];
  for (const path of publicIdentificationRoutes) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertStringIncludes(source, "fetchQuotaGuardedGroupTags(");
    assert(
      !source.includes("fetchGroupTags("),
      `${path} calls the provider helper without the group-tag quota boundary`,
    );
  }

  const quotaWrapper = await Deno.readTextFile(
    new URL("../_shared/groupTagQuota.ts", import.meta.url),
  );
  for (
    const fragment of [
      'operation: "scan_group_tag_enrichment"',
      "deriveAIRequestId(",
      "await quotaLease.commit();",
      "reservation: quotaLease.reservation",
      "await quotaLease.fail();",
    ]
  ) {
    assertStringIncludes(quotaWrapper, fragment);
  }

  const biology = await Deno.readTextFile(
    new URL("../_shared/biology.ts", import.meta.url),
  );
  assertStringIncludes(
    biology,
    "execution: PreparedAIExecution",
  );
  assertStringIncludes(biology, "await execution.invoke()");
  assert(!biology.includes("createFlashModel"));
  const worker = await Deno.readTextFile(
    new URL("../refresh-species-model-content/db.ts", import.meta.url),
  );
  for (
    const field of [
      'kind: "service_job"',
      'purpose: "public_species_facts"',
      "jobId: job.job_id",
      "attemptCount: job.attempts",
      "maxAttempts: job.max_attempts",
      "dependencies.prepareAI ?? prepareAIExecution",
    ]
  ) assertStringIncludes(worker, field);
  assert(!worker.includes("reserveAIProviderCall"));
});

Deno.test("server recovery retries use a separately metered idempotency key per claim attempt", async () => {
  const multimodal = await Deno.readTextFile(
    new URL("../identify-multimodal/index.ts", import.meta.url),
  );
  assertStringIncludes(multimodal, "X-Merian-Replay-Attempt");
  assertStringIncludes(
    multimodal,
    "`scan-ingestion-replay:${internalReplayAttempt}`",
  );
  assertStringIncludes(multimodal, "deriveAIRequestId(");

  const worker = await Deno.readTextFile(
    new URL("../replay-scan-ingestion/worker.ts", import.meta.url),
  );
  assertStringIncludes(worker, "replayAttemptCount: row.replay_attempt_count");
  assertStringIncludes(worker, '"X-Merian-Replay-Attempt"');
});

Deno.test("deployment does not require the optional quota hashing override", async () => {
  const workflow = await Deno.readTextFile(
    new URL("../../../../.github/workflows/deploy.yml", import.meta.url),
  );
  assert(
    !workflow.includes(
      ': "${AI_QUOTA_IP_HASH_SECRET:?Missing AI_QUOTA_IP_HASH_SECRET',
    ),
    "the optional key-separation override must not block deployment",
  );
  assertStringIncludes(
    workflow,
    'if [ -n "$AI_QUOTA_IP_HASH_SECRET" ] &&',
  );
  assertStringIncludes(
    workflow,
    "Using the built-in server key for domain-separated AI quota IP hashing.",
  );
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
