import {
  assert,
  assertEquals,
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

Deno.test("every direct paid-provider dispatch file is explicitly inventoried", async () => {
  const functionsRoot = new URL("../", import.meta.url);
  const dispatchFiles: string[] = [];

  for (const file of await runtimeTypeScriptFiles(functionsRoot)) {
    const relativePath = decodeURIComponent(
      file.pathname.slice(functionsRoot.pathname.length),
    );
    if (
      relativePath.startsWith("_tests/") ||
      /(?:^|\/)[^/]*(?:_test|[.]test)[.]ts$/.test(relativePath)
    ) {
      continue;
    }
    const source = await Deno.readTextFile(file);
    if (source.includes(".generateContent({")) {
      dispatchFiles.push(relativePath);
    }
  }

  assertEquals(dispatchFiles.sort(), [
    "_shared/audioModeration.ts",
    "_shared/biology.ts",
    "_shared/gemini.ts",
    "audio-spec/index.ts",
    "explore-post-chat/index.ts",
    "identify-describe/index.ts",
    "identify-multimodal/index.ts",
    "identify/index.ts",
    "insight-chat/index.ts",
  ]);
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
      /await quotaLease[.]commit[(][)];[\s\S]{0,120}const result = await _genAI[.]models[.]generateContent/
        .test(source),
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
      "quotaLease.reservation.model",
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
    "scientificName: string,\n  modelName: string,",
  );
  assertStringIncludes(biology, "100,\n    modelName,");
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
