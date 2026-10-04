import { assert, assertEquals, assertRejects } from "@std/assert";
import { evidenceDigest } from "./evidence.ts";
import {
  PHOTO_CLASSIFIER_MAX_BYTES,
  preparePublicationPhotoClassifier,
  type PublicationPhotoSource,
} from "./photoClassifier.ts";

const png = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0]);
async function fixture(bytes = png, content_type = "image/png") {
  const source: PublicationPhotoSource = {
    media_id: "00000000-0000-4000-8000-000000000001",
    object_id: "00000000-0000-4000-8000-000000000002",
    content_type,
    byte_count: bytes.length,
    sha256: await evidenceDigest(bytes),
  };
  return {
    source,
    deps: {
      apiKey: () => "synthetic-key",
      readSource: () => Promise.resolve(bytes),
    },
  };
}
function output(
  decision = "allow",
  confidence = 0.99,
  categories: string[] = [],
) {
  return {
    modelVersion: "gemini-2.5-flash",
    candidates: [{
      finishReason: "STOP",
      content: {
        role: "model",
        parts: [{ text: JSON.stringify({ decision, confidence, categories }) }],
      },
    }],
    usageMetadata: {
      promptTokenCount: 100,
      candidatesTokenCount: 10,
      totalTokenCount: 110,
    },
  };
}
const response = (value: unknown) => Response.json(value);
Deno.test("photo classifier freezes verified bytes and proof before one provider call", async () => {
  const bytes = png.slice();
  const f = await fixture(bytes);
  let calls = 0;
  let sent = "";
  const prepared = await preparePublicationPhotoClassifier(f.source, {
    ...f.deps,
    fetcher: (_url, init) => {
      calls++;
      assertEquals(
        String(_url),
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
      );
      assertEquals(init?.redirect, "error");
      assert(init?.signal);
      assertEquals(
        new Headers(init?.headers).get("x-goog-api-key"),
        "synthetic-key",
      );
      sent = init?.body as string;
      return Promise.resolve(response(output()));
    },
  });
  assertEquals(calls, 0);
  assert(Object.isFrozen(prepared.proof));
  assert(Object.isFrozen(prepared.proof.source));
  const original = { ...f.source };
  f.source.object_id = "mutated";
  bytes.fill(0);
  assertEquals(await prepared.invoke(), {
    decision: "approved",
    classification: "allow",
    confidence: 0.99,
    categories: [],
    model: "gemini-2.5-flash",
    usage: { input_tokens: 100, output_tokens: 10, total_tokens: 110 },
  });
  assertEquals(prepared.proof.source, original);
  assertEquals(
    await evidenceDigest(new TextEncoder().encode(JSON.stringify({
      method: "POST",
      endpoint:
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
      body_sha256: await evidenceDigest(new TextEncoder().encode(sent)),
    }))),
    prepared.proof.request_sha256,
  );
  for (
    const secret of [
      original.object_id,
      original.media_id,
      original.sha256,
      "synthetic-key",
    ]
  ) assert(!sent.includes(secret));
  assertEquals(JSON.parse(sent).contents[0].parts[1].inlineData, {
    mimeType: "image/png",
    data: "iVBORw0KGgoA",
  });
  await assertRejects(
    () => prepared.invoke(),
    Error,
    "photo_classifier_already_invoked",
  );
  assertEquals(calls, 1);
});
Deno.test("photo classifier policy/request hashes are deterministic and source content bound", async () => {
  const f = await fixture();
  const first = await preparePublicationPhotoClassifier(f.source, f.deps);
  const second = await preparePublicationPhotoClassifier(f.source, f.deps);
  assertEquals(first.proof, second.proof);
  // Frozen policy contract: intentional policy edits need a new version.
  assertEquals(
    first.proof.policy_sha256,
    "b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9",
  );
  const g = await fixture(new Uint8Array([...png, 1]));
  const changed = await preparePublicationPhotoClassifier(g.source, g.deps);
  assertEquals(changed.proof.policy_sha256, first.proof.policy_sha256);
  assert(changed.proof.request_sha256 !== first.proof.request_sha256);
});
Deno.test("photo classifier checks type, byte budget, digest and keys before transport", async (t) => {
  const cases: Array<(source: PublicationPhotoSource) => void> = [
    (s) => s.sha256 = "a".repeat(64),
    (s) => s.byte_count++,
    (s) => s.byte_count = PHOTO_CLASSIFIER_MAX_BYTES + 1,
    (s) => s.content_type = "image/jpeg",
    (s) => s.content_type = "audio/mp4",
    (s) => s.object_id = "https://example.invalid/private",
    (s) => s.media_id = s.object_id,
    (s) => Object.assign(s, { object_id: { toString: () => s.media_id } }),
    (s) => Object.assign(s, { media_id: { toString: () => s.object_id } }),
    (s) => Object.assign(s, { note: "must not enter prompt" }),
  ];
  for (const [index, change] of cases.entries()) {
    await t.step(String(index), async () => {
      const f = await fixture();
      change(f.source);
      await assertRejects(() =>
        preparePublicationPhotoClassifier(f.source, {
          ...f.deps,
          fetcher: () => {
            throw new Error("transport must not be called");
          },
        })
      );
    });
  }
  const f = await fixture();
  let read = false;
  await assertRejects(
    () =>
      preparePublicationPhotoClassifier(f.source, {
        apiKey: () => undefined,
        readSource: () => {
          read = true;
          return Promise.resolve(png);
        },
      }),
    Error,
    "photo_classifier_unavailable",
  );
  assertEquals(read, false);
});
Deno.test("photo classifier accepts supported photo signatures without transforming content", async () => {
  for (
    const [bytes, type] of [
      [new Uint8Array([255, 216, 255, 0]), "image/jpeg"],
      [
        new Uint8Array([
          0,
          0,
          0,
          20,
          102,
          116,
          121,
          112,
          109,
          105,
          102,
          49,
          0,
          0,
          0,
          0,
          104,
          101,
          105,
          99,
        ]),
        "image/heic",
      ],
    ] as const
  ) {
    const f = await fixture(bytes, type);
    const prepared = await preparePublicationPhotoClassifier(f.source, f.deps);
    assertEquals(prepared.proof.source.sha256, await evidenceDigest(bytes));
  }
});
Deno.test("photo classifier requires high confidence and safe decision; review never approves", async (t) => {
  for (
    const [decision, confidence, categories, expected] of [
      ["allow", 0.95, [], "approved"],
      ["allow", 0.949, [], "rejected"],
      ["review", 1, [], "rejected"],
      ["reject", 1, ["personal_data"], "rejected"],
    ] as const
  ) {
    await t.step(`${decision}/${confidence}`, async () => {
      const f = await fixture();
      const p = await preparePublicationPhotoClassifier(f.source, {
        ...f.deps,
        fetcher: () =>
          Promise.resolve(
            response(output(decision, confidence, [...categories])),
          ),
      });
      assertEquals((await p.invoke()).decision, expected);
    });
  }
});
Deno.test("photo classifier treats malformed, blocked or unaccounted output as unknown", async (t) => {
  const cases: Array<(v: ReturnType<typeof output>) => void> = [
    (v) => v.modelVersion = "gemini-other",
    (v) => v.candidates[0].finishReason = "MAX_TOKENS",
    (v) => v.candidates.push(v.candidates[0]),
    (v) => v.candidates[0].content.parts[0].text = "```json\n{}\n```",
    (v) =>
      v.candidates[0].content.parts[0].text = JSON.stringify({
        decision: "allow",
        confidence: 1,
        categories: [],
        notes: "private",
      }),
    (v) =>
      v.candidates[0].content.parts[0].text = JSON.stringify({
        decision: "allow",
        confidence: 1,
        categories: ["personal_data"],
      }),
    (v) =>
      v.candidates[0].content.parts[0].text = JSON.stringify({
        decision: "review",
        confidence: 1,
        categories: ["unexpected"],
      }),
    (v) =>
      v.candidates[0].content.parts[0].text = JSON.stringify({
        decision: "review",
        confidence: 2,
        categories: [],
      }),
    (v) => Object.assign(v.candidates[0].content.parts[0], { thought: true }),
    (v) => Object.assign(v, { promptFeedback: { blockReason: "SAFETY" } }),
    (v) =>
      Object.assign(v, {
        promptFeedback: { safetyRatings: [{ blocked: true }] },
      }),
    (v) =>
      Object.assign(v.candidates[0], { safetyRatings: [{ blocked: true }] }),
    (v) => v.usageMetadata.totalTokenCount++,
    (v) => v.usageMetadata.promptTokenCount = -1,
    (v) => Object.assign(v.usageMetadata, { thoughtsTokenCount: 1 }),
    (v) => Object.assign(v, { usageMetadata: null }),
  ];
  for (const [index, change] of cases.entries()) {
    await t.step(String(index), async () => {
      const f = await fixture();
      const v = output();
      change(v);
      let calls = 0;
      const p = await preparePublicationPhotoClassifier(f.source, {
        ...f.deps,
        fetcher: () => {
          calls++;
          return Promise.resolve(response(v));
        },
      });
      await assertRejects(
        p.invoke,
        Error,
        "photo_classifier_execution_unknown",
      );
      await assertRejects(p.invoke, Error, "photo_classifier_already_invoked");
      assertEquals(calls, 1);
    });
  }
});
Deno.test("photo classifier bounds streamed responses, never leaks provider errors or retries", async (t) => {
  const cases: Array<() => Response> = [
    () => new Response("private provider diagnostics", { status: 429 }),
    () => new Response("private provider diagnostics", { status: 503 }),
    () =>
      new Response("x".repeat(32769), {
        headers: { "content-type": "application/json" },
      }),
    () =>
      new Response(new Uint8Array([255]), {
        headers: { "content-type": "application/json" },
      }),
    () => new Response("{}", { headers: { "content-type": "text/plain" } }),
    () => {
      throw new Error("secret request and credential");
    },
  ];
  for (const [index, build] of cases.entries()) {
    await t.step(String(index), async () => {
      const f = await fixture();
      let calls = 0;
      const p = await preparePublicationPhotoClassifier(f.source, {
        ...f.deps,
        fetcher: () => {
          calls++;
          return Promise.resolve(build());
        },
      });
      const error = await assertRejects(
        p.invoke,
        Error,
        "photo_classifier_execution_unknown",
      );
      assertEquals(error.cause, undefined);
      assertEquals(error.message, "photo_classifier_execution_unknown");
      await assertRejects(p.invoke, Error, "photo_classifier_already_invoked");
      assertEquals(calls, 1);
    });
  }
});
Deno.test("photo classifier parallel invocation consumes the local permit once", async () => {
  const f = await fixture();
  let calls = 0;
  const p = await preparePublicationPhotoClassifier(f.source, {
    ...f.deps,
    fetcher: () => {
      calls++;
      return Promise.resolve(response(output()));
    },
  });
  const results = await Promise.allSettled([p.invoke(), p.invoke()]);
  assertEquals(results.map((r) => r.status), ["fulfilled", "rejected"]);
  assertEquals(calls, 1);
});
