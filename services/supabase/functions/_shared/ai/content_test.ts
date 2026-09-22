import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createClient, type User } from "@supabase/supabase-js";
import { createEnrichHandler } from "../../enrich-scan/index.ts";
import { fetchQuotaGuardedGroupTags } from "../groupTagQuota.ts";
import {
  runSpeciesModelContentRefresh,
  type SpeciesModelEnrichmentJobRow,
} from "../../refresh-species-model-content/db.ts";
import type {
  AIAdapter,
  AIExecutionAuthority,
  AIProviderOutcome,
  SpeciesContentAIRequest,
} from "./contracts.ts";
import type { prepareAIExecution } from "./production.ts";
import { resolveAIClaim } from "./registry.ts";
import { createAIExecution } from "./execution.ts";

const user: User = {
  id: "00000000-0000-4000-8000-000000000201",
  aud: "authenticated",
  app_metadata: {},
  user_metadata: {},
  created_at: "2026-09-21T00:00:00Z",
};
const requestId = "00000000-0000-4000-8000-000000000101";
const speciesId = "00000000-0000-4000-8000-000000000301";
const scientificName = "Synthetic species";
const taxonomy = {
  kingdom: "Animalia",
  phylum: "Arthropoda",
  class: "Insecta",
  order: "SyntheticOrder",
  family: "SyntheticFamily",
  genus: "Synthetic",
};
const overview = {
  taxonomy,
  habitat_description: "Synthetic habitat.",
  iucn_red_list_status: "not_evaluated",
  hazard_type: "none",
  colors: ["green"],
};
const facts = {
  providerDurationMs: 1234,
  providerCompletedAt: 0,
  returnedModel: null,
  finishReason: "STOP",
  responseCharacters: 0,
  usage: {
    promptTokens: 12,
    candidateTokens: 8,
    totalTokens: 25,
    thinkingTokens: 3,
    cachedTokens: 2,
    toolTokens: 2,
    modalityBreakdown: {
      prompt: { text: 12 },
      cached: { text: 2 },
      candidates: { text: 8 },
      tool: { text: 2 },
    },
  },
};
const job: SpeciesModelEnrichmentJobRow = {
  job_id: "00000000-0000-4000-8000-000000000401",
  species_id: speciesId,
  scientific_name: scientificName,
  content_group: "habitat",
  priority: 1,
  attempts: 1,
  max_attempts: 5,
  source_trigger: "synthetic",
  metadata: {},
};
const serviceRequest = {
  limit: 12,
  asOf: "2026-09-21T00:00:00Z",
  dryRun: false,
};
const operations = {
  species_overview: "scan_overview_enrichment",
  lookalikes: "scan_lookalike_enrichment",
  group_tags: "scan_group_tag_enrichment",
};

