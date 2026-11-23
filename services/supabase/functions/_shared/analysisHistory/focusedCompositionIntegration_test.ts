import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { compositionSourceReservationRepository } from "./compositionSourceReservationRepository.ts";
import { compositionEvidenceRepository } from "./compositionEvidenceRepository.ts";
import {
  compositionSourceIdentity,
  parseCompositionSourceReservationRequest,
} from "./compositionSourceReservation.ts";
import {
  compositionEvidenceIdentity,
  decodeCompositionEvidenceReceipt,
} from "./compositionEvidence.ts";
import {
  compositionRequestFingerprint,
  focusedCompositionRequestDigest,
} from "./compositionFingerprint.ts";
import { compositionCohortItems } from "./compositionCohort.ts";
import { compositionByteFixture } from "./compositionByteTestFixtures.ts";
import { materializeCompositionAnalysis } from "./compositionMaterialization.ts";
import { executeCompositionAnalysis } from "./compositionExecution.ts";
import type { AnalysisExecutionDependencies } from "./execution.ts";
import { buildGeminiRequestParameters } from "../ai/geminiRequest.ts";
import { identificationProvenance } from "../ai/provenance.ts";
import { identificationMetricsAreGeminiCompatible } from "../ai/metricCompatibility.ts";
import { prepareMultimodalResultPolicy } from "../ai/multimodalResultPolicy.ts";
import { resolveAIClaim } from "../ai/registry.ts";
import { identificationInputProfile } from "../ai/identificationInput.ts";
import vectors from "./fixtures/composition-request-v6.json" with {
  type: "json",
};
const bytes = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value));
const signal = () => new AbortController().signal;
const owner = "00000000-0000-4000-8000-000000009000";
async function candidate(input: unknown) {
  return {
    schema_version: 3,
    input,
    fingerprint_version: 2,
    fingerprint: await compositionRequestFingerprint(input),
  };
}
Deno.test("focused source and evidence RPCs bind reader15 and reject crossed pairs before RPC", async () => {
  for (const vector of vectors) {
    const original = await candidate(vector.input);
    const identity = await compositionSourceIdentity(original);
    const calls: Record<string, unknown>[] = [];
    const receipt = {
      ...identity,
      owner_id: owner,
      state: "allocated",
      expires_at: "2027-01-01T00:00:00.000Z",
      items: compositionCohortItems(vector.input).map((item, i) => ({
        ...item,
        object_id: `00000000-0000-4000-8000-${
          String(8000 + i).padStart(12, "0")
        }`,
        ready_at: null,
      })),
    };
    const client = {
      rpc(routine: string, args: Record<string, unknown>) {
        calls.push(args);
        return {
          abortSignal() {
            return Promise.resolve({
              data: routine.endsWith("evidence")
                ? receipt
                : { ...identity, owner_id: owner, state: "reserved" },
              error: null,
            });
          },
        };
      },
    } as unknown as SupabaseClient;
    const source = compositionSourceReservationRepository(client);
    await source.reserve(owner, original, signal());
    await source.recover(owner, original, signal());
    await compositionEvidenceRepository(client).reserve(
      owner,
      original,
      signal(),
    );
    assertEquals(calls.map((c) => c.p_reader), [15, 15, 15]);
    assertEquals(calls[1].p_request, identity);
    assertEquals(identity.fingerprint_version, 2);
    await assertRejects(() =>
      source.reserve(owner, { ...original, fingerprint_version: 1 }, signal())
    );
    await assertRejects(() =>
      source.reserve(owner, {
        ...original,
        input: { ...vector.input, request_digest: "0".repeat(64) },
      }, signal())
    );
    assertEquals(calls.length, 3);
    await assertRejects(() =>
      decodeCompositionEvidenceReceipt(
        bytes({ ...receipt, fingerprint_version: 1 }),
        vector.input,
        owner,
      )
    );
    await assertRejects(() =>
      parseCompositionSourceReservationRequest({
        ...original,
        fingerprint_version: 3,
      })
    );
  }
});

Deno.test("focused recovered outcome rejects a forged typed digest before any advance", async () => {
  let calls = 0;
  const unexpected = () => {
    calls++;
    throw new Error("must not advance");
  };
  const deps = {
    advance: unexpected,
    prepare: unexpected,
    resolveSpecies: unexpected,
  } as AnalysisExecutionDependencies;
  await assertRejects(() =>
    executeCompositionAnalysis({
      state: "dispatched",
      claimed: true,
      input: { ...vectors[0].input, request_digest: "0".repeat(64) },
      quota: {},
      provider_outcome: {},
    }, deps)
  );
  assertEquals(calls, 0);
});

