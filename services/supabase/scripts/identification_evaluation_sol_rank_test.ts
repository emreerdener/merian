import { createOpenAISolRankEvaluationAdapter } from "../functions/_shared/ai/openai.ts";
import { createAIExecution } from "../functions/_shared/ai/execution.ts";
import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  buildOpenAIPhotoModelRequestParameters,
  isOpenAIPhotoModelProfile,
  openAIPhotoModelSnapshot,
} from "../functions/_shared/ai/openaiPhotoModels.ts";
import {
  buildOpenAIPhotoRequestParameters,
  openAIPhotoSnapshot,
} from "../functions/_shared/ai/openaiPhoto.ts";
import {
  decodeOpenAIDraft,
  type OpenAISchema,
} from "../functions/_shared/ai/openaiRequest.ts";
import {
  openAIDraftFixture,
  openAIPhotoModerationFixture,
  openAIPhotoRequestFixture,
  openAIResponseFixture,
  openAITextFixture,
} from "../functions/_shared/ai/testing/openaiFixtures.ts";
import { normalizeIdentification } from "../functions/_shared/identify/normalizeIdentification.ts";
import {
  fingerprintBytes,
  fingerprintJson,
} from "./identification_evaluation/evidence.ts";
import { syntheticCorpus } from "./identification_evaluation/fixtures.ts";
import {
  parsePhotoTaxonomyRemap,
  repairPhotoTaxonomy,
} from "./identification_evaluation/photoTaxonomyRepair.ts";
import {
  buildSolPhotoRankRequest,
  SOL_RANK_PROFILE,
  solPhotoRankInstructions,
  solPhotoRankSchema,
  solPhotoRankSnapshot,
} from "./identification_evaluation/solPhotoRankCandidate.ts";
import {
  resolveTaxon,
  type ReviewedTaxonomy,
} from "./identification_evaluation/taxonomy.ts";

const request = openAIPhotoRequestFixture();
const baseline = () =>
  buildOpenAIPhotoModelRequestParameters(
    request,
    openAIPhotoModelSnapshot(request, "openai_photo_sol_low_v1"),
  );
const candidate = () =>
  buildSolPhotoRankRequest(request, solPhotoRankSnapshot(request));
function structural(value: OpenAISchema): OpenAISchema {
  const result = structuredClone(value);
  delete result.description;
  if (result.properties) {
    result.properties = Object.fromEntries(
      Object.entries(result.properties).map(([k, v]) => [k, structural(v)]),
    );
  }
  if (result.items) result.items = structural(result.items);
  return result;
}

Deno.test("Sol rank candidate changes only guidance and schema identity, retaining strict shape, generation and explanation format", async () => {
  const base = baseline(), result = candidate();
  const { instructions: _bi, text: _bt, ...b } = base;
  const { instructions: _ci, text: _ct, ...c } = result;
  assertEquals(c, b);
  assertEquals(result.model, "gpt-6-sol");
  assertEquals(result.reasoning, { effort: "low" });
  assertEquals(result.max_output_tokens, 8192);
  assertEquals(
    structural(result.text.format.schema),
    structural(base.text.format.schema),
  );
  assertEquals(result.text.format.type, base.text.format.type);
  assertEquals(result.text.format.strict, true);
  for (
    const key of [
      "ai_reasoning",
      "confidence_score",
      "image_quality",
      "pet_identification",
    ]
  ) {
    assertEquals(
      result.text.format.schema.properties?.[key],
      base.text.format.schema.properties?.[key],
    );
  }
  assert(result.instructions.includes("Geological Exceptions"));
  const geological = (value: string) =>
    value.split("\n").find((line) =>
      line.startsWith("- **Geological Exceptions:")
    );
  assertEquals(geological(result.instructions), geological(base.instructions));
  assertEquals(
    await fingerprintBytes(new TextEncoder().encode(result.instructions)),
    "2ce09781a640db6909494740e7a25cbdf8d53f8f944f9b524c3459dd69472f77",
  );
  assertEquals(
    await fingerprintJson(result.text.format),
    "630cc0447b70d10a9d6de25105a35c9d3ded73a124649a0d177cb348a69364a4",
  );
  assertEquals(baseline(), base);
});

