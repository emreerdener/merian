/** Synthetic local timing only. Run with runtime network permission denied.
 * The cached native-request control intentionally excludes request preparation;
 * differences include that work, not just newly introduced wrapper overhead.
 */
import { assertEquals } from "@std/assert";
import type {
  AIRequest,
  UserRequestAuthority,
} from "../functions/_shared/ai/contracts.ts";
import { prepareAIExecution } from "../functions/_shared/ai/production.ts";
import { resolveAIClaim } from "../functions/_shared/ai/registry.ts";
import { buildGeminiRequest } from "../functions/_shared/ai/gemini.ts";
import { _genAI, extractJson } from "../functions/_shared/gemini.ts";

function fixtures(): { name: string; request: AIRequest }[] {
  // Byte-shaped transport fixtures, not decodable media or biological examples.
  const image = "AQID".repeat(65_536); // 192 KiB raw / 256 KiB base64.
  const audio = "AQID".repeat(21_845); // About 64 KiB raw.
  const text = {
    kind: "text" as const,
    order: 0 as const,
    source: "observation_context" as const,
    text: "Synthetic organism description.",
  };
  const still = {
    kind: "image" as const,
    order: 0,
    inputIndex: 0,
    mimeType: "image/webp",
    data: image,
    lineage: { kind: "image" as const, sourceIndex: 0 },
  };
  const wav = {
    kind: "audio" as const,
    order: 0,
    inputIndex: 0,
    mimeType: "audio/wav" as const,
    data: audio,
    lineage: { kind: "audio" as const, sourceIndex: 0 },
  };
  const capture = {
    hasVideo: false,
    videoClipCount: 0,
    declaredVideoFrameCount: 0,
    videoInferenceFrameCount: 0,
  };
  const main = {
    task: "identify" as const,
    variant: "multimodal" as const,
    capture,
  };
  return [
    {
      name: "description_compat",
      request: {
        task: "identify",
        variant: "description_compat",
        evidence: [{ ...text, source: "description" }],
      },
    },
    { name: "main_text", request: { ...main, evidence: [text] } },
    { name: "main_still", request: { ...main, evidence: [still] } },
    { name: "main_audio", request: { ...main, evidence: [wav] } },
    {
      name: "main_five_frames_and_audio",
      request: {
        ...main,
        capture: {
          hasVideo: true,
          videoClipCount: 1,
          declaredVideoFrameCount: 5,
          videoInferenceFrameCount: 5,
        },
        evidence: [
          ...Array.from({ length: 5 }, (_, index) => ({
            ...still,
            order: index,
            inputIndex: index,
            lineage: {
              kind: "video_frame" as const,
              clipIndex: 0,
              frameIndex: index,
            },
          })),
          { ...wav, order: 5, lineage: { kind: "video_audio", clipIndex: 0 } },
        ],
      },
    },
    {
      name: "vision_compat",
      request: {
        task: "identify",
        variant: "vision_compat",
        evidence: [still],
      },
    },
    {
      name: "audio_compat",
      request: { task: "identify", variant: "audio_compat", evidence: [wav] },
    },
    {
      name: "species_overview",
      request: {
        task: "species_overview",
        variant: "species_content",
        scientificName: "Synthetic species",
        locale: "en",
      },
    },
    {
      name: "lookalikes",
      request: {
        task: "lookalikes",
        variant: "species_content",
        scientificName: "Synthetic species",
        taxonomy: { kingdom: "Animalia", order: "SyntheticOrder" },
      },
    },
    {
      name: "group_tags",
      request: {
        task: "group_tags",
        variant: "species_content",
        scientificName: "Synthetic species",
      },
    },
  ];
}

function authority(request: AIRequest, model: string): UserRequestAuthority {
  const operations = {
    species_overview: "scan_overview_enrichment",
    lookalikes: "scan_lookalike_enrichment",
    group_tags: "scan_group_tag_enrichment",
  };
  return {
    kind: "user_request",
    userId: "synthetic-benchmark",
    permission: "google_gemini",
    operation: request.task !== "identify"
      ? operations[request.task]
      : request.variant === "audio_compat"
      ? "scan_audio_identification"
      : "scan_identification",
    reservation: {
      id: "synthetic-reservation",
      requestId: "synthetic-request",
      attemptCount: 1,
      policyVersion: 1,
      model,
      tier: { effective_tier: model === "gemini-2.5-pro" ? "pro" : "free" },
    },
  };
}

function percentiles(values: number[]) {
  const ordered = [...values].sort((a, b) => a - b);
  const pick = (fraction: number) =>
    Number(ordered[Math.ceil(fraction * ordered.length) - 1].toFixed(4));
  return { p50: pick(0.5), p95: pick(0.95) };
}