Deno.test("verified focused photo/audio preserves order and sends adjacent bounded intent to Gemini", async () => {
  const f = await compositionByteFixture(false);
  const focus = {
    x: 0.2,
    y: 0.3,
    width: 0.4,
    height: 0.5,
    source: "user_selection" as const,
  };
  const input = {
    ...f.input,
    schema_version: 6,
    evidence_manifest: {
      schema_version: 6,
      items: f.input.evidence_manifest.items.map((node) =>
        node.kind === "image" ? { ...node, focus_region: focus } : node
      ),
    },
  };
  input.request_digest = await focusedCompositionRequestDigest(input);
  const receipt = { ...f.receipt, ...await compositionEvidenceIdentity(input) };
  const request = await materializeCompositionAnalysis(
    input,
    owner,
    bytes(receipt),
    { read: (item) => Promise.resolve(f.bytes.get(item.media_id)!) },
    signal(),
  );
  const image = request.evidence.find((item) => item.kind === "image")!;
  assert(image.kind === "image");
  assertEquals(image.focusRegion, focus);
  const snapshot = resolveAIClaim(request, {
    kind: "user_request",
    userId: owner,
    permission: "google_gemini",
    operation: "scan_identification",
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 7,
      model: "gemini-2.5-flash",
      tier: { effective_tier: "free" },
      assignment: {
        inputProfile: identificationInputProfile(request),
        provider: "gemini",
        binding: "gemini_baseline_v1",
        permission: "google_gemini",
      },
    },
  });
  assertEquals(snapshot.prompt, "identify_blended_focus_v1");
  assertEquals(
    prepareMultimodalResultPolicy(snapshot).confidence.kind,
    "unqualified",
  );
  assertEquals(
    identificationMetricsAreGeminiCompatible(
      identificationProvenance(snapshot),
      "flash",
    ),
    false,
  );
  assertThrows(() =>
    buildGeminiRequestParameters(request, {
      ...snapshot,
      prompt: "identify_blended_v1",
    })
  );
  const withoutFocus = {
    ...request,
    evidence: request.evidence.map((item) => {
      if (item.kind !== "image") return item;
      const { focusRegion: _focus, ...plain } = item;
      return plain;
    }),
  };
  assertThrows(() => buildGeminiRequestParameters(withoutFocus, snapshot));
  const legacy = buildGeminiRequestParameters(withoutFocus, {
    ...snapshot,
    prompt: "identify_blended_v1",
  });
  assertEquals(legacy.contents, [{
    role: "user",
    parts: withoutFocus.evidence.map((item) =>
      item.kind === "text"
        ? { text: item.text }
        : { inlineData: { mimeType: item.mimeType, data: item.data } }
    ),
  }]);
  const twoImages = {
    ...request,
    evidence: [
      { ...image, data: "first-synthetic-image" },
      {
        ...image,
        order: 1,
        inputIndex: 1,
        data: "second-synthetic-image",
        focusRegion: { ...focus, x: 0.1 },
      },
    ],
  };
  const pair = buildGeminiRequestParameters(twoImages, {
    ...snapshot,
    prompt: "identify_vision_focus_v1",
  }).contents as {
    parts: { text?: string; inlineData?: { data: string } }[];
  }[];
  assertEquals(pair[0].parts.length, 4);
  assert(pair[0].parts[0].text?.includes('"x":0.2'));
  assertEquals(pair[0].parts[1].inlineData?.data, "first-synthetic-image");
  assert(pair[0].parts[2].text?.includes('"x":0.1'));
  assertEquals(pair[0].parts[3].inlineData?.data, "second-synthetic-image");
  const parameters = buildGeminiRequestParameters(request, snapshot);
  const contents = parameters.contents as {
    parts: { text?: string; inlineData?: unknown }[];
  }[];
  const parts = contents[0].parts;
  assertEquals(parts.length, request.evidence.length + 1);
  const marker = parts.findIndex((p) =>
    p.text?.startsWith("The user selected")
  );
  assert(marker >= 0 && parts[marker + 1].inlineData !== undefined);
  assert(parts[marker].text?.includes('"x":0.2'));
  const auto = {
    ...request,
    evidence: request.evidence.map((item) =>
      item.kind === "image"
        ? {
          ...item,
          focusRegion: { ...focus, source: "vision_objectness" as const },
        }
        : item
    ),
  };
  assert(
    JSON.stringify(buildGeminiRequestParameters(auto, snapshot)).includes(
      "only a hint",
    ),
  );
  const invalid = {
    ...request,
    evidence: request.evidence.map((item) =>
      item.kind === "image"
        ? { ...item, focusRegion: { ...focus, width: 2 } }
        : item
    ),
  };
  assertThrows(() => buildGeminiRequestParameters(invalid, snapshot));
  await assertRejects(() =>
    materializeCompositionAnalysis(input, owner, bytes(receipt), {
      read: () => Promise.resolve(new Uint8Array([9])),
    }, signal())
  );
});
