import type { SupabaseClient } from "@supabase/supabase-js";
import type { AIQuotaReservation } from "../aiQuota.ts";
import { identificationProvenance } from "../ai/provenance.ts";
import { prepareInitialAccountedIdentification } from "./dispatchAccounting.ts";
import {
  type CapturedInitialResult,
  captureInitialResult,
  persistInitialResult,
} from "./resultEvidence.ts";
import { data as syntheticResult } from "./fixtures/resultEvidence.ts";
import { cpmCompletionAdmissionFixture } from "./fixtures/cpmCompletionAdmission.ts";
import { assert, assertEquals, assertRejects } from "@std/assert";
import { GoogleGenAI } from "@google/genai";
import { decodeBase64, encodeBase64 } from "../encoding.ts";
import { syntheticOriginalPhotoSnapshot as snapshot } from "./fixtures/cpmPhotoExecutionRequest.ts";
import { safeJpeg } from "../analysisHistory/testing/publicPhotoFixtures.ts";
import { initialCanonicalText } from "./canonical.ts";
import { fixture, hash } from "./cpmPhotoAdmissionTestFixtures.ts";
import { initialCpmPhotoCandidateDigest } from "./cpmPhotoCandidate.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import { createInitialCpmPhotoRequestPreparer } from "./cpmPhotoExecutionRequest.ts";

const id = (n: number) =>
  "00000000-0000-4000-8000-" + String(n).padStart(12, "0");
async function example(
  count: number,
  contexts: string[],
  locale = "en",
  malformed = false,
) {
  const photos = Array.from({ length: count }, (_, i) => {
    const bytes = safeJpeg().slice();
    bytes[7] = i + 1; // first quantization value; distinct valid JPEGs
    if (malformed) bytes[0] = 0;
    return { objectID: id(501 + 3 * i), bytes };
  });
  const f = await fixture(async (candidate, assignment) => {
    const content = JSON.parse(candidate.content_canonical);
    content.contexts = contexts.map((text) => ({
      text_utf8_base64: encodeBase64(new TextEncoder().encode(text)),
    }));
    const first = content.photos[0];
    content.photos = [];
    const roles = ["source", "ai", "display"] as const;
    assignment.preparation.role_mapping = [];
    for (const [i, photo] of photos.entries()) {
      const p = structuredClone(first);
      p.ordinal = i;
      p.ai.byte_count = photo.bytes.length;
      p.ai.sha256 = await initialMediaHash(photo.bytes);
      for (const [j, role] of roles.entries()) {
        p[role].reference_id = id(400 + 3 * i + j);
        assignment.preparation.role_mapping.push({
          photo_ordinal: i,
          role,
          object_id: id(500 + 3 * i + j),
          declaration: p[role],
        });
      }
      content.photos.push(p);
    }
    Object.assign(assignment.configuration, {
      provider_model: snapshot.model,
      effective_model: snapshot.model,
      binding: snapshot.binding,
      output_language: locale,
    });
    candidate.content_canonical = initialCanonicalText(content);
    assignment.content_digest = await initialCpmPhotoContentDigest(content);
    assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
      candidate,
    );
  });
  const backend = {
    generation: f.snapshot.backend_generation,
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_only",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const digest = await hash(
    "merian.initial-analysis.media.backend.v1",
    initialCanonicalText(backend),
  );
  const saved = {
    ...f.identity,
    backend_generation: backend.generation,
    backend_configuration_digest: digest,
  };
  const a = JSON.parse(saved.assignment_canonical);
  const policy = { ...a.preparation };
  delete policy.role_mapping;
  const dim = {
    maximumWidth: 4096,
    maximumHeight: 4096,
    maximumPixels: 4096 ** 2,
  };
  const profile = {
    configurationCanonical: initialCanonicalText(a.configuration),
    preparationPolicyCanonical: initialCanonicalText(policy),
    verification: {
      profile_digest: policy.profile_digest,
      verifier_build_digest: policy.verifier_build_digest,
      dimensions: { source: dim, ai: dim, display: dim },
      backend: { ...backend, configuration_digest: digest },
    },
    snapshot: structuredClone(snapshot),
  };
  const base = await cpmCompletionAdmissionFixture();
  const content = JSON.parse(
    JSON.parse(saved.candidate_canonical).content_canonical,
  );
  const admission = {
    ...base.admission,
    owner_id: saved.owner_id,
    scan_id: saved.scan_id,
    route: a.configuration.route,
    submission_digest: a.content_digest,
    ordered_description_count: contexts.length,
    ordered_description_digest: await hash(
      "merian.initial-analysis.cpm-photo-contexts.v1",
      initialCanonicalText(content.contexts),
    ),
  };
  const reply = {
    ...base.reply,
    owner_id: saved.owner_id,
    scan_id: saved.scan_id,
    candidate_digest: a.candidate_digest,
    assignment_digest: saved.assignment_digest,
    backend_generation: saved.backend_generation,
    backend_configuration_digest: digest,
    admission_canonical: initialCanonicalText(admission),
  };
  return { photos, saved, profile, reply, admission };
}