function database(
  options: {
    cached?: boolean;
    denied?: boolean;
    commitDenied?: boolean;
    jobs?: SpeciesModelEnrichmentJobRow[];
    beforeWrite?: () => Promise<void>;
  } = {},
) {
  const events: string[] = [];
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const row: Record<string, unknown> = {
    id: speciesId,
    scientific_name: scientificName,
    ...taxonomy,
    alternative_common_names: [],
    habitat_description: options.cached ? overview.habitat_description : null,
    lookalikes_flash_attempted: options.cached ?? false,
  };
  const client = createClient(
    "https://synthetic.supabase.invalid",
    "synthetic-test-only",
    {
      auth: { persistSession: false, autoRefreshToken: false },
      global: {
        fetch: async (input, init) => {
          const req = new Request(input, init);
          const url = new URL(req.url);
          const name = url.pathname.split("/").at(-1)!;
          const args = req.method === "GET" ? {} : await req.json();
          if (url.pathname.includes("/rpc/")) {
            calls.push({ name, args });
            switch (name) {
              case "reserve_ai_quota":
                events.push("reserve");
                assertEquals(args.p_user_id, user.id);
                assertEquals(args.p_original_analysis_id, requestId);
                if (options.denied) {
                  return Response.json({ message: "ai_consent_required" }, {
                    status: 403,
                  });
                }
                return Response.json({
                  reservation_id: "00000000-0000-4000-8000-000000000501",
                  request_id: args.p_request_id,
                  lease_token: "00000000-0000-4000-8000-000000000601",
                  lease_expires_at: "2099-01-01T00:00:00Z",
                  reservation_state: "reserved",
                  is_replay: false,
                  attempt_count: 1,
                  model: "gemini-2.5-pro",
                  effective_plan: "pro_paid",
                  effective_tier: "pro",
                  subscription_tier: "pro",
                  trial_active: false,
                  entitlement_version: 1,
                  policy_version: 1,
                  daily_limit: 100,
                  daily_remaining: 99,
                  original_analysis_id: requestId,
                  complimentary_client_scan_id: null,
                  flash_fallback_used: false,
                  scans_remaining: 0,
                  scans_available_to_start: 0,
                  in_flight_count: 0,
                });
              case "finalize_ai_quota_reservation":
                events.push(String(args.p_final_state));
                return Response.json(
                  !(options.commitDenied && args.p_final_state === "committed"),
                );
              case "record_ai_usage_event":
                events.push("usage");
                return Response.json(null);
              case "claim_species_model_enrichment_jobs":
                events.push("claim");
                return Response.json(options.jobs ?? [job]);
              case "complete_species_enrichment_job":
                events.push("complete");
                return Response.json(null);
              case "persist_species_model_lookalikes":
                events.push("relations");
                return Response.json([{
                  persisted_count: 0,
                  unresolved_count: 0,
                  rejected_count: 0,
                }]);
              default:
                throw new Error(`Unexpected RPC ${name}`);
            }
          }
          if (name === "species_dictionary") {
            if (req.method === "PATCH") {
              await options.beforeWrite?.();
              Object.assign(row, args);
              events.push("write");
            } else assertEquals(req.method, "GET");
            return Response.json(row);
          }
          if (name === "species_lookalikes") return Response.json([]);
          assertEquals(name, "species_content_provenance");
          assertEquals(req.method, "POST");
          events.push("provenance");
          return Response.json(null);
        },
      },
    },
  );
  return { client, events, calls, row };
}

function preparation(db: ReturnType<typeof database>, options: {
  setupFailed?: boolean;
  outcome?: AIProviderOutcome;
  beforeInvoke?: () => Promise<void>;
  inspect?: (
    request: SpeciesContentAIRequest,
    authority: AIExecutionAuthority,
  ) => void;
} = {}): typeof prepareAIExecution {
  return (request, authority) => {
    assert(request.variant === "species_content");
    options.inspect?.(request, authority);
    const snapshot = resolveAIClaim(request, authority);
    const adapter: AIAdapter = {
      provider: "test_only",
      prepare() {
        db.events.push("prepare");
        if (options.setupFailed) {
          throw new Error("synthetic configuration failure");
        }
        return async () => {
          db.events.push("invoke");
          await options.beforeInvoke?.();
          return options.outcome ?? {
            ...facts,
            kind: "draft",
            draft: request.task === "species_overview"
              ? overview
              : request.task === "lookalikes"
              ? { similar_species: [] }
              : { group_tags: [" animal ", "insect", "insect"] },
          };
        };
      },
    };
    return createAIExecution(adapter, request, snapshot);
  };
}

function request(scope: string) {
  return new Request("https://example.invalid/enrich-scan", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      scientific_name: scientificName,
      scope,
      scan_id: requestId,
      ai_request_id: requestId,
    }),
  });
}

