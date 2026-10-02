import { assert, assertEquals, assertThrows } from "@std/assert";
import { isIdentificationProviderAssignment } from "../functions/_shared/ai/admission.ts";
import {
  buildOpenAIPhotoPrimaryRequest,
  openAIPhotoPrimarySnapshot,
} from "../functions/_shared/ai/openaiPhotoPrimary.ts";
import { decodeSolPhotoPrimaryDraft } from "../functions/_shared/ai/openaiSolPrimaryContract.ts";
import {
  isOpenAIProfile,
  type OpenAISchema,
} from "../functions/_shared/ai/openaiRequest.ts";
import {
  openAIPhotoRequestFixture,
  openAITextFixture,
} from "../functions/_shared/ai/testing/openaiFixtures.ts";
import { solPrimaryDraftFixture } from "../functions/_shared/ai/testing/openaiSolPrimaryFixtures.ts";
import {
  buildPhotoFeatureRequest,
  decodePhotoFeatureDraft,
  FEATURE_PROFILE,
  photoFeatureSnapshot,
} from "./identification_evaluation/photoFeatureCandidate.ts";
import {
  projectReviewedPhotoFeatures,
  type TransientFeatureReviewer,
} from "./identification_evaluation/photoFeatureReview.ts";
import type { ReviewedTaxonomy } from "./identification_evaluation/taxonomy.ts";

const feature = {
  kind: "view_coverage",
  observation: "PRIVATE SYNTHETIC FEATURE",
  visibility: "not_visible",
} as const;
const draft = () => ({
  ...solPrimaryDraftFixture(),
  diagnostic_features: [{ ...feature }],
});
const taxonomy: ReviewedTaxonomy = {
  version: "evaluation_taxonomy_v2",
  taxonomyVersion: "synthetic-v1",
  catalogRef: "synthetic-catalog",
  reviewRef: "synthetic-review",
  taxa: [{
    taxon: { id: "test:species", rank: "species" },
    canonicalName: "Syntheticus example",
    synonyms: [],
  }],
};
const support: TransientFeatureReviewer = () => Promise.resolve(["supported"]);
const supportAgain: TransientFeatureReviewer = () =>
  Promise.resolve(["supported"]);
const project = (value: unknown, a = support, b = supportAgain) =>
  projectReviewedPhotoFeatures("c0001", "opaque-token", value, taxonomy, [
    a,
    b,
  ]);

Deno.test("feature candidate preserves input/settings and existing fields, with no production admission", () => {
  const request = openAIPhotoRequestFixture();
  const snapshot = photoFeatureSnapshot(request);
  const base = buildOpenAIPhotoPrimaryRequest(
    request,
    openAIPhotoPrimarySnapshot(request),
  );
  const candidate = buildPhotoFeatureRequest(request, snapshot);
  assertEquals({
    ...candidate,
    instructions: base.instructions,
    text: base.text,
  }, base);
  assert(candidate.instructions.startsWith(base.instructions));
  const b = base.text.format.schema, c = candidate.text.format.schema;
  for (const [k, v] of Object.entries(b.properties!)) {
    assertEquals((c as OpenAISchema).properties![k], v);
  }
  assertEquals(c.required, [...b.required!, "diagnostic_features"]);
  assertEquals({ ...c, required: b.required, properties: b.properties }, b);
  assertEquals(Object.keys(c.properties!), [
    ...Object.keys(b.properties!),
    "diagnostic_features",
  ]);
  assertEquals(
    c.properties!.diagnostic_features.items!.additionalProperties,
    false,
  );
  assertEquals(isOpenAIProfile(FEATURE_PROFILE), false);
  assertEquals(
    isIdentificationProviderAssignment({
      provider: "openai",
      binding: snapshot.binding,
      inputProfile: "multimodal_photo_v1",
      permission: "openai",
    }),
    false,
  );
  for (
    const change of [{ prompt: "old" }, { extra: true }, {
      generation: { ...snapshot.generation, reasoningEffort: "high" },
    }]
  ) {
    assertThrows(() =>
      buildPhotoFeatureRequest(
        request,
        { ...snapshot, ...change } as typeof snapshot,
      )
    );
  }
  assertThrows(() => photoFeatureSnapshot(openAITextFixture()));
  assertThrows(() =>
    photoFeatureSnapshot({
      ...request,
      capture: { ...request.capture, hasVideo: true },
    })
  );
  candidate.text.format.schema.properties!.diagnostic_features.maxItems = 99;
  assertEquals(
    buildPhotoFeatureRequest(request, snapshot).text.format.schema.properties!
      .diagnostic_features.maxItems,
    3,
  );
  assertEquals(
    buildOpenAIPhotoPrimaryRequest(
      request,
      openAIPhotoPrimarySnapshot(request),
    ),
    base,
  );
});

