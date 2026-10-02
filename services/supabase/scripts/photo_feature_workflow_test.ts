import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { featureReviewSession } from "./identification_evaluation/photoFeatureView.ts";
import {
  type BlindFeatureView,
  type FeatureReviewer,
  parseFeatureReviewReceipt,
  reviewFeatureView,
} from "./identification_evaluation/photoFeatureInstrument.ts";
import {
  type FeatureScoringCase,
  type FeatureScoringResult,
  scorePhotoFeatures,
} from "./identification_evaluation/photoFeatureScoring.ts";
import { photoFeatureAdapter } from "./identification_evaluation/photoFeatureProvider.ts";
import { photoFeatureSnapshot } from "./identification_evaluation/photoFeatureCandidate.ts";
import { createAIExecution } from "../functions/_shared/ai/execution.ts";
import {
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
} from "../functions/_shared/ai/testing/openaiFixtures.ts";
import { solPrimaryDraftFixture } from "../functions/_shared/ai/testing/openaiSolPrimaryFixtures.ts";
const good = {
  support: "supported",
  visibilityAccurate: true,
  diagnosticValue: "distinguishing",
};
const view: BlindFeatureView = {
  token: "opaque",
  facts: ["Synthetic shape fixture."],
  image: { sha256: "1".repeat(64), mimeType: "image/png", data: "AQID" },
  features: [{
    kind: "shape",
    visibility: "visible",
    observation: "PRIVATE FEATURE",
  }],
};
const judges = (): FeatureReviewer[] =>
  ["slot-01", "slot-02"].map((id) => ({
    id,
    method: "synthetic",
    review: () => Promise.resolve([{ ...good }]),
  }));