Deno.test("Sol rank candidate fails on drift and cannot enter a historical or production photo binding", () => {
  assertEquals(isOpenAIPhotoModelProfile(SOL_RANK_PROFILE), false);
  const snapshot = solPhotoRankSnapshot(request);
  assertThrows(() =>
    buildOpenAIPhotoModelRequestParameters(
      request,
      snapshot as unknown as Parameters<
        typeof buildOpenAIPhotoModelRequestParameters
      >[1],
    )
  );
  assertThrows(() =>
    buildOpenAIPhotoRequestParameters(
      request,
      snapshot as unknown as ReturnType<typeof openAIPhotoSnapshot>,
    )
  );
  for (
    const change of [
      { model: "gpt-6-luna" },
      { confidence: "qualified" },
      { prompt: "changed" },
      { generation: { ...snapshot.generation, reasoningEffort: "high" } },
    ]
  ) {
    assertThrows(() =>
      buildSolPhotoRankRequest(
        request,
        { ...snapshot, ...change } as typeof snapshot,
      )
    );
  }
  assertThrows(() => solPhotoRankSnapshot(openAITextFixture()));
  assertThrows(() =>
    solPhotoRankSnapshot({
      ...request,
      capture: { ...request.capture, hasVideo: true },
    })
  );
  const text = baseline().instructions;
  assertThrows(() =>
    solPhotoRankInstructions(
      text.replace("identify these to the species level.", "drift"),
    )
  );
  assertThrows(() =>
    solPhotoRankInstructions(
      text + " when not alive — identify these to the species level.",
    )
  );
  const schema = structuredClone(baseline().text.format.schema);
  schema.properties!.scientific_name.description = "drift";
  assertThrows(() => solPhotoRankSchema(schema));
});

Deno.test("existing strict decoding and normalization retain synthetic species, genus, family and unresolved names without changing confidence", () => {
  for (
    const [name, biological] of [
      ["Syntheticus example", true],
      ["Syntheticus", true],
      ["Syntheticaceae", true],
      [null, true],
      [null, false],
    ] as const
  ) {
    const draft = decodeOpenAIDraft({
      ...openAIDraftFixture(),
      scientific_name: name,
      is_biological_subject: biological,
      candidates: [],
      ai_reasoning: "Invented evidence tests transport only.",
    });
    const result = normalizeIdentification(draft, {
      hasVisualEvidence: true,
      hasAudioEvidence: false,
      hasInvasiveLocationContext: false,
      confidencePolicy: { kind: "unqualified" },
    }).identification;
    assertEquals(result.scientific_name, name);
    assertEquals(result.is_biological_subject, biological);
    assertEquals(result.confidence_score, .99);
    assertEquals(
      result.ai_reasoning,
      "Invented evidence tests transport only.",
    );
  }
});

const taxonomy: ReviewedTaxonomy = {
  version: "evaluation_taxonomy_v2",
  taxonomyVersion: "synthetic-before-v1",
  catalogRef: "synthetic-before",
  reviewRef: "synthetic-before-review",
  taxa: [
    {
      taxon: { id: "synthetic:old", rank: "species" },
      canonicalName: "Syntheticus example",
      synonyms: ["Oldus example"],
    },
    {
      taxon: { id: "synthetic:kept", rank: "species" },
      canonicalName: "syntheticus   EXAMPLE",
      synonyms: ["Otherus example"],
    },
  ],
};
const corpus = () => ({
  version: "identification_exploratory_corpus_v1",
  id: "synthetic-before-v1",
  kind: "exploratory",
  evidenceOrigin: "synthetic",
  taxonomyVersion: taxonomy.taxonomyVersion,
  preparationVersion: "synthetic-v1",
  splitSeed: 42,
  eligibility: null,
  cases: [{
    input: { ...syntheticCorpus().cases[0].input, observationTexts: [] },
    provisionalReference: {
      subject: "biological" as const,
      resolution: "named" as const,
      supportedRank: "species" as const,
      acceptableTaxa: taxonomy.taxa.map((t) => t.taxon),
    },
    curation: { kind: "synthetic" },
  }],
});
async function remap(c = corpus(), t = taxonomy) {
  return {
    version: "photo_taxonomy_remap_v1" as const,
    sourceCorpusDigest: await fingerprintJson(c),
    sourceTaxonomyDigest: await fingerprintJson(t),
    corpusId: "synthetic-after-v1",
    taxonomyVersion: "synthetic-after-v1",
    catalogRef: "synthetic-after",
    reviewRef: "synthetic-after-review",
    merges: [{ from: "synthetic:old", to: "synthetic:kept" }],
  };
}