async function main() {
  if ((await Deno.permissions.query({ name: "net" })).state !== "denied") {
    throw new Error(
      "Run this benchmark with --deny-net; it never needs a network.",
    );
  }
  const samples = Deno.args.length ? Number(Deno.args[0]) : 250;
  if (
    Deno.args.length > 1 || !Number.isSafeInteger(samples) || samples < 50 ||
    samples > 2000
  ) {
    throw new Error("Expected an optional sample count from 50 to 2000.");
  }
  const environment = [
    "GEMINI_PAID_API_KEY",
    "GOOGLE_GENAI_USE_VERTEXAI",
    "GOOGLE_GENAI_USE_ENTERPRISE",
    "GOOGLE_GEMINI_BASE_URL",
  ];
  const saved = new Map(environment.map((name) => [name, Deno.env.get(name)]));
  const originalFetch = globalThis.fetch;
  const originalTimeout = globalThis.setTimeout;
  const timers: ReturnType<typeof setTimeout>[] = [];
  let dispatches = 0;
  let captureBodies = false;
  const bodies: string[] = [];
  const draft = {
    synthetic: true,
    description: "Synthetic response. ".repeat(128),
  };
  const response = JSON.stringify({
    candidates: [{
      content: { role: "model", parts: [{ text: JSON.stringify(draft) }] },
      finishReason: "STOP",
    }],
    usageMetadata: {
      promptTokenCount: 12,
      candidatesTokenCount: 8,
      totalTokenCount: 20,
    },
  });
  const results = [];
  const clearTimers = () => {
    for (const timer of timers.splice(0)) clearTimeout(timer);
  };
  try {
    for (const name of environment) Deno.env.delete(name);
    Deno.env.set("GEMINI_PAID_API_KEY", "synthetic-no-network-benchmark");
    globalThis.fetch = (input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      assertEquals(url.origin, "https://generativelanguage.googleapis.com");
      dispatches++;
      if (captureBodies) bodies.push(String(init?.body));
      return Promise.resolve(
        new Response(response, {
          headers: { "Content-Type": "application/json" },
        }),
      );
    };
    globalThis.setTimeout = ((handler, timeout, ...args) => {
      const timer = originalTimeout(handler, timeout, ...args);
      timers.push(timer);
      return timer;
    }) as typeof setTimeout;

    const measure = async (run: () => Promise<unknown>) => {
      const before = dispatches;
      const start = performance.now();
      const value = await run();
      const duration = performance.now() - start;
      clearTimers();
      assertEquals(dispatches - before, 1);
      assertEquals(value, draft);
      return duration;
    };
    for (const fixture of fixtures()) {
      for (const model of ["gemini-2.5-flash", "gemini-2.5-pro"]) {
        const context = authority(fixture.request, model);
        const native = buildGeminiRequest(
          fixture.request,
          resolveAIClaim(fixture.request, context),
        );
        const direct = async () => {
          const result = await _genAI.models.generateContent(native);
          return extractJson(result.text ?? "");
        };
        const shared = async () => {
          const result = await prepareAIExecution(fixture.request, context)
            .invoke();
          if (result.kind !== "draft") {
            throw new Error("Synthetic benchmark failed.");
          }
          return result.draft;
        };
        captureBodies = true;
        await measure(direct);
        await measure(shared);
        assertEquals(JSON.parse(bodies[0]), JSON.parse(bodies[1]));
        const requestBytes = new TextEncoder().encode(bodies[0]).length;
        bodies.length = 0;
        captureBodies = false;
        for (let i = 0; i < 25; i++) {
          await measure(direct);
          await measure(shared);
        }
        const directMs: number[] = [],
          sharedMs: number[] = [],
          deltaMs: number[] = [],
          prepareMs: number[] = [];
        for (let i = 0; i < samples; i++) {
          let directDuration: number, sharedDuration: number;
          if (i % 2 === 0) {
            directDuration = await measure(direct);
            sharedDuration = await measure(shared);
          } else {
            sharedDuration = await measure(shared);
            directDuration = await measure(direct);
          }
          directMs.push(directDuration);
          sharedMs.push(sharedDuration);
          deltaMs.push(sharedDuration - directDuration);
          const before = dispatches;
          const start = performance.now();
          prepareAIExecution(fixture.request, context);
          prepareMs.push(performance.now() - start);
          assertEquals(dispatches, before);
        }
        results.push({
          profile: fixture.name,
          model,
          samples,
          request_bytes: requestBytes,
          direct_cached_native_ms: percentiles(directMs),
          shared_prepare_invoke_ms: percentiles(sharedMs),
          paired_difference_ms: percentiles(deltaMs),
          prepare_only_ms: percentiles(prepareMs),
        });
      }
    }
    console.log(JSON.stringify(
      {
        format: "ai-boundary-local-v1",
        deno: Deno.version.deno,
        os: Deno.build.os,
        arch: Deno.build.arch,
        warmup_pairs: 25,
        network: "denied",
        cold_start: "excluded",
        control: "cached native request + real SDK + JSON extraction",
        scope:
          "canonical request through adapter; excludes HTTP admission, media preparation, DB, provider latency and client rendering",
        results,
      },
      null,
      2,
    ));
  } finally {
    clearTimers();
    globalThis.fetch = originalFetch;
    globalThis.setTimeout = originalTimeout;
    for (const [name, value] of saved) {
      if (value === undefined) Deno.env.delete(name);
      else Deno.env.set(name, value);
    }
  }
}

if (import.meta.main) await main();
