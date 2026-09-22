import { join } from "node:path";
import type { AIProviderOutcome } from "../../functions/_shared/ai/contracts.ts";
import { encodeWav16 } from "../../functions/audio-spec/wav.ts";
import { crc32 } from "./assets.ts";
import { type EvaluationCorpus, type EvaluationInput } from "./contracts.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import {
  EXPLORATORY_CORPUS_VERSION,
  EXPLORATORY_SPEC_VERSION,
  fingerprintRunCorpus,
  isSyntheticCorpus,
  parseExploratoryCorpus,
  type RunCorpus,
} from "./exploratory.ts";
import { atomicJson, privateDirectory } from "./files.ts";
import { syntheticCorpus } from "./fixtures.ts";
import {
  type Assignment,
  parseRunSpec,
  parseTaxonomy,
  type RunSpec,
  type Taxonomy,
} from "./runContracts.ts";
import {
  array,
  fields,
  id,
  member,
  requireCondition as check,
} from "./validation.ts";

export interface OfflineFixtures {
  version: "identification_offline_v1";
  corpusDigest: string;
  cases: { caseId: string; kind: AIProviderOutcome["kind"]; draft: unknown }[];
}
export function offlineOutcomes(
  value: unknown,
  corpus: RunCorpus,
  spec: RunSpec,
) {
  const v = fields(value, ["version", "corpusDigest", "cases"]);
  check(
    isSyntheticCorpus(corpus) && spec.mode === "offline" &&
      v.version === "identification_offline_v1" &&
      v.corpusDigest === spec.corpusDigest,
  );
  const cases = array(v.cases, 1, 240).map((raw) => {
    const c = fields(raw, ["caseId", "kind", "draft"]);
    id(c.caseId, "c");
    member(c.kind, [
      "draft",
      "refusal",
      "invalid_output",
      "operational_failure",
      "unknown_execution",
    ]);
    if (c.kind !== "draft") check(c.draft === null);
    return c as unknown as OfflineFixtures["cases"][number];
  });
  check(
    cases.length === spec.caseIds.length &&
      new Set(cases.map((c) => c.caseId)).size === cases.length &&
      cases.every((c) => spec.caseIds.includes(c.caseId)),
  );
  return (input: EvaluationInput, a: Assignment): AIProviderOutcome => {
    const c = cases.find((c) => c.caseId === input.caseId)!;
    const facts = {
      providerDurationMs: 0,
      providerCompletedAt: 0,
      returnedModel: a.model,
      usage: null,
      finishReason: null,
      responseCharacters: 0,
    };
    if (c.kind === "draft") {
      return { ...facts, kind: "draft", draft: structuredClone(c.draft) };
    }
    if (c.kind === "invalid_output") {
      return { ...facts, kind: "invalid_output", reason: "json" };
    }
    return { ...facts, kind: c.kind };
  };
}