Deno.test("explicit catalog repair merges only reviewed equal-name/equal-rank IDs and rewrites references without changing their rank or source", async () => {
  const c = corpus(),
    t = structuredClone(taxonomy),
    original = structuredClone({ c, t });
  const result = await repairPhotoTaxonomy(c, t, await remap(c, t));
  assertEquals({ c, t }, original);
  assertEquals(result.taxonomy.taxa.length, 1);
  assertEquals(result.corpus.cases[0].input, c.cases[0].input);
  assertEquals(result.corpus.cases[0].provisionalReference, {
    ...c.cases[0].provisionalReference,
    acceptableTaxa: [taxonomy.taxa[1].taxon],
  });
  assertEquals(result.report.rewrittenReferences, 1);
  assertEquals(result.report.deduplicatedReferences, 1);
  assertEquals(result.report.audit.counts.nameCollisions, 0);
  assertEquals(result.report.referenceReviewComplete, false);
  for (
    const name of ["Syntheticus example", "Oldus example", "Otherus example"]
  ) {
    assertEquals(
      resolveTaxon(result.taxonomy, name).taxon?.id,
      "synthetic:kept",
    );
  }
  assertEquals(
    resolveTaxon(result.taxonomy, "Unreviewedus unknown").mapping.status,
    "unmapped",
  );
});

Deno.test("catalog remap rejects chains, cycles, extra fields, repeated sources and stale source digests", async () => {
  const value = await remap();
  for (
    const merges of [
      [{ from: "a", to: "a" }],
      [{ from: "a", to: "b" }, { from: "a", to: "c" }],
      [{ from: "a", to: "b" }, { from: "b", to: "c" }],
      [{ from: "a", to: "b" }, { from: "b", to: "a" }],
    ]
  ) assertThrows(() => parsePhotoTaxonomyRemap({ ...value, merges }));
  assertThrows(() =>
    parsePhotoTaxonomyRemap({ ...value, dispatchAuthorized: true })
  );
  await assertRejects(() =>
    repairPhotoTaxonomy(corpus(), taxonomy, {
      ...value,
      sourceCorpusDigest: "0".repeat(64),
    })
  );
  await assertRejects(() =>
    repairPhotoTaxonomy(corpus(), taxonomy, {
      ...value,
      taxonomyVersion: taxonomy.taxonomyVersion,
    })
  );
});

Deno.test("catalog repair rejects different canonical names, cross-rank homonyms, missing targets and any residual collision", async () => {
  for (const kind of ["name", "rank", "missing", "remaining"] as const) {
    const t = structuredClone(taxonomy), c = corpus();
    if (kind === "name") t.taxa[1].canonicalName = "Differentus example";
    if (kind === "rank") {
      t.taxa[1].taxon = { id: "synthetic:kept", rank: "genus" };
    }
    if (kind === "remaining") {
      t.taxa.push({
        ...t.taxa[0],
        taxon: { id: "synthetic:third", rank: "species" },
      });
    }
    const r = await remap(c, t);
    if (kind === "missing") r.merges[0].to = "missing";
    await assertRejects(() => repairPhotoTaxonomy(c, t, r));
  }
});

Deno.test("Sol rank live adapter sends the pinned request once with exact model and native moderation checks", async () => {
  for (
    const kind of [
      "allow",
      "wrong_model",
      "missing_moderation",
      "denied",
    ] as const
  ) {
    let calls = 0;
    let sent: unknown = null, url: unknown = null;
    const response = {
      ...openAIResponseFixture(),
      service_tier: "default",
      moderation: openAIPhotoModerationFixture(),
    };
    if (kind === "wrong_model") response.model = "gpt-6-luna";
    if (kind === "denied") {
      response.moderation.input.flagged = true;
      response.moderation.input.categories.violence = true;
    }
    const body = kind === "missing_moderation"
      ? openAIResponseFixture()
      : response;
    const fetcher = ((_url: unknown, options?: RequestInit) => {
      calls++;
      url = _url;
      sent = JSON.parse(String(options?.body));
      return Promise.resolve(
        new Response(JSON.stringify(body), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    }) as typeof fetch;
    const execution = createAIExecution(
      createOpenAISolRankEvaluationAdapter("synthetic-evaluation-key", fetcher),
      request,
      solPhotoRankSnapshot(request),
    );
    const result = await execution.invoke();
    assertEquals(url, "https://api.openai.com/v1/responses");
    assertEquals(sent, JSON.parse(JSON.stringify(candidate())));
    assertEquals(calls, 1);
    assertEquals(
      result.kind,
      kind === "allow"
        ? "draft"
        : kind === "denied"
        ? "refusal"
        : "invalid_output",
    );
    await assertRejects(() => execution.invoke());
    assertEquals(calls, 1);
  }
});
