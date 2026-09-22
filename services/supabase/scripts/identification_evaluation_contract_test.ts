import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import type { EvaluationCorpus } from "./identification_evaluation/contracts.ts";
import {
  fingerprintCorpus,
  fingerprintEvidence,
  projectEvaluationEvidence,
} from "./identification_evaluation/evidence.ts";
import { syntheticCorpus } from "./identification_evaluation/fixtures.ts";
import {
  EvaluationContractError,
  parseEvaluationCorpus,
  parseEvaluationInput,
  parsePrediction,
} from "./identification_evaluation/validation.ts";

type Mutable<T> = T extends readonly (infer U)[] ? Mutable<U>[]
  : T extends object ? { -readonly [K in keyof T]: Mutable<T[K]> }
  : T;
function fixture(): Mutable<EvaluationCorpus> {
  return structuredClone(syntheticCorpus()) as Mutable<EvaluationCorpus>;
}
function reviewedFixture(): Mutable<EvaluationCorpus> {
  const corpus = fixture();
  corpus.kind = "reference";
  corpus.approval = {
    recordRef: "synthetic-approval",
    ownerRole: "curator",
    retainUntil: "2026-12-31",
  };
  for (const item of corpus.cases) {
    item.curation = {
      kind: "reviewed",
      source: "purpose_collected",
      sourceRecordRef: "synthetic-source",
      referenceRecordRef: "synthetic-reference",
      permission: "gemini_evaluation",
      rightsApproved: true,
      personalDataExcluded: true,
      nearDuplicatesReviewed: true,
      referenceVerified: true,
      reviewerRefs: ["r0001", "r0002"],
      adjudication: "agreed",
    };
  }
  return corpus; // Tests validation of assertions, not actual research approval.
}

Deno.test("evaluation corpus accepts six input groups and copies caller records", () => {
  const value = fixture();
  const corpus = parseEvaluationCorpus(value);
  assertEquals(
    new Set(corpus.cases.map((item) => item.input.inputGroup)).size,
    6,
  );
  assertEquals(corpus.cases.length, 12);
  value.cases[0].input.observationTexts[0] = "Changed after parsing.";
  assertNotEquals(
    corpus.cases[0].input.observationTexts[0],
    value.cases[0].input.observationTexts[0],
  );
  assertEquals(parseEvaluationCorpus(reviewedFixture()).kind, "reference");
});

Deno.test("evaluation eligibility rejects missing approval and incomplete independent review", async (t) => {
  const changes: [string, (value: Mutable<EvaluationCorpus>) => void][] = [
    ["no corpus approval", (c) => c.approval = null],
    [
      "unapproved rights",
      (c) => Object.assign(c.cases[0].curation, { rightsApproved: false }),
    ],
    [
      "personal information unchecked",
      (c) =>
        Object.assign(c.cases[0].curation, { personalDataExcluded: false }),
    ],
    [
      "duplicate review unchecked",
      (c) =>
        Object.assign(c.cases[0].curation, { nearDuplicatesReviewed: false }),
    ],
    [
      "unverified reference",
      (c) => Object.assign(c.cases[0].curation, { referenceVerified: false }),
    ],
    [
      "same reviewer twice",
      (c) =>
        Object.assign(c.cases[0].curation, {
          reviewerRefs: ["r0001", "r0001"],
        }),
    ],
    [
      "wrong recipient",
      (c) =>
        Object.assign(c.cases[0].curation, { permission: "another_service" }),
    ],
    [
      "synthetic admission as real",
      (c) => c.cases[0].curation = { kind: "synthetic" },
    ],
  ];
  for (const [name, change] of changes) {
    await t.step(name, () => {
      const corpus = reviewedFixture();
      change(corpus);
      assertThrows(
        () => parseEvaluationCorpus(corpus),
        EvaluationContractError,
      );
    });
  }
});

Deno.test("evaluation schema rejects extra fields without exposing their names or values", () => {
  const corpus = fixture();
  const marker = "synthetic-private-marker";
  Object.assign(corpus.cases[0].input, { [marker]: marker });
  const error = assertThrows(
    () => parseEvaluationCorpus(corpus),
    EvaluationContractError,
  );
  assertEquals(error.message, "invalid_shape");
  assertEquals(JSON.stringify(error).includes(marker), false);
  assertThrows(
    () =>
      parseEvaluationInput({
        ...fixture().cases[0].input,
        reference: fixture().cases[0].reference,
      }),
    EvaluationContractError,
  );
});