/** Minimal invented RGB PNGs/WAV tones exercise loading, never quality. */
async function png(n: number): Promise<Uint8Array> {
  const chunk = (kind: string, data: Uint8Array) => {
    const bytes = new Uint8Array(12 + data.length),
      view = new DataView(bytes.buffer);
    view.setUint32(0, data.length);
    bytes.set(new TextEncoder().encode(kind), 4);
    bytes.set(data, 8);
    view.setUint32(8 + data.length, crc32(bytes.subarray(4, 8 + data.length)));
    return bytes;
  };
  const ihdr = new Uint8Array(13), view = new DataView(ihdr.buffer);
  view.setUint32(0, 1);
  view.setUint32(4, 1);
  ihdr[8] = 8;
  ihdr[9] = 2;
  const raw = new Uint8Array([0, n % 256, Math.floor(n / 256), 127]);
  const compressed = new Uint8Array(
    await new Response(
      new Blob([raw]).stream().pipeThrough(new CompressionStream("deflate")),
    ).arrayBuffer(),
  );
  const chunks = [
    new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ihdr),
    chunk("IDAT", compressed),
    chunk("IEND", new Uint8Array()),
  ];
  const result = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let at = 0;
  for (const c of chunks) {
    result.set(c, at);
    at += c.length;
  }
  return result;
}
export async function createDemo(
  root: string,
  exploratory = false,
): Promise<void> {
  await privateDirectory(root);
  const assets = await privateDirectory(join(root, "assets"));
  const original = syntheticCorpus(), cases = [];
  for (const c of original.cases) {
    const prepared = [];
    for (const a of c.input.assets) {
      const n = Number(a.id.slice(1)), audio = a.mimeType === "audio/wav";
      const samples = Float32Array.from(
        { length: 16000 },
        (_, i) => .3 * Math.sin(2 * Math.PI * (200 + n) * i / 16000),
      );
      const bytes = audio
        ? new Uint8Array(encodeWav16(samples, 16000))
        : await png(n);
      const file = `${a.id}.${audio ? "wav" : "png"}`;
      await Deno.writeFile(join(assets, file), bytes, {
        createNew: true,
        mode: 0o600,
      });
      prepared.push({
        ...a,
        path: `assets/${file}`,
        mimeType: audio ? "audio/wav" as const : "image/png" as const,
        byteLength: bytes.length,
        sha256: await fingerprintBytes(bytes),
      });
    }
    cases.push({ ...c, input: { ...c.input, assets: prepared } });
  }
  let corpus: RunCorpus = {
    ...original,
    preparationVersion: "synthetic-prepared-v1",
    cases,
  } as EvaluationCorpus;
  if (exploratory) {
    corpus = parseExploratoryCorpus({
      version: EXPLORATORY_CORPUS_VERSION,
      id: "synthetic-exploratory-v1",
      kind: "exploratory",
      evidenceOrigin: "synthetic",
      eligibility: null,
      taxonomyVersion: corpus.taxonomyVersion,
      preparationVersion: corpus.preparationVersion,
      splitSeed: corpus.splitSeed,
      cases: corpus.cases.map((c, i) => ({
        input: c.input,
        provisionalReference: i % 2 === 0 ? c.reference : null,
        curation: { kind: "synthetic" },
      })),
    });
  }
  const names = [
    "Syntheticus primus",
    "Syntheticus secundus",
    "Syntheticus tertius",
    "Syntheticus quartus",
    "Syntheticus quintus",
    "Syntheticus sextus",
    "Syntheticus septimus",
    "Syntheticus octavus",
    "Syntheticus nonus",
    "Syntheticus decimus",
    "Syntheticus undecimus",
    "Syntheticus duodecimus",
  ];
  const taxonomy: Taxonomy = parseTaxonomy({
    version: "evaluation_taxonomy_v1",
    taxonomyVersion: corpus.taxonomyVersion,
    taxa: [
      ...names.map((name, i) => ({
        taxon: {
          id: `synthetic:${i + 1}`,
          rank: i === 1 ? "genus" : "species",
        },
        names: [name],
      })),
      {
        taxon: { id: "synthetic:2-species", rank: "species" },
        names: ["Syntheticus overspecificus"],
      },
    ],
  });
  const digest = await fingerprintRunCorpus(corpus);
  const spec = parseRunSpec({
    version: exploratory
      ? EXPLORATORY_SPEC_VERSION
      : "identification_run_spec_v1",
    runId: exploratory ? "offline-exploratory-v1" : "offline-demo-v1",
    mode: "offline",
    corpusDigest: digest,
    taxonomyDigest: await fingerprintJson(taxonomy),
    split: "development",
    stage: exploratory ? "exploratory" : "development",
    profiles: ["gemini_flash_free", "gemini_pro"],
    caseIds: corpus.cases.map((c) => c.input.caseId),
    repeats: 1,
    orderSeed: 42,
    maxCalls: 24,
    budgetUsd: 0,
    pricingDigest: null,
    readinessDigest: null,
  });
  const fixtures: OfflineFixtures = {
    version: "identification_offline_v1",
    corpusDigest: digest,
    cases: corpus.cases.map((c, i) => ({
      caseId: c.input.caseId,
      kind: i === 2
        ? "refusal"
        : i === 4
        ? "invalid_output"
        : i === 6
        ? "operational_failure"
        : i === 10
        ? "unknown_execution"
        : "draft",
      draft: [2, 4, 6, 10].includes(i) ? null : {
        is_biological_subject: i !== 9,
        is_live_capture: true,
        scientific_name: i === 8 || i === 9
          ? undefined
          : i === 1
          ? "Syntheticus overspecificus"
          : names[i],
        common_name: i === 8
          ? "Unidentified Wildlife"
          : i === 9
          ? "Synthetic object"
          : names[i],
        confidence_score: i === 8 ? 0 : i === 3 ? .90 : .99,
        ai_reasoning: "Invented offline fixture.",
        extracted_visual_traits: ["Invented fixture trait."],
        candidates: [],
        image_quality: {
          sharpness: 1,
          framing: 1,
          diagnostic_utility: 1,
          overall_score: 0,
        },
        ...(c.input.inputGroup === "audio"
          ? {
            audio_subject_type: i === 8
              ? "unidentified_non_human"
              : "identified_non_human",
          }
          : {}),
      },
    })),
  };
  await atomicJson(join(root, "corpus.json"), corpus);
  await atomicJson(join(root, "taxonomy.json"), taxonomy);
  await atomicJson(join(root, "spec.json"), spec);
  await atomicJson(join(root, "fixtures.json"), fixtures);
}