Deno.test("content registry separates user permission and public claimed jobs", () => {
  const input: SpeciesContentAIRequest = {
    task: "group_tags",
    variant: "species_content",
    scientificName,
  };
  const authority: AIExecutionAuthority = {
    kind: "service_job",
    task: "group_tags",
    purpose: "public_species_facts",
    jobId: job.job_id,
    attemptCount: 1,
    maxAttempts: 5,
    model: "gemini-2.5-flash",
  };
  const snapshot = resolveAIClaim(input, authority);
  assert(Object.isFrozen(snapshot) && Object.isFrozen(snapshot.generation));
  assertEquals(snapshot.permission, null);
  assertEquals(snapshot.policyVersion, null);
  assertEquals(snapshot.contextKind, "service_job");
  assertEquals(snapshot.operation, "scan_group_tag_enrichment");
  for (
    const change of [
      { task: "lookalikes" },
      { purpose: "private_observation" },
      { jobId: "" },
      { attemptCount: 0 },
      { attemptCount: 6 },
      { maxAttempts: 0 },
      { model: "gemini-2.5-pro" },
      { model: "test_only" },
    ]
  ) {
    assertThrows(() =>
      resolveAIClaim(input, { ...authority, ...change } as AIExecutionAuthority)
    );
  }
  const userAuthority: AIExecutionAuthority = {
    kind: "user_request",
    userId: user.id,
    operation: "scan_group_tag_enrichment",
    permission: "google_gemini",
    reservation: {
      id: "synthetic-reservation",
      requestId,
      attemptCount: 1,
      policyVersion: 1,
      model: "gemini-2.5-pro",
    },
  };
  assertEquals(resolveAIClaim(input, userAuthority).model, "gemini-2.5-pro");
  for (
    const change of [
      { operation: "scan_identification" },
      { permission: "other_provider" },
      { userId: "" },
      ...[
        { id: "" },
        { requestId: "" },
        { attemptCount: 0 },
        { policyVersion: 0 },
        { model: "test_only" },
      ].map((change) => ({
        reservation: { ...userAuthority.reservation, ...change },
      })),
    ]
  ) {
    assertThrows(() =>
      resolveAIClaim(input, {
        ...userAuthority,
        ...change,
      } as AIExecutionAuthority)
    );
  }
  assertThrows(
    () =>
      resolveAIClaim({
        task: "identify",
        variant: "description_compat",
        evidence: [{
          kind: "text",
          order: 0,
          source: "description",
          text: "Synthetic private note",
        }],
      }, authority),
    Error,
    "ai_authority_mismatch",
  );
});

