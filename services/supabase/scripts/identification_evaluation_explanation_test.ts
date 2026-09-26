import { screenCandidate } from "./identification_evaluation/candidateReport.ts";
import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { createAIExecution } from "../functions/_shared/ai/execution.ts";
import { createOpenAIEvaluationAdapter } from "../functions/_shared/ai/openai.ts";
import {
  buildOpenAIRequestParameters,
  CONCISE_EXPLANATION_INSTRUCTION,
  OPENAI_CANDIDATE_PROFILES,
  openAIEvaluationSnapshot,
} from "../functions/_shared/ai/openaiRequest.ts";
import type { MultimodalAIRequest } from "../functions/_shared/ai/contracts.ts";
import {
  CALIBRATION_EXAMPLES,
  calibrationRecord,
  validateCalibration,
} from "./identification_evaluation/explanationCalibration.ts";
import {
  type AssessmentBinding,
  assessmentMatches,
  parseAssessment,
  parseRatings,
  parseReviewPlan,
  unavailableRatings,
} from "./identification_evaluation/explanationContracts.ts";
import {
  openPrivateReview,
  type ReviewDisplay,
  reviewSession,
} from "./identification_evaluation/explanationView.ts";
const request: MultimodalAIRequest = {
  task: "identify",
  variant: "multimodal",
  capture: {
    hasVideo: false,
    videoClipCount: 0,
    declaredVideoFrameCount: 0,
    videoInferenceFrameCount: 0,
  },
  evidence: [{
    kind: "text",
    order: 0,
    source: "observation_context",
    text: "An invented smooth gray pebble.",
  }],
};
Deno.test("concise profiles preserve evidence and schema, changing only declared native settings", async () => {
  const baseline = buildOpenAIRequestParameters(
    request,
    openAIEvaluationSnapshot(request),
  );
  const [control, candidate] = OPENAI_CANDIDATE_PROFILES.map((p) =>
    buildOpenAIRequestParameters(request, openAIEvaluationSnapshot(request, p))
  );
  assertEquals(control, {
    ...baseline,
    prompt_cache_options: { mode: "explicit" },
  });
  assertEquals(candidate, {
    ...control,
    instructions: baseline.instructions + "\n" +
      CONCISE_EXPLANATION_INSTRUCTION,
  });
  assert(!JSON.stringify(candidate).includes("prompt_cache_breakpoint"));
  const imageRequest: MultimodalAIRequest = {
    ...request,
    evidence: [{
      kind: "image",
      order: 0,
      mimeType: "image/png",
      inputIndex: 0,
      data: "AAAA",
      lineage: null,
    }],
  };
  const imageBase = buildOpenAIRequestParameters(
    imageRequest,
    openAIEvaluationSnapshot(imageRequest),
  );
  const imageCandidate = buildOpenAIRequestParameters(
    imageRequest,
    openAIEvaluationSnapshot(imageRequest, OPENAI_CANDIDATE_PROFILES[1]),
  );
  assertEquals(imageCandidate, {
    ...imageBase,
    prompt_cache_options: { mode: "explicit" },
    instructions: imageBase.instructions + "\n" +
      CONCISE_EXPLANATION_INSTRUCTION,
  });
  assertEquals(
    openAIEvaluationSnapshot(imageRequest, OPENAI_CANDIDATE_PROFILES[1]).prompt,
    "openai_concise_identify_vision_v1",
  );
  assertEquals(
    openAIEvaluationSnapshot(request, OPENAI_CANDIDATE_PROFILES[1]).prompt,
    "openai_concise_identify_text_v1",
  );
  assertThrows(() =>
    buildOpenAIRequestParameters(
      request,
      {
        ...openAIEvaluationSnapshot(request, OPENAI_CANDIDATE_PROFILES[1]),
        generation: {
          maxOutputTokens: 100,
          reasoningEffort: "low",
          imageDetail: "high",
        },
      } as unknown as ReturnType<typeof openAIEvaluationSnapshot>,
    )
  );
  assertThrows(() =>
    openAIEvaluationSnapshot({
      ...request,
      capture: { ...request.capture, hasVideo: true },
    }, OPENAI_CANDIDATE_PROFILES[0])
  );
  for (const profile of OPENAI_CANDIDATE_PROFILES) {
    let calls = 0;
    const adapter = createOpenAIEvaluationAdapter(
      "synthetic-fixture",
      ((_url, init) => {
        calls++;
        assertEquals(
          JSON.parse(String(init?.body)),
          JSON.parse(JSON.stringify(buildOpenAIRequestParameters(
            request,
            openAIEvaluationSnapshot(request, profile),
          ))),
        );
        return Promise.resolve(
          new Response(JSON.stringify({
            status: "incomplete",
            model: "gpt-6-sol",
            usage: {
              input_tokens: 10,
              output_tokens: 5,
              total_tokens: 15,
              input_tokens_details: { cached_tokens: 0, cache_write_tokens: 0 },
              output_tokens_details: { reasoning_tokens: 0 },
            },
          })),
        );
      }) as typeof fetch,
    );
    const execution = createAIExecution(
      adapter,
      request,
      openAIEvaluationSnapshot(request, profile),
    );
    const outcome = await execution.invoke();
    assertEquals(outcome.usage?.cacheWriteTokens, 0);
    assertEquals(calls, 1);
  }
});
Deno.test("explanation rubric rejects contradictory ratings, prose and false calibration", async () => {
  const pass = structuredClone(CALIBRATION_EXAMPLES[0].expected);
  assertThrows(() =>
    parseRatings({
      ...pass,
      grounding: { status: "pass", reason: "invented_evidence" },
    })
  );
  assertThrows(() =>
    parseRatings({
      ...pass,
      grounding: { status: "fail", reason: "missing_limitation" },
    })
  );
  assertThrows(() => parseRatings({ ...pass, notes: "raw explanation" }));
  const correct = CALIBRATION_EXAMPLES.map((c) => c.expected);
  const recorded = await calibrationRecord(
    "reviewer",
    correct,
    "synthetic_fixture_v1",
  );
  assertEquals(recorded.passed, true);
  await validateCalibration(recorded, "reviewer", false);
  await assertRejects(() => validateCalibration(recorded, "reviewer", true));
  const wrong = await calibrationRecord(
    "reviewer",
    correct.map(() => pass),
    "synthetic_fixture_v1",
  );
  assertEquals(wrong.passed, false);
  await assertRejects(() =>
    validateCalibration({ ...wrong, passed: true }, "reviewer", false)
  );
  assertEquals(unavailableRatings().grounding.status, "not_assessable");
});
Deno.test("delegated AI review is versioned and cannot become owner or synthetic live evidence", async () => {
  const digest = "1".repeat(64);
  const review = {
    rubricDigest: digest,
    factsDigest: digest,
    calibrationDigest: null,
    reviewerRef: "assistant-review",
    timeoutMs: 60000,
    cards: [{ caseId: "c0001", digest }],
    method: "assistant_local_v1",
    delegationRef: "user-delegated-review",
  };
  assertEquals(parseReviewPlan(review, true).calibrationDigest, null);
  assertThrows(() => parseReviewPlan(review));
  assertThrows(() =>
    parseReviewPlan({ ...review, calibrationDigest: digest }, true)
  );
  assertThrows(() => parseReviewPlan({ ...review, delegationRef: "" }, true));
  const binding: AssessmentBinding = {
    planDigest: digest,
    runDigest: digest,
    key: "case-control-1",
    requestDigest: digest,
    profileId: "openai_photo_text_uncached_v1",
    profileDigest: digest,
    inputDigest: digest,
    factCardDigest: digest,
    resultDigest: digest,
    calibrationDigest: null,
    rubricDigest: digest,
    reviewerRef: "assistant-review",
  };
  const record = parseAssessment({
    version: "explanation_assessment_v2",
    binding,
    method: "assistant_local_v1",
    ratings: CALIBRATION_EXAMPLES[0].expected,
  });
  await assessmentMatches(record, binding, true, true);
  await assertRejects(() => assessmentMatches(record, binding, true));
  await assertRejects(() => assessmentMatches(record, binding, false, true));
  assertThrows(() => parseAssessment({ ...record, method: "owner_local_v1" }));
  assertThrows(() =>
    parseAssessment({ ...record, version: "explanation_assessment_v1" })
  );
  const synthetic = { ...record, method: "synthetic_fixture_v1" };
  await assessmentMatches(synthetic, binding, false, true);
  await assertRejects(() => assessmentMatches(synthetic, binding, true, true));
  const owner = {
    version: "explanation_assessment_v1",
    binding: { ...binding, calibrationDigest: digest },
    method: "owner_local_v1",
    ratings: record.ratings,
  };
  await assessmentMatches(owner, owner.binding, true);
  await assertRejects(() =>
    assessmentMatches(owner, owner.binding, true, true)
  );
});
const display: ReviewDisplay = {
  title: "Synthetic review",
  observation: ["</script><img src=x onerror=alert(1)>"],
  images: [],
  facts: ["Synthetic facts."],
  decision: ["Non-biological"],
  explanation: ["Synthetic explanation."],
};
Deno.test("private review requires one-use capability, same origin and bounded enum input", async () => {
  const origin = "http://127.0.0.1:41000", capability = "synthetic-capability";
  const session = reviewSession(display, () => origin, capability);
  const call = (
    path: string,
    method = "GET",
    body?: unknown,
    extra: Record<string, string> = {},
  ) =>
    session.handler(
      new Request(origin + path, {
        method,
        headers: {
          host: "127.0.0.1:41000",
          "x-review-token": capability,
          ...(method === "POST"
            ? { origin, "content-type": "application/json" }
            : {}),
          ...extra,
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
    );
  const page = await call("/");
  assertEquals(page.headers.get("cache-control"), "no-store, max-age=0");
  assert(
    page.headers.get("content-security-policy")?.includes(
      "frame-ancestors 'none'",
    ),
  );
  assert(!(await page.text()).includes(display.observation[0]));
  assertEquals(
    (await call("/view", "GET", undefined, { "x-review-token": "wrong" }))
      .status,
    403,
  );
  assertEquals(
    (await call("/view", "GET", undefined, { host: "attacker.invalid" }))
      .status,
    403,
  );
  const view = await call("/view");
  assertEquals((await view.json()).observation, display.observation);
  assertEquals(
    (await call("/submit", "POST", CALIBRATION_EXAMPLES[0].expected, {
      origin: "https://attacker.invalid",
    })).status,
    403,
  );
  assertEquals(
    (await call("/submit", "POST", { raw: "x".repeat(10000) })).status,
    400,
  );
  assertEquals(
    (await call("/submit", "POST", {
      ...CALIBRATION_EXAMPLES[0].expected,
      notes: "not allowed",
    })).status,
    400,
  );
  assertEquals(
    (await call("/submit", "POST", CALIBRATION_EXAMPLES[0].expected)).status,
    200,
  );
  assertEquals(await session.result, CALIBRATION_EXAMPLES[0].expected);
  assertEquals((await call("/view")).status, 410);
  assertEquals(
    (await call("/submit", "POST", CALIBRATION_EXAMPLES[0].expected)).status,
    410,
  );
  session.close();
});
Deno.test("private review cancellation releases content and never manufactures a rating", async () => {
  const origin = "http://127.0.0.1:41001",
    session = reviewSession(display, () => origin, "synthetic-capability");
  const result = await session.handler(
    new Request(origin + "/cancel", {
      method: "POST",
      headers: { host: "127.0.0.1:41001", origin },
      body: JSON.stringify({ token: "synthetic-capability" }),
    }),
  );
  assertEquals(result.status, 200);
  assertEquals(await session.result, null);
});

Deno.test("private review releases its server once after save, cancel or opener failure", async (t) => {
  for (const outcome of ["saved", "cancelled", "unavailable"] as const) {
    await t.step(outcome, async () => {
      const originalServe = Deno.serve, originalCommand = Deno.Command;
      let handler!: (request: Request) => Promise<Response>;
      let signal!: AbortSignal;
      let closed = false, shutdowns = 0;
      Deno.serve = ((
        options: { signal: AbortSignal },
        callback: typeof handler,
      ) => {
        signal = options.signal;
        handler = callback;
        return {
          addr: { hostname: "127.0.0.1", port: 41002, transport: "tcp" },
          finished: Promise.resolve(),
          shutdown: () => {
            shutdowns++;
            closed = true;
            return Promise.resolve();
          },
        };
      }) as typeof Deno.serve;
      Deno.Command = class {
        constructor(
          private command: string,
          private options: Deno.CommandOptions,
        ) {}
        async output() {
          assertEquals(this.command, "/usr/bin/open");
          assertEquals(this.options.clearEnv, true);
          if (outcome === "unavailable") return { success: false };
          const url = new URL(this.options.args![0]);
          const result = await handler(
            new Request(
              url.origin + (outcome === "saved" ? "/submit" : "/cancel"),
              {
                method: "POST",
                headers: {
                  host: url.host,
                  origin: url.origin,
                  "x-review-token": url.hash.slice(1),
                  "content-type": "application/json",
                },
                body: JSON.stringify(
                  outcome === "saved"
                    ? CALIBRATION_EXAMPLES[0].expected
                    : { token: url.hash.slice(1) },
                ),
              },
            ),
          );
          assertEquals(result.status, 200);
          await result.text();
          return { success: true };
        }
      } as unknown as typeof Deno.Command;
      try {
        assertEquals(
          await openPrivateReview(display, 1000),
          outcome === "saved" ? CALIBRATION_EXAMPLES[0].expected : null,
        );
        assert(closed);
        assertEquals(shutdowns, 1);
        // Deno 2.9.4 releases the HTTP resource during graceful shutdown.
        // Aborting that signal afterward throws BadResource, losing the review.
        assertEquals(signal.aborted, false);
      } finally {
        Deno.serve = originalServe;
        Deno.Command = originalCommand;
      }
    });
  }
});

Deno.test("candidate screen requires complete measured gains without new quality faults", () => {
  const good = {
    subject: "agreement",
    identity: "agreement",
    falseBiological: false,
    unsupportedBiological: false,
    unsupportedSpecificity: false,
  } as const;
  const comparison: Parameters<typeof screenCandidate>[0] = {
    slices: (["all_cases", "photos", "description"] as const).map(
      (inputGroup) => ({
        inputGroup,
        baseline: {
          scheduled: inputGroup === "all_cases"
            ? 8
            : inputGroup === "photos"
            ? 6
            : 2,
        },
        candidate: {
          scheduled: inputGroup === "all_cases"
            ? 8
            : inputGroup === "photos"
            ? 6
            : 2,
        },
        observedLatencyImprovementPercent: 12,
        observedCostImprovementPercent: 0,
        paired: Array.from({
          length: inputGroup === "all_cases"
            ? 8
            : inputGroup === "photos"
            ? 6
            : 2,
        }, () => ({ left: { ...good }, right: { ...good } })),
      }),
    ),
  };
  const assessments = Array.from(
    { length: 16 },
    () => ({ ratings: structuredClone(CALIBRATION_EXAMPLES[0].expected) }),
  );
  const state = { live: true, complete: true, cache: true };
  const screen = (c = comparison, s = state, a = assessments) =>
    screenCandidate(c, a, s);
  assertEquals(screen(), "candidate_for_further_qualification");
  assertEquals(
    screen(comparison, { ...state, live: false }),
    "synthetic_mechanics_only",
  );
  assertEquals(screen(comparison, { ...state, cache: false }), "inconclusive");
  assertEquals(
    screen(comparison, { ...state, complete: false }),
    "inconclusive",
  );
  assertEquals(screen(comparison, state, assessments.slice(1)), "inconclusive");
  const missingReview = structuredClone(assessments);
  missingReview[0].ratings = unavailableRatings();
  assertEquals(screen(comparison, state, missingReview), "inconclusive");
  let c = structuredClone(comparison);
  c.slices[0].observedLatencyImprovementPercent = 9;
  assertEquals(screen(c), "retain_baseline_no_material_gain");
  c = structuredClone(comparison);
  c.slices[2].observedCostImprovementPercent = -11;
  assertEquals(screen(c), "retain_baseline_no_material_gain");
  c = structuredClone(comparison);
  c.slices[1].observedLatencyImprovementPercent = null;
  assertEquals(screen(c), "inconclusive");
  c = structuredClone(comparison);
  c.slices[0].paired[0].right.identity = "unmapped";
  assertEquals(screen(c), "inconclusive");
  c = structuredClone(comparison);
  c.slices[0].paired[0].left.identity = "disagreement";
  c.slices[0].paired[0].right.falseBiological = true;
  assertEquals(
    screen(c),
    "retain_baseline_quality_regression",
    "an existing identity error must not mask a new false biological result",
  );
});