Deno.test("feature instrument binds distinct reviewers and refuses disputed or forged credit", async () => {
  const receipt = await reviewFeatureView(view, judges());
  assertEquals(receipt.eligible, true);
  assert(!JSON.stringify(receipt).includes("PRIVATE"));
  const disagreement = judges();
  disagreement[1].review = () =>
    Promise.resolve([{ ...good, visibilityAccurate: false }]);
  const disputed = await reviewFeatureView(view, disagreement);
  assertEquals(disputed.eligible, false);
  assertEquals(disputed.disagreements, 1);
  assertThrows(() =>
    parseFeatureReviewReceipt({ ...disputed, eligible: true })
  );
  assertThrows(() =>
    parseFeatureReviewReceipt({ ...receipt, rawFeature: "PRIVATE" })
  );
  const duplicate = judges();
  duplicate[1].id = duplicate[0].id;
  await assertRejects(() => reviewFeatureView(view, duplicate));
});
Deno.test("private feature browser view hides IDs and deletes content after bounded verdict submission", async () => {
  const origin = "http://127.0.0.1:4444", secret = "synthetic-secret";
  const session = featureReviewSession(
    view,
    { id: "slot-01", method: "synthetic" },
    () => origin,
    secret,
  );
  const request = (path: string, body?: unknown, token = secret) =>
    new Request(origin + path, {
      method: body ? "POST" : "GET",
      headers: {
        host: "127.0.0.1:4444",
        origin,
        "x-review-token": token,
        ...(body ? { "content-type": "application/json" } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
  assertEquals(
    (await session.handler(request("/view", undefined, "wrong"))).status,
    403,
  );
  const response = await session.handler(request("/view"));
  assertEquals(response.headers.get("cache-control"), "no-store, max-age=0");
  const shown = await response.json();
  assertEquals(Object.keys(shown).sort(), [
    "facts",
    "features",
    "image",
    "reviewer",
    "token",
  ]);
  assertEquals(
    (await session.handler(
      request("/submit", [{ ...good, rawText: "PRIVATE" }]),
    )).status,
    400,
  );
  assertEquals((await session.handler(request("/submit", [good]))).status, 200);
  assertEquals(await session.result, [good]);
  assertEquals((await session.handler(request("/view"))).status, 410);
  assertEquals((await session.handler(request("/submit", [good]))).status, 410);
  const cancelled = featureReviewSession(
    view,
    { id: "slot-01", method: "synthetic" },
    () => origin,
    secret,
  );
  cancelled.close();
  assertEquals(await cancelled.result, null);
});
Deno.test("feature transport reuses exact-model safety/accounting without exposing provider text", async () => {
  const request = openAIPhotoRequestFixture();
  let calls = 0;
  const fetcher: typeof fetch = (_url, init) => {
    calls++;
    const body = JSON.parse(String(init?.body));
    assert(body.text.format.schema.properties.diagnostic_features);
    assertEquals(body.model, "gpt-6-sol");
    const raw = openAIResponseFixture();
    raw.output[0].content[0].text = JSON.stringify({
      ...solPrimaryDraftFixture(),
      diagnostic_features: view.features,
    });
    return Promise.resolve(
      Response.json({
        ...raw,
        service_tier: "default",
        moderation: openAIPhotoModerationFixture(),
      }),
    );
  };
  const outcome = await createAIExecution(
    photoFeatureAdapter("synthetic-key", fetcher),
    request,
    photoFeatureSnapshot(request),
  ).invoke();
  assertEquals(calls, 1);
  assertEquals(outcome.kind, "draft");
  assertEquals(outcome.mediaSafety?.disposition, "allowed");
  assert(outcome.usage !== null);
});
Deno.test("feature advancement requires reviewed paired gains across mechanisms and unresolved evidence", async () => {
  const receipt = await reviewFeatureView(view, judges());
  const unresolved = await reviewFeatureView({
    ...view,
    features: view.features.map((f) => ({ ...f, visibility: "unclear" })),
  }, judges());
  const cases: FeatureScoringCase[] = Array.from({ length: 18 }, (_, i) => ({
    caseId: `c${String(i + 1).padStart(4, "0")}`,
    reference: i === 14
      ? {
        subject: "biological",
        resolution: "unresolved",
        supportedRank: null,
        acceptableTaxa: [],
      }
      : {
        subject: "biological",
        resolution: "named",
        supportedRank: i < 5 ? "species" : "genus",
        acceptableTaxa: [{
          id: `test:t${i}`,
          rank: i < 5 ? "species" : "genus",
        }],
      },
    mechanisms: i < 5 ? [] : [i % 3 + 1],
  }));
  const values: FeatureScoringResult[] = cases.flatMap((c, i) =>
    (["primary", "features"] as const).map((arm) => {
      const wrong = arm === "primary" && [5, 6, 14].includes(i);
      return {
        arm,
        review: arm === "features" ? (i === 14 ? unresolved : receipt) : null,
        observation: {
          prediction: {
            caseId: c.caseId,
            outcome: "normalized",
            subject: "biological",
            resolution: wrong ? "named" : c.reference.resolution,
            taxon: wrong
              ? { id: "test:wrong", rank: "species" }
              : c.reference.acceptableTaxa[0] ?? null,
            confidence: .5,
          },
          mapping: !wrong && c.reference.resolution === "unresolved"
            ? { status: "not_applicable", match: null }
            : { status: "matched", match: "canonical" },
        },
      };
    })
  );
  const sharedJudges = judges().map((r) => ({
    ...r,
    review: () => Promise.resolve([{ ...good, diagnosticValue: "shared" }]),
  }));
  const shared = await reviewFeatureView(view, sharedJudges);
  assertEquals(
    scorePhotoFeatures(
      cases,
      values.map((v) => v.arm === "features" ? { ...v, review: shared } : v),
    ).outcomeHurdleMet,
    false,
  );
  const pass = scorePhotoFeatures(cases, values);
  assertEquals(pass.outcomeHurdleMet, true);
  assertEquals(pass.unresolvedGains, 1);
  assertEquals(pass.advancementAuthorized, false);
  assertEquals(
    scorePhotoFeatures(cases, values.slice(1)).outcomeHurdleMet,
    false,
  );
  const lost = structuredClone(values);
  lost.find((v) =>
    v.arm === "features" && v.observation.prediction.caseId === cases[5].caseId
  )!.review = null;
  assertEquals(scorePhotoFeatures(cases, lost).outcomeHurdleMet, false);
  const regression = structuredClone(values);
  regression[1].observation = {
    prediction: { caseId: cases[0].caseId, outcome: "invalid_output" },
    mapping: null,
  };
  assertEquals(scorePhotoFeatures(cases, regression).outcomeHurdleMet, false);
  const onlyOneMechanism = cases.map((c) => ({
    ...c,
    mechanisms: c.mechanisms.length ? [1] : [],
  }));
  assertEquals(
    scorePhotoFeatures(onlyOneMechanism, values).outcomeHurdleMet,
    false,
  );
  assertThrows(() => scorePhotoFeatures(cases, [...values, values[0]]));
});