Deno.test("original CPM stills and exact contexts reach the existing Gemini wire serializer", async (t) => {
  for (
    const [count, contexts] of [[1, []], [1, ["lost-grant"]], [2, [
      '\uFEFFquoted "🐾"\u0000\n',
      "e\u0301",
      "e\u0301",
      "",
    ]]] as const
  ) {
    await t.step(
      String(count) + " photo(s), " + contexts.length + " contexts",
      async () => {
        const f = await example(count, [...contexts]);
        const expected = await Promise.all(
          f.photos.map((p) => initialMediaHash(p.bytes)),
        );
        const prepare = createInitialCpmPhotoRequestPreparer(f.profile);
        const prepared = prepare(
          f.saved,
          f.reply,
          f.photos,
          new AbortController().signal,
        );
        // Neither the caller's photos nor a later catalog edit may change these parameters.
        f.photos.forEach((p) => p.bytes.fill(42));
        f.profile.snapshot = {
          ...snapshot,
          generation: { ...snapshot.generation, seed: undefined },
        };
        const { binding, parameters, snapshot: usedSnapshot } = await prepared;
        assertEquals(binding, {
          owner_id: f.saved.owner_id,
          scan_id: f.saved.scan_id,
          submission_digest: f.admission.submission_digest,
          config_digest: f.admission.config_digest,
          funding_binding_id: f.admission.funding_binding_id,
          funding_binding_digest: f.admission.funding_binding_digest,
          admission_receipt_id: f.reply.admission_receipt_id,
          admission_receipt_digest: f.reply.admission_receipt_digest,
        });
        const params = JSON.parse(parameters);
        const projection = {
          ...syntheticResult(),
          scan_id: binding.scan_id,
          inference_tier: "pro",
          identification_provenance: identificationProvenance(usedSnapshot),
        };
        let sent = 0;
        const originalFetch = globalThis.fetch;
        try {
          globalThis.fetch = async (input, init) => {
            const url = new URL(
              input instanceof Request ? input.url : String(input),
            );
            assertEquals(url.hostname, "generativelanguage.googleapis.com");
            assertEquals(
              url.pathname.endsWith("/models/gemini-2.5-pro:generateContent"),
              true,
            );
            const body = JSON.parse(String(init?.body)),
              parts = body.contents[0].parts;
            assertEquals(parts.length, count + 1);
            assertEquals(
              body.systemInstruction.parts.some((p: { text: string }) =>
                p.text.includes("Respond in English.")
              ),
              true,
            );
            assertEquals(body.generationConfig.seed, 42);
            for (let i = 0; i < count; i++) {
              assertEquals(parts[i].inlineData.mimeType, "image/jpeg");
              assertEquals(
                await initialMediaHash(
                  decodeBase64(parts[i].inlineData.data).slice(),
                ),
                expected[i],
              );
            }
            assertEquals(parts[count], {
              text: "Observation-wide supporting descriptions (JSON):\n" +
                JSON.stringify(contexts),
            });
            sent++;
            return Response.json({
              candidates: [{
                content: {
                  role: "model",
                  parts: [{ text: JSON.stringify(projection) }],
                },
              }],
            });
          };
          // Fake credential and intercepted transport only. Run with --deny-net.
          const sdk = new GoogleGenAI({ apiKey: "synthetic-only" });
          // Exercise the existing one-shot accounting/result owners with local
          // synthetic decisions. No installed executable or funded service exists here.
          const invocation = id(701), signal = new AbortController().signal;
          let reports = 0, commits = 0;
          const start = (lost: boolean) =>
            prepareInitialAccountedIdentification({
              client: {
                rpc() {
                  throw new Error("unexpected ordinary accounting");
                },
              } as unknown as SupabaseClient,
              reservation: {
                id: id(702),
                leaseToken: id(703),
                requestId: binding.scan_id,
                attemptCount: 1,
              } as AIQuotaReservation,
              binding,
              caller: signal,
              origin: "http://127.0.0.1",
              serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join(
                "_",
              ),
              executionEvidence: initialCanonicalText({
                version: 1,
                synthetic_only: true,
              }),
              execution: {
                snapshot: usedSnapshot,
                invoke: async () => {
                  const response = await sdk.models.generateContent(params);
                  return {
                    kind: "draft",
                    draft: JSON.parse(response.text!),
                    execution: { ...usedSnapshot, durationMs: 1 },
                    providerDurationMs: 1,
                    providerCompletedAt: 1000,
                    returnedModel: usedSnapshot.model,
                    usage: null,
                    finishReason: "STOP",
                    responseCharacters: response.text!.length,
                  };
                },
              },
              fetcher: (url, init) => {
                const args = JSON.parse(String(init?.body));
                assertEquals(args.p_owner, binding.owner_id);
                assertEquals(args.p_scan, binding.scan_id);
                if (
                  String(url).endsWith("/authorize_initial_analysis_dispatch")
                ) {
                  commits++;
                  assertEquals(
                    JSON.parse(args.p_expected).funding_binding_id,
                    binding.funding_binding_id,
                  );
                  if (lost) {
                    return Promise.reject(new Error("synthetic unknown grant"));
                  }
                  return Promise.resolve(
                    Response.json({
                      version: 1,
                      owner_id: binding.owner_id,
                      scan_id: binding.scan_id,
                      submission_digest: binding.submission_digest,
                      admission_receipt_id: binding.admission_receipt_id,
                      admission_receipt_digest:
                        binding.admission_receipt_digest,
                      outcome: "fresh",
                      invocation_id: invocation,
                    }),
                  );
                }
                assertEquals(
                  String(url).endsWith("/report_initial_analysis_usage"),
                  true,
                );
                assertEquals(args.p_invocation, invocation);
                reports++;
                return Promise.reject(
                  new Error("synthetic lost usage acknowledgement"),
                );
              },
            });
          // Separate scenarios. An uncertain grant never reaches the SDK.
          if (contexts[0] === "lost-grant") {
            const uncertain = start(true);
            await assertRejects(() => uncertain.invoke());
            await assertRejects(() => uncertain.invoke());
            assertEquals({ sent, reports, commits }, {
              sent: 0,
              reports: 0,
              commits: 1,
            });
            return;
          }
          const run = start(false);
          const result = await run.invoke();
          if (result.outcome.kind !== "draft") {
            throw new Error("expected synthetic draft");
          }
          const captured = await captureInitialResult({
            binding,
            invocationId: result.invocationId,
            resultEvidenceId: id(704),
            outcome: result.outcome,
            data: result.outcome.draft,
          });
          let durable: CapturedInitialResult | null = null,
            writes = 0,
            reads = 0;
          assertEquals(
            await persistInitialResult(
              {
                write: (value) => {
                  writes++;
                  durable = { ...value };
                  return Promise.reject(
                    new Error("synthetic lost result acknowledgement"),
                  );
                },
                read: () => {
                  reads++;
                  return Promise.resolve(durable);
                },
              },
              captured,
              signal,
            ),
            "stored",
          );
          assertEquals(captured.reference.invocation_id, invocation);
          assertEquals(
            captured.reference.funding_binding_digest,
            binding.funding_binding_digest,
          );
          await assertRejects(() => run.invoke());
          assertEquals({ commits, sent, reports, writes, reads }, {
            commits: 1,
            sent: 1,
            reports: 1,
            writes: 1,
            reads: 1,
          });
        } finally {
          globalThis.fetch = originalFetch;
        }
      },
    );
  }
});