Deno.test("feature decoder retains all five primary states and rejects self-grading/malformed prose", () => {
  for (
    const state of [
      "species",
      "genus",
      "family",
      "unresolved_biological",
      "non_biological",
    ] as const
  ) {
    const identification = solPrimaryDraftFixture(state);
    assertEquals(
      decodePhotoFeatureDraft({
        ...identification,
        diagnostic_features: [{ ...feature }],
      }).identification,
      decodeSolPhotoPrimaryDraft(identification),
    );
  }
  const nonbio = {
    ...solPrimaryDraftFixture("non_biological"),
    diagnostic_features: [],
  };
  assertEquals(decodePhotoFeatureDraft(nonbio).features, []);
  assertThrows(() => decodeSolPhotoPrimaryDraft(draft()));
  for (
    const features of [
      undefined,
      [],
      Array(4).fill(feature),
      [feature, feature],
      [{ ...feature, confidence: 1 }],
      [{ ...feature, kind: "taxon" }],
      [{ ...feature, visibility: "verified" }],
      [{ ...feature, observation: "x".repeat(161) }],
      [{ ...feature, observation: " " }],
      [{ ...feature, observation: "hidden\ntext" }],
    ]
  ) {
    const e = assertThrows(() =>
      decodePhotoFeatureDraft({ ...draft(), diagnostic_features: features })
    );
    assert(e instanceof Error);
    assertEquals(e.message, "photo_feature_draft_invalid");
  }
  assertThrows(() =>
    decodePhotoFeatureDraft({ ...draft(), reviewer_judgments: ["supported"] })
  );
});

Deno.test("transient review hides identity fields and retains no diagnostic prose", async () => {
  const raw = { ...draft(), ai_reasoning: "PRIVATE EXPLANATION" };
  let visits = 0;
  const review: TransientFeatureReviewer = (opaque, view) => {
    visits++;
    assertEquals(opaque, "opaque-token");
    assertEquals(view, [feature]);
    assert(Object.isFrozen(view) && Object.isFrozen(view[0]));
    assert(!JSON.stringify(view).includes("Syntheticus"));
    assertThrows(() => {
      (view[0] as { observation: string }).observation = "changed";
    });
    return Promise.resolve(["supported"]);
  };
  const r = await project(raw, review, (token, view) => review(token, view));
  assertEquals(visits, 2);
  assertEquals(r.status, "reviewed");
  if (r.status !== "reviewed") throw new Error("missing_review");
  assertEquals(r.review, {
    count: 1,
    supported: 1,
    disputed: 0,
    unsupported: 0,
    allFeaturesSupported: true,
  });
  for (
    const privateText of [
      "PRIVATE",
      "Syntheticus",
      "diagnostic_features",
      "observation:",
    ]
  ) assert(!JSON.stringify(r).includes(privateText));
  assertEquals(raw.ai_reasoning, "PRIVATE EXPLANATION");
});

Deno.test("review fails closed for disagreement, rejection, malformed results and duplicate reviewers", async () => {
  for (const judgment of ["contradicted", "unverifiable", "irrelevant"]) {
    const r = await project(
      draft(),
      support,
      () => Promise.resolve([judgment]),
    );
    assert(r.status === "reviewed");
    assertEquals(r.review.allFeaturesSupported, false);
    assertEquals(r.review.disputed, 1);
  }
  for (
    const invalid of [[], ["supported", "supported"], ["PRIVATE ERROR"], {
      judgment: "supported",
    }]
  ) {
    const r = await project(draft(), support, () => Promise.resolve(invalid));
    assertEquals(r.status, "review_incomplete");
    assert(!JSON.stringify(r).includes("PRIVATE"));
  }
  assertEquals(
    (await project(draft(), support, support)).status,
    "review_incomplete",
  );
  const r = await project(draft(), () => {
    throw new Error("PRIVATE ERROR");
  });
  assertEquals(r.status, "review_incomplete");
  assert(!JSON.stringify(r).includes("PRIVATE"));
  let calls = 0;
  const shouldNotRun: TransientFeatureReviewer = () => {
    calls++;
    return Promise.resolve([]);
  };
  assertEquals(
    (await project({ ...draft(), resolution: "genus" }, shouldNotRun, support))
      .status,
    "invalid_output",
  );
  assertEquals(
    (await project(
      { ...draft(), diagnostic_features: [] },
      shouldNotRun,
      support,
    )).status,
    "invalid_output",
  );
  assertEquals(calls, 0);
  const empty = await project(
    { ...solPrimaryDraftFixture("non_biological"), diagnostic_features: [] },
    () => Promise.resolve([]),
    () => Promise.resolve([]),
  );
  assert(empty.status === "reviewed");
  assertEquals(empty.review.allFeaturesSupported, false);
});

