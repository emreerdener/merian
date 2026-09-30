/** Invented identities, pixels and prices: mechanics only, never study evidence. */
import { join } from "node:path";
import { openAIDraftFixture } from "../../../functions/_shared/ai/testing/openaiFixtures.ts";
import type { AIProviderOutcome } from "../../../functions/_shared/ai/contracts.ts";
import { crc32 } from "../assets.ts";
import type { ConfidenceCase, ConfidenceCorpus } from "../confidenceCorpus.ts";
import { CONFIDENCE_PROTOCOL as P } from "../confidenceProtocol.ts";
import { assignConfidenceSplits } from "../confidenceSampling.ts";
import type { ConfidenceObservation } from "../confidenceScoring.ts";
import { fingerprintBytes } from "../evidence.ts";
import { atomicJson, privateDirectory } from "../files.ts";
import type { OpenAIPricing, SourceIdentity } from "../runContracts.ts";
import { noIdentityMapping, type ReviewedTaxonomy } from "../taxonomy.ts";

export const confidenceSource: SourceIdentity = {
  commit: "0".repeat(40),
  dirty: true,
  digest: "1".repeat(64),
  sdk: "synthetic",
};
export function confidenceFixture() {
  const taxonomy: ReviewedTaxonomy = {
    version: "evaluation_taxonomy_v2",
    taxonomyVersion: "synthetic-confidence-v1",
    catalogRef: "synthetic-catalog",
    reviewRef: "synthetic-review",
    taxa: [
      {
        taxon: { id: "synthetic:species", rank: "species" },
        canonicalName: "Syntheticus example",
        synonyms: ["Oldname example"],
      },
      {
        taxon: { id: "synthetic:genus", rank: "genus" },
        canonicalName: "Syntheticus",
        synonyms: [],
      },
      {
        taxon: { id: "synthetic:other", rank: "species" },
        canonicalName: "Syntheticus different",
        synonyms: [],
      },
    ],
  };
  const cases: ConfidenceCase[] = [];
  for (const split of ["development", "held_out"] as const) {
    for (const category of P.categories) {
      for (let j = 0; j < 20; j++) {
        const n = cases.length + 1, suffix = String(n).padStart(4, "0");
        const control = category === "nonbiological",
          unresolved = category === "limited" && j >= 10;
        const accepted = category === "limited"
          ? taxonomy.taxa[1].taxon
          : taxonomy.taxa[0].taxon;
        cases.push({
          category,
          taxaGroup: control
            ? "none"
            : category === "cultivated"
            ? "plant"
            : P.taxaGroups[Math.floor(j / 5)],
          input: {
            caseId: `c${suffix}`,
            groupId: `g${suffix}`,
            split,
            inputGroup: "photos",
            observationTexts: [],
            context: { deviceRegion: null, currentMonth: null },
            clips: [],
            assets: [{
              id: `a${suffix}`,
              path: `assets/a${suffix}.png`,
              kind: "image",
              mimeType: "image/png",
              sourceIndex: 0,
              byteLength: 128,
              sha256: n.toString(16).padStart(64, "0"),
            }],
          },
          reference: {
            subject: control ? "non_biological" : "biological",
            resolution: control || unresolved ? "unresolved" : "named",
            supportedRank: control || unresolved ? null : accepted.rank,
            acceptableTaxa: control || unresolved ? [] : [accepted],
          },
          curation: { kind: "synthetic" },
        });
      }
    }
  }
  const ordered = assignConfidenceSplits(cases).sort((a, b) =>
    a.input.split.localeCompare(b.input.split) ||
    P.categories.indexOf(a.category) - P.categories.indexOf(b.category) ||
    a.reference.resolution.localeCompare(b.reference.resolution) ||
    a.input.caseId.localeCompare(b.input.caseId)
  );
  const corpus: ConfidenceCorpus = {
    version: P.corpusVersion,
    kind: "synthetic",
    id: "synthetic-confidence-v1",
    splitSeed: P.splitSeed,
    taxonomyVersion: taxonomy.taxonomyVersion,
    referenceStatus: "valid",
    cases: ordered,
  };
  const observations: ConfidenceObservation[] = ordered.map((c) => ({
    prediction: {
      caseId: c.input.caseId,
      outcome: "normalized",
      subject: c.reference.subject,
      resolution: c.reference.resolution,
      taxon: c.reference.acceptableTaxa[0] ?? null,
      confidence: .84,
    },
    mapping: c.reference.resolution === "named"
      ? { status: "matched", match: "canonical" }
      : noIdentityMapping(),
  }));
  const pricing: OpenAIPricing = {
    version: "evaluation_openai_pricing_v1",
    provider: "openai",
    currency: "USD",
    service: "paid_standard_synchronous",
    retrievedAt: "2026-09-30T00:00:00.000Z",
    sourceUrl: "https://developers.openai.com/api/docs/models/gpt-6-sol",
    reviewRef: "synthetic-pricing",
    includesReasoning: true,
    models: [{
      model: "gpt-6-sol",
      inputPerMillion: { text: 1, image: 1, cached: 1, cacheWrite: 1 },
      outputPerMillion: 2,
      maxInputTokens: 1_050_000,
      maxBillableOutputTokens: 8192,
      limitsEvidenceRef: "synthetic-ceiling",
    }],
  };
  return { corpus, taxonomy, observations, pricing };
}
export function confidenceOutcome(c: ConfidenceCase): AIProviderOutcome {
  const name = c.reference.acceptableTaxa[0]?.rank === "genus"
    ? "Syntheticus"
    : "Syntheticus example";
  return {
    kind: "draft",
    draft: {
      ...openAIDraftFixture(),
      scientific_name: c.reference.resolution === "named" ? name : null,
      is_biological_subject: c.reference.subject === "biological",
      confidence_score: .84,
    },
    returnedModel: "gpt-6-sol",
    serviceTier: "default",
    providerDurationMs: 1,
    providerCompletedAt: 1,
    finishReason: "completed",
    responseCharacters: 10,
    usage: {
      promptTokens: 100,
      candidateTokens: 30,
      thinkingTokens: 10,
      totalTokens: 140,
      cachedTokens: 20,
      cacheWriteTokens: 0,
      toolTokens: 0,
      modalityBreakdown: {},
    },
  };
}
async function png(n: number) {
  const chunk = (kind: string, data: Uint8Array) => {
    const bytes = new Uint8Array(12 + data.length),
      view = new DataView(bytes.buffer);
    view.setUint32(0, data.length);
    bytes.set(new TextEncoder().encode(kind), 4);
    bytes.set(data, 8);
    view.setUint32(8 + data.length, crc32(bytes.subarray(4, 8 + data.length)));
    return bytes;
  };
  const header = new Uint8Array(13), view = new DataView(header.buffer);
  view.setUint32(0, 1);
  view.setUint32(4, 1);
  header[8] = 8;
  header[9] = 2;
  const raw = new Uint8Array([0, n % 256, Math.floor(n / 256), 127]);
  const compressed = new Uint8Array(
    await new Response(
      new Blob([raw]).stream()
        .pipeThrough(new CompressionStream("deflate")),
    ).arrayBuffer(),
  );
  const parts = [
    new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", header),
    chunk("IDAT", compressed),
    chunk("IEND", new Uint8Array()),
  ];
  const result = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}
export async function writeConfidenceFixture(root: string) {
  const fixture = confidenceFixture();
  await privateDirectory(join(root, "assets"));
  for (const [i, c] of fixture.corpus.cases.entries()) {
    const bytes = await png(i + 1), asset = c.input.assets[0];
    await Deno.writeFile(join(root, asset.path), bytes, {
      createNew: true,
      mode: 0o600,
    });
    c.input = {
      ...c.input,
      assets: [{
        ...asset,
        byteLength: bytes.length,
        sha256: await fingerprintBytes(bytes),
      }],
    };
  }
  await atomicJson(join(root, "confidence-corpus.json"), fixture.corpus);
  await atomicJson(join(root, "taxonomy.json"), fixture.taxonomy);
  await atomicJson(join(root, "pricing.json"), fixture.pricing);
  return fixture;
}