Deno.test("evaluation input rejects invalid shapes, bounds and precise context", async (t) => {
  const changes: [string, (value: Mutable<EvaluationCorpus>) => void][] = [
    [
      "unknown version",
      (c) => Object.assign(c, { version: "identification_corpus_v2" }),
    ],
    ["empty corpus", (c) => c.cases = []],
    [
      "whitespace only description",
      (c) => c.cases[1].input.observationTexts = [" "],
    ],
    [
      "oversized description",
      (c) => c.cases[1].input.observationTexts = ["x".repeat(2001)],
    ],
    [
      "sparse text array",
      (c) => c.cases[1].input.observationTexts = new Array(1),
    ],
    [
      "raw location field",
      (c) =>
        Object.assign(c.cases[0].input.context, { gps: "disallowed-field" }),
    ],
    ["invalid month", (c) => c.cases[0].input.context.currentMonth = 13],
    [
      "unbounded region string",
      (c) =>
        c.cases[0].input.context.deviceRegion = "unapproved free-form location",
    ],
    [
      "invalid source hash",
      (c) => c.cases[0].input.assets[0].sha256 = "invalid",
    ],
    ["negative file size", (c) => c.cases[0].input.assets[0].byteLength = -1],
  ];
  for (const [name, change] of changes) {
    await t.step(name, () => {
      const corpus = fixture();
      change(corpus);
      assertThrows(
        () => parseEvaluationCorpus(corpus),
        EvaluationContractError,
      );
    });
  }
});

Deno.test("evaluation rejects duplicate observations across splits and renamed duplicate media", () => {
  let corpus = fixture();
  corpus.cases[1].input.groupId = corpus.cases[0].input.groupId;
  corpus.cases[1].input.split = "held_out";
  assertThrows(
    () => parseEvaluationCorpus(corpus),
    EvaluationContractError,
    "split_leakage",
  );
  corpus.cases[1].input.split = "development";
  assertThrows(
    () => parseEvaluationCorpus(corpus),
    EvaluationContractError,
    "duplicate_group",
  );
  corpus = fixture();
  corpus.cases[1].input.caseId = corpus.cases[0].input.caseId;
  assertThrows(
    () => parseEvaluationCorpus(corpus),
    EvaluationContractError,
    "duplicate_case",
  );
  corpus = fixture();
  corpus.cases[6].input.assets[0].sha256 =
    corpus.cases[0].input.assets[0].sha256;
  assertThrows(
    () => parseEvaluationCorpus(corpus),
    EvaluationContractError,
    "duplicate_evidence",
  );
  corpus = fixture();
  corpus.cases[7].input.observationTexts = [
    corpus.cases[1].input.observationTexts[0].toUpperCase(),
  ];
  assertThrows(
    () => parseEvaluationCorpus(corpus),
    EvaluationContractError,
    "duplicate_evidence",
  );
});

Deno.test("evaluation requires ordered frames and every declared companion audio input", async (t) => {
  const changes: [string, (value: Mutable<EvaluationCorpus>) => void][] = [
    ["missing companion audio", (c) => c.cases[4].input.assets.pop()],
    ["reversed frames", (c) => c.cases[3].input.assets.reverse()],
    [
      "repeated frame index",
      (c) => Object.assign(c.cases[3].input.assets[1], { frameIndex: 0 }),
    ],
    [
      "unbound audio clip",
      (c) => Object.assign(c.cases[4].input.assets[5], { clipIndex: 1 }),
    ],
    [
      "audio precedes frames",
      (c) => c.cases[4].input.assets.unshift(c.cases[4].input.assets.pop()!),
    ],
    ["wrong input group", (c) => c.cases[4].input.inputGroup = "frames"],
    [
      "native video forbidden",
      (c) =>
        Object.assign(c.cases[3].input.assets[0], {
          kind: "video",
          mimeType: "video/mp4",
        }),
    ],
    [
      "audio must be WAV",
      (c) =>
        Object.assign(c.cases[2].input.assets[0], { mimeType: "audio/mpeg" }),
    ],
    [
      "path traversal",
      (c) => c.cases[0].input.assets[0].path = "../outside.jpg",
    ],
    [
      "remote asset",
      (c) =>
        c.cases[0].input.assets[0].path = "https://example.invalid/asset.jpg",
    ],
    [
      "answer-bearing filename",
      (c) => c.cases[0].input.assets[0].path = "assets/reference-species.jpg",
    ],
  ];
  for (const [name, change] of changes) {
    await t.step(name, () => {
      const corpus = fixture();
      change(corpus);
      assertThrows(
        () => parseEvaluationCorpus(corpus),
        EvaluationContractError,
      );
    });
  }
  const partial = fixture();
  partial.cases[3].input.assets.splice(2, 1);
  assertEquals(parseEvaluationCorpus(partial).cases[3].input.assets.length, 4);
});

Deno.test("evaluation labels distinguish identity from evidence-supported rank", () => {
  const corpus = fixture();
  corpus.cases[1].reference.acceptableTaxa = [{
    id: "synthetic:2",
    rank: "species",
  }];
  assertThrows(
    () => parseEvaluationCorpus(corpus),
    EvaluationContractError,
    "invalid_reference",
  );
  const unknown = fixture();
  unknown.cases[7].reference.acceptableTaxa = [{
    id: "synthetic:8",
    rank: "genus",
  }];
  assertThrows(
    () => parseEvaluationCorpus(unknown),
    EvaluationContractError,
    "invalid_reference",
  );
});