Deno.test("one reviewer cannot later mutate its recorded judgment through the next callback", async () => {
  const first = ["contradicted"];
  const result = await project(draft(), () => Promise.resolve(first), () => {
    first[0] = "supported";
    return Promise.resolve(["supported"]);
  });
  assert(result.status === "reviewed");
  assertEquals(result.review.allFeaturesSupported, false);
});

Deno.test("reference materialization preserves holds, input hashes, original split and taxonomy ranks", async () => {
  const { featureReferences, FEATURE_ADJUDICATION_SHA256 } = await import(
    "./identification_evaluation/photoFeaturePreparation.ts"
  );
  const { confidenceFixture } = await import(
    "./identification_evaluation/testing/confidenceFixtures.ts"
  );
  const { fingerprintBytes } = await import(
    "./identification_evaluation/evidence.ts"
  );
  const bytes = await Deno.readFile(
    new URL(
      "../../../docs/research/identification/answerability-adjudication-2026-10-01.json",
      import.meta.url,
    ),
  );
  assertEquals(await fingerprintBytes(bytes), FEATURE_ADJUDICATION_SHA256);
  const adjudication = JSON.parse(new TextDecoder().decode(bytes));
  const fixture = confidenceFixture();
  // Synthetic parent identities/pixels exercise joins, not biological correctness.
  for (const row of adjudication.cases) {
    const c = fixture.corpus.cases.find((c) => c.input.caseId === row.caseId)!;
    c.input = {
      ...c.input,
      assets: [{ ...c.input.assets[0], sha256: row.assetSha256 }],
    };
    for (const taxon of row.reference?.acceptableTaxa ?? []) {
      if (
        taxon.rank !== "family" &&
        !fixture.taxonomy.taxa.some((t) => t.taxon.id === taxon.id)
      ) {
        fixture.taxonomy.taxa.push({
          taxon,
          canonicalName: `Invented ${fixture.taxonomy.taxa.length}`,
          synonyms: [],
        });
      }
    }
  }
  const before = structuredClone(fixture);
  const prepared = featureReferences(adjudication, fixture);
  assertEquals(prepared.cases.length, 18);
  assertEquals(prepared.heldCaseIds, ["c0005", "c0062"]);
  assert(prepared.cases.every((c) => c.input.split === "development"));
  assertEquals(
    prepared.cases.filter((c) => c.reference.supportedRank === "family").length,
    3,
  );
  assertEquals(fixture, before);
  for (
    const change of [
      (a: typeof adjudication) => {
        a.cases[0].assetSha256 = "f".repeat(64);
      },
      (a: typeof adjudication) => {
        a.cases.find((r: { caseId: string }) => r.caseId === "c0005")
          .reference = a.cases[0].reference;
      },
      (a: typeof adjudication) => {
        a.eligibleCaseIds[0] = "c0005";
      },
      (a: typeof adjudication) => {
        a.taxonomyOverlay.additions[0].taxon.rank = "species";
      },
      (a: typeof adjudication) => {
        a.taxonomyOverlay.editsToExistingEntries = [{}];
      },
      (a: typeof adjudication) => {
        a.cases[0].reference.acceptableTaxa[0].rank = "family";
      },
      (a: typeof adjudication) => {
        a.independentHumanValidation = true;
      },
    ]
  ) {
    const modified = structuredClone(adjudication);
    change(modified);
    assertThrows(() => featureReferences(modified, fixture));
  }
});