Deno.test("content callers preserve user quotas, caches and public job lifecycle", async (t) => {
  const env = new Map(
    ["POSTHOG_API_KEY", "AI_QUOTA_IP_HASH_SECRET"].map((
      key,
    ) => [key, Deno.env.get(key)]),
  );
  const originalLog = console.log,
    originalError = console.error,
    originalWarn = console.warn;
  const runtime = globalThis as unknown as {
    EdgeRuntime?: { waitUntil(task: Promise<void>): void };
  };
  const originalRuntime = runtime.EdgeRuntime;
  const background: Promise<void>[] = [];
  const step = (name: string, run: () => Promise<void>) =>
    t.step(name, async () => {
      try {
        await run();
      } finally {
        await Promise.all(background.splice(0));
      }
    });
  try {
    Deno.env.delete("POSTHOG_API_KEY");
    Deno.env.set(
      "AI_QUOTA_IP_HASH_SECRET",
      "synthetic-test-only-hash-secret".repeat(2),
    );
    console.log = console.error = console.warn = () => {};
    runtime.EdgeRuntime = { waitUntil: (task) => background.push(task) };
    for (
      const task of ["species_overview", "lookalikes", "group_tags"] as const
    ) {
      const scope = task === "species_overview" ? "enrichment" : "lookalikes";
      const run = (
        db: ReturnType<typeof database>,
        prepare = preparation(db),
      ) =>
        task === "group_tags"
          ? fetchQuotaGuardedGroupTags(
            request(scope),
            user,
            scientificName,
            db.client,
            requestId,
            prepare,
          )
          : createEnrichHandler(prepare)(request(scope), user, db.client);
      if (task !== "group_tags") {
        await step(
          `${task}: cache hit performs no admission or inference`,
          async () => {
            const db = database({ cached: true });
            const response = await run(db);
            assert(response instanceof Response);
            assertEquals(response.status, 200);
            assertEquals(db.events, []);
          },
        );
      }
      await step(
        `${task}: permission denial prevents preparation`,
        async () => {
          const db = database({ denied: true });
          if (task === "group_tags") assertEquals(await run(db), null);
          else await assertRejects(() => run(db), Error, "Confirm you are 18");
          assertEquals(db.events, ["reserve"]);
        },
      );
      for (const setupFailed of [true, false]) {
        await step(
          `${task}: ${
            setupFailed ? "setup" : "commit"
          } failure refunds without invocation`,
          async () => {
            const db = database({ commitDenied: !setupFailed });
            const response = await run(db, preparation(db, { setupFailed }));
            if (response instanceof Response) {
              assertEquals(response.status, 500);
            } else assertEquals(response, null);
            assertEquals(
              db.events,
              setupFailed
                ? ["reserve", "prepare", "refunded"]
                : ["reserve", "prepare", "committed", "refunded"],
            );
          },
        );
      }
      for (
        const kind of [
          "unknown_execution",
          "operational_failure",
          "refusal",
          "invalid_output",
        ] as const
      ) {
        await step(
          `${task}: ${kind} remains charged and does not write content`,
          async () => {
            const db = database();
            const outcome: AIProviderOutcome = kind === "invalid_output"
              ? { ...facts, kind, reason: "json" }
              : { ...facts, kind, usage: null };
            const response = await run(db, preparation(db, { outcome }));
            if (response instanceof Response) {
              assertEquals(response.status, 500);
            } else assertEquals(response, null);
            assertEquals(
              db.events.filter((event) => event !== "usage"),
              ["reserve", "prepare", "committed", "invoke", "failed"],
            );
          },
        );
      }
      await step(
        `${task}: one admitted invocation preserves task, usage and attribution`,
        async () => {
          const db = database();
          const response = await run(
            db,
            preparation(db, {
              inspect(input, authority) {
                assertEquals(input.task, task);
                assertEquals(input.scientificName, scientificName);
                assert(authority.kind === "user_request");
                assertEquals(authority.permission, "google_gemini");
                assertEquals(authority.operation, operations[task]);
                assertEquals(authority.reservation.model, "gemini-2.5-pro");
              },
            }),
          );
          if (response instanceof Response) {
            assertEquals(response.status, 200);
            const body = await response.json();
            assert(!JSON.stringify(body).includes('"execution"'));
            assert(!JSON.stringify(body).includes('"ai_provider"'));
          } else assert(response?.group_tags);
          await Promise.all(background);
          assertEquals(db.events.slice(0, 4), [
            "reserve",
            "prepare",
            "committed",
            "invoke",
          ]);
          const usage = db.calls.filter((call) =>
            call.name === "record_ai_usage_event"
          );
          assertEquals(usage.length, 1);
          assertEquals(usage[0].args.p_operation, operations[task]);
          assertEquals(usage[0].args.p_user_id, user.id);
          assertEquals(usage[0].args.p_model, "gemini-2.5-pro");
          assertEquals(usage[0].args.p_metadata, {
            ai_task: task,
            ai_provider: "gemini",
            ai_binding: "gemini_baseline_v1",
            ai_prompt: `${task}_v1`,
            ai_schema: `${task}_v1`,
            ai_policy_version: 1,
            ai_context_kind: "user_request",
            ai_returned_model: null,
            ai_provider_duration_ms: 1234,
            ai_outcome: "draft",
          });
          assertEquals([
            usage[0].args.p_prompt_tokens,
            usage[0].args.p_candidate_tokens,
            usage[0].args.p_total_tokens,
            usage[0].args.p_thinking_tokens,
            usage[0].args.p_cached_tokens,
            usage[0].args.p_tool_tokens,
          ], [12, 8, 25, 3, 2, 2]);
          assertEquals(
            usage[0].args.p_prompt_tokens_by_modality,
            facts.usage.modalityBreakdown,
          );
          const reservation = db.calls.find((call) =>
            call.name === "reserve_ai_quota"
          )!;
          assertEquals(reservation.args.p_operation, operations[task]);
          if (task === "group_tags") {
            assert(reservation.args.p_request_id !== requestId);
          }
          if (task === "species_overview") {
            assertEquals(
              db.row.habitat_description,
              overview.habitat_description,
            );
          }
        },
      );
    }
    await step(
      "overview waiters share inference and wait for its cache write",
      async () => {
        const writing = Promise.withResolvers<void>(),
          release = Promise.withResolvers<void>();
        const db = database({
          beforeWrite: () => {
            writing.resolve();
            return release.promise;
          },
        });
        const handle = createEnrichHandler(preparation(db));
        const first = handle(request("enrichment"), user, db.client);
        await writing.promise;
        let secondFinished = false;
        const second = handle(request("enrichment"), user, db.client).then(
          (value) => {
            secondFinished = true;
            return value;
          },
        );
        await new Promise((resolve) => setTimeout(resolve, 0));
        assertEquals(secondFinished, false);
        assertEquals(db.events.filter((event) => event === "invoke").length, 1);
        release.resolve();
        const responses = await Promise.all([first, second]);
        assertEquals(await responses[0].json(), await responses[1].json());
        assertEquals(
          db.calls.filter((call) => call.name === "reserve_ai_quota").length,
          1,
        );
      },
    );
    for (const scope of ["enrichment", "lookalikes"]) {
      await step(
        `${scope}: failed leader releases waiter through fresh admission`,
        async () => {
          const invoked = Promise.withResolvers<void>();
          const release = Promise.withResolvers<void>();
          const options = { denied: false };
          const db = database(options);
          const first = createEnrichHandler(preparation(db, {
            beforeInvoke: () => {
              invoked.resolve();
              return release.promise;
            },
            outcome: { ...facts, kind: "unknown_execution", usage: null },
          }))(request(scope), user, db.client);
          await invoked.promise;
          options.denied = true;
          const handle = createEnrichHandler(preparation(db));
          const second = handle(request(scope), user, db.client);
          const rejected = assertRejects(
            () => second,
            Error,
            "Confirm you are 18",
          );
          await new Promise((resolve) => setTimeout(resolve, 0));
          assertEquals(db.events, [
            "reserve",
            "prepare",
            "committed",
            "invoke",
          ]);
          release.resolve();
          assertEquals((await first).status, 500);
          await rejected;
          assertEquals(db.events, [
            "reserve",
            "prepare",
            "committed",
            "invoke",
            "failed",
            "reserve",
          ]);
          options.denied = false;
          assertEquals(
            (await handle(request(scope), user, db.client)).status,
            200,
          );
          assertEquals(
            db.events.filter((event) => event === "invoke").length,
            2,
          );
          assertEquals(
            db.events.filter((event) => event === "reserve").length,
            3,
          );
        },
      );
    }
    for (
      const content_group of ["habitat", "lookalikes", "group_tags"] as const
    ) {
      await step(
        `public ${content_group}: claimed job uses Flash without user quota`,
        async () => {
          const db = database({ jobs: [{ ...job, content_group }] });
          const result = await runSpeciesModelContentRefresh(
            serviceRequest,
            db.client,
            {
              prepareAI: preparation(db, {
                inspect(input, authority) {
                  assert(authority.kind === "service_job");
                  assertEquals(authority.task, input.task);
                  assertEquals(authority.jobId, job.job_id);
                  assertEquals(authority.attemptCount, job.attempts);
                  assertEquals(authority.maxAttempts, job.max_attempts);
                  assertEquals(authority.model, "gemini-2.5-flash");
                },
              }),
            },
          );
          await Promise.all(background);
          assertEquals(result.failed_count, 0);
          assertEquals(db.events.slice(0, 3), ["claim", "prepare", "invoke"]);
          assert(
            !db.events.includes("reserve") && !db.events.includes("committed"),
          );
          const usage = db.calls.filter((call) =>
            call.name === "record_ai_usage_event"
          );
          assertEquals(usage.length, 1);
          assertEquals(usage[0].args.p_user_id, null);
          assertEquals(usage[0].args.p_model, "gemini-2.5-flash");
          const metadata = usage[0].args.p_metadata as Record<string, unknown>;
          assertEquals(metadata.ai_context_kind, "service_job");
          assertEquals(metadata.ai_policy_version, null);
          assert(!JSON.stringify(metadata).includes(job.job_id));
          assert(!JSON.stringify(metadata).includes(scientificName));
          assertEquals(
            db.calls.find((call) =>
              call.name === "complete_species_enrichment_job"
            )?.args.succeeded,
            true,
          );
          if (content_group === "group_tags") {
            assertEquals(db.row.group_tags, ["animal", "insect"]);
          }
        },
      );
    }
    await step(
      "public preview performs no inference, completion or usage writes",
      async () => {
        const db = database();
        const result = await runSpeciesModelContentRefresh(
          { ...serviceRequest, dryRun: true },
          db.client,
          {
            prepareAI: () => {
              throw new Error("Must not prepare");
            },
          },
        );
        assertEquals(result.dry_run, true);
        assertEquals(db.events, ["claim"]);
        assertEquals(db.calls[0].args.preview_only, true);
      },
    );
    await step(
      "invalid claim attempts fail before preparation or cache writes",
      async () => {
        const db = database({ jobs: [{ ...job, attempts: 6 }] });
        const result = await runSpeciesModelContentRefresh(
          serviceRequest,
          db.client,
          { prepareAI: preparation(db) },
        );
        assertEquals(result.failed_count, 1);
        assertEquals(db.events, ["claim", "complete"]);
        assertEquals(db.calls.at(-1)?.args.succeeded, false);
      },
    );
    await step(
      "uncertain public execution follows existing failed-job recovery",
      async () => {
        const db = database();
        const result = await runSpeciesModelContentRefresh(
          serviceRequest,
          db.client,
          {
            prepareAI: preparation(db, {
              outcome: { ...facts, kind: "unknown_execution", usage: null },
            }),
          },
        );
        assertEquals(result.failed_count, 1);
        assertEquals(db.events, ["claim", "prepare", "invoke", "complete"]);
        assertEquals(db.calls.at(-1)?.args.succeeded, false);
      },
    );
    await step(
      "public batches retain concurrency two and one call per claimed job",
      async () => {
        const db = database({
          jobs: Array.from(
            { length: 5 },
            (_, i) => ({ ...job, job_id: `synthetic-job-${i}` }),
          ),
        });
        const started = Promise.withResolvers<void>(),
          release = Promise.withResolvers<void>();
        let active = 0, peak = 0;
        const run = runSpeciesModelContentRefresh(serviceRequest, db.client, {
          prepareAI: preparation(db, {
            beforeInvoke: async () => {
              active++;
              peak = Math.max(peak, active);
              if (active === 2) started.resolve();
              await release.promise;
              active--;
            },
          }),
        });
        await started.promise;
        assertEquals(db.events.filter((event) => event === "invoke").length, 2);
        release.resolve();
        assertEquals((await run).refreshed_count, 5);
        assertEquals(peak, 2);
        assertEquals(db.events.filter((event) => event === "invoke").length, 5);
        assertEquals(
          db.events.filter((event) => event === "complete").length,
          5,
        );
      },
    );
  } finally {
    await Promise.all(background);
    console.log = originalLog;
    console.error = originalError;
    console.warn = originalWarn;
    if (originalRuntime === undefined) delete runtime.EdgeRuntime;
    else runtime.EdgeRuntime = originalRuntime;
    for (const [key, value] of env) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
});