Deno.test("CPM preparation rejects substituted bytes, identity, structure, profile and caller", async () => {
  const f = await example(2, []),
    prepare = createInitialCpmPhotoRequestPreparer(f.profile);
  const signal = new AbortController().signal;
  for (
    const photos of [
      [],
      f.photos.slice(0, 1),
      [...f.photos].reverse(),
      [f.photos[0], f.photos[0]],
      [{ ...f.photos[0], bytes: f.photos[1].bytes }, f.photos[1]],
      [{ ...f.photos[0], objectID: id(500) }, f.photos[1]],
    ]
  ) {
    await assertRejects(() => prepare(f.saved, f.reply, photos, signal));
  }
  await assertRejects(() =>
    prepare(
      { ...f.saved, assignment_digest: "0".repeat(64) },
      f.reply,
      f.photos,
      signal,
    )
  );
  await assertRejects(() =>
    prepare(
      { ...f.saved, backend_configuration_digest: "0".repeat(64) },
      f.reply,
      f.photos,
      signal,
    )
  );
  assert(f.profile.snapshot.binding === "gemini_baseline_v1");
  const wrongModel = createInitialCpmPhotoRequestPreparer({
    ...f.profile,
    snapshot: { ...f.profile.snapshot, model: "gemini-2.5-flash" },
  });
  await assertRejects(() => wrongModel(f.saved, f.reply, f.photos, signal));
  await assertRejects(() =>
    prepare(f.saved, { ...f.reply, owner_id: id(900) }, f.photos, signal)
  );
  await assertRejects(() =>
    prepare(f.saved, f.reply, [{
      ...f.photos[0],
      bytes: new Uint8Array(5 * 1048576 + 1),
    }], signal)
  );
  const fr = await example(1, [], "fr");
  await assertRejects(() =>
    createInitialCpmPhotoRequestPreparer(fr.profile)(
      fr.saved,
      fr.reply,
      fr.photos,
      signal,
    )
  );
  const bad = await example(1, [], "en", true);
  await assertRejects(() =>
    createInitialCpmPhotoRequestPreparer(bad.profile)(
      bad.saved,
      bad.reply,
      bad.photos,
      signal,
    )
  );
  await assertRejects(() =>
    prepare(f.saved, f.reply, f.photos, AbortSignal.abort())
  );
});