Deno.test("prepared visuals preserve WebP and one MIME type per request", () => {
  const webp = fixture();
  assertEquals(
    parseEvaluationCorpus(webp).cases[3].input.assets[0].mimeType,
    "image/webp",
  );
  for (
    const [mimeType, extension] of [["image/jpeg", "jpg"], ["image/png", "png"]]
  ) {
    const corpus = fixture();
    for (const asset of corpus.cases[3].input.assets) {
      Object.assign(asset, {
        mimeType,
        path: `assets/${asset.id}.${extension}`,
      });
    }
    assertEquals(
      parseEvaluationCorpus(corpus).cases[3].input.assets[0].mimeType,
      mimeType,
    );
  }
  Object.assign(webp.cases[3].input.assets[0], {
    mimeType: "image/png",
    path: `assets/${webp.cases[3].input.assets[0].id}.png`,
  });
  assertThrows(
    () => parseEvaluationCorpus(webp),
    EvaluationContractError,
    "invalid_media",
  );
});

Deno.test("evaluation v1 requires an explicit species mapping for finer ranks", () => {
  const corpus = fixture();
  Object.assign(corpus.cases[0].reference, {
    supportedRank: "subspecies",
    acceptableTaxa: [{ id: "synthetic:1", rank: "subspecies" }],
  });
  assertThrows(() => parseEvaluationCorpus(corpus), EvaluationContractError);
  assertThrows(
    () =>
      parsePrediction({
        caseId: "c0001",
        outcome: "normalized",
        subject: "biological",
        resolution: "named",
        taxon: { id: "synthetic:1", rank: "subspecies" },
        confidence: 0.99,
      }),
    EvaluationContractError,
  );
});

Deno.test("description derivation cannot cross groups through a media case", () => {
  const corpus = fixture();
  corpus.cases[1].input.observationTexts = [
    ...corpus.cases[0].input.observationTexts,
  ];
  corpus.cases[1].input.split = "held_out";
  assertThrows(
    () => parseEvaluationCorpus(corpus),
    EvaluationContractError,
    "duplicate_evidence",
  );
  const withoutContext = fixture();
  for (const item of withoutContext.cases) {
    if (item.input.inputGroup !== "description") {
      item.input.observationTexts = [];
    }
  }
  assertEquals(parseEvaluationCorpus(withoutContext).cases.length, 12);
});

Deno.test("evaluation projection omits labels and preserves exact no-telemetry context", () => {
  const corpus = fixture();
  const input = corpus.cases[1].input;
  const projection = projectEvaluationEvidence(input);
  assertEquals(projection.captureContext, "Context: no telemetry.");
  for (
    const key of [
      "caseId",
      "groupId",
      "split",
      "reference",
      "curation",
      "acceptableTaxa",
    ]
  ) assertEquals(Object.hasOwn(projection, key), false);
  assertEquals(JSON.stringify(projection).includes("synthetic:2"), false);
  input.context = { deviceRegion: "US", currentMonth: 9 };
  assertEquals(
    projectEvaluationEvidence(input).captureContext,
    "Context: Region:US, Month:9.",
  );
  const frames = projectEvaluationEvidence(corpus.cases[4].input);
  assertEquals(frames.assets.map((item) => item.kind), [
    "video_frame",
    "video_frame",
    "video_frame",
    "video_frame",
    "video_frame",
    "video_audio",
  ]);
  assertThrows(() => {
    projectEvaluationEvidence(corpus.cases[1]);
  }, EvaluationContractError);
});

Deno.test("evaluation fingerprints freeze labels separately from projected evidence", async () => {
  const corpus = fixture();
  const before = await fingerprintCorpus(corpus);
  const evidenceBefore = await fingerprintEvidence(corpus.cases[0].input);
  assertEquals(before.length, 64);
  assertEquals(
    await fingerprintCorpus(
      Object.fromEntries(Object.entries(corpus).reverse()),
    ),
    before,
  );
  corpus.cases[0].reference.acceptableTaxa = [{
    id: "synthetic:changed",
    rank: "species",
  }];
  assertNotEquals(await fingerprintCorpus(corpus), before);
  assertEquals(
    await fingerprintEvidence(corpus.cases[0].input),
    evidenceBefore,
  );
  corpus.cases[0].input.context.currentMonth = 9;
  assertNotEquals(
    await fingerprintEvidence(corpus.cases[0].input),
    evidenceBefore,
  );
});

Deno.test("prediction contract rejects non-finite scores and raw diagnostic fields", () => {
  const base = {
    caseId: "c0001",
    outcome: "normalized",
    subject: "biological",
    resolution: "named",
    taxon: null,
    confidence: 0.99,
  } as const;
  assertEquals(parsePrediction(base), base);
  for (const confidence of [NaN, Infinity, -0.01, 1.01]) {
    assertThrows(
      () => parsePrediction({ ...base, confidence }),
      EvaluationContractError,
    );
  }
  assertThrows(
    () => parsePrediction({ ...base, reasoning: "synthetic raw output" }),
    EvaluationContractError,
  );
  assertThrows(
    () =>
      parsePrediction({ caseId: "c0001", outcome: "refusal", confidence: 1 }),
    EvaluationContractError,
  );
  assertThrows(
    () => parsePrediction({ ...base, subject: "non_biological" }),
    EvaluationContractError,
  );
});
