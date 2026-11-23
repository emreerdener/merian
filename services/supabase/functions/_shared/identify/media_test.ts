import { assertEquals, assertRejects } from "@std/assert";

import { AwsClient } from "aws4fetch";
import { encodeBase64 } from "../encoding.ts";
import { MEDIA_BUDGETS } from "../mediaBudgets.ts";

import {
  parseAudioTransport,
  resolveImagePayloads,
  stagedImageSourceKeys,
  validateImageR2ObjectKeys,
} from "./media.ts";

async function responseError(
  response: Response | null,
): Promise<string | null> {
  if (!response) return null;
  const body = await response.json() as { error?: string };
  return body.error ?? null;
}

Deno.test("validateImageR2ObjectKeys allows destination keys when ownership is not required", () => {
  const response = validateImageR2ObjectKeys(
    ["staging/other-user/photo.webp"],
    "user-1",
    {
      enforceOwnership: false,
      idorEvent: "test/image_idor_attempt",
    },
  );

  assertEquals(response, null);
});

Deno.test("validateImageR2ObjectKeys rejects path traversal even for destination-only keys", async () => {
  const response = validateImageR2ObjectKeys(
    ["staging/user-1/../photo.webp"],
    "user-1",
    {
      enforceOwnership: false,
      idorEvent: "test/image_idor_attempt",
    },
  );

  assertEquals(response?.status, 400);
  assertEquals(
    await responseError(response),
    "Bad Request: Path traversal detected.",
  );
});

Deno.test("validateImageR2ObjectKeys rejects wrong-user staged source keys", async () => {
  const response = validateImageR2ObjectKeys(
    ["staging/other-user/photo.webp"],
    "user-1",
    {
      enforceOwnership: true,
      idorEvent: "test/image_idor_attempt",
    },
  );

  assertEquals(response?.status, 403);
  assertEquals(
    await responseError(response),
    "Forbidden: r2ObjectKey does not belong to the requesting user.",
  );
});

Deno.test("stagedImageSourceKeys excludes destination hints for inline images", () => {
  assertEquals(
    stagedImageSourceKeys(
      ["staging/legacy-device-id/photo.webp"],
      ["inline-image-bytes"],
    ),
    [],
  );
});

Deno.test("stagedImageSourceKeys preserves actual staged image sources", () => {
  const sourceKeys = ["staging/user-1/photo.webp"];
  assertEquals(stagedImageSourceKeys(sourceKeys, []), sourceKeys);
  assertEquals(stagedImageSourceKeys(sourceKeys, undefined), sourceKeys);
});

Deno.test("parseAudioTransport accepts one typed transport and normalizes absence", () => {
  assertEquals(parseAudioTransport({}), {
    value: { audioR2ObjectKeys: [], audioBase64s: [] },
  });
  assertEquals(
    parseAudioTransport({
      audioR2ObjectKeys: ["staging/user-1/call.wav"],
    }),
    {
      value: {
        audioR2ObjectKeys: ["staging/user-1/call.wav"],
        audioBase64s: [],
      },
    },
  );
});

Deno.test("parseAudioTransport rejects scalars, blank entries, and mixed transports", () => {
  for (
    const payload of [
      { audioBase64s: "not-an-array" },
      { audioBase64s: [42] },
      { audioBase64s: ["   "] },
      { audioR2ObjectKeys: [null] },
    ]
  ) {
    assertEquals(
      parseAudioTransport(payload).error?.code,
      "invalid_audio_transport",
    );
  }

  assertEquals(
    parseAudioTransport({
      audioR2ObjectKeys: ["staging/user-1/call.wav"],
      audioBase64s: ["UklGRg=="],
    }).error?.code,
    "ambiguous_audio_transport",
  );
});

Deno.test("staged image reads release all response bodies and share one byte budget", async (t) => {
  const originalFetch = AwsClient.prototype.fetch;
  const names = [
    "R2_ACCOUNT_ID",
    "R2_BUCKET_NAME",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
  ];
  const previous = names.map((name) => Deno.env.get(name));
  for (const name of names) Deno.env.set(name, "synthetic-media-test");
  try {
    for (
      const mode of [
        "success",
        "fetch-rejection",
        "http-error",
        "header-limit",
        "chunk-limit",
        "read-error",
        "aggregate-limit",
        "exact-budget-empty",
        "exact-budget-extra",
      ]
    ) {
      await t.step(mode, async () => {
        const cancelled: number[] = [];
        const pulls = [0, 0, 0];
        let fetches = 0;
        const bytes = mode.startsWith("exact-budget")
          ? new Uint8Array(MEDIA_BUDGETS.maxImageRawBytes)
          : mode === "aggregate-limit"
          ? new Uint8Array(MEDIA_BUDGETS.maxImageRawBytes - 2)
          : new Uint8Array([1, 2, 3]);
        AwsClient.prototype.fetch = () => {
          const index = fetches++;
          if (index === 0 && mode === "fetch-rejection") {
            return Promise.reject(new Error("synthetic fetch failure"));
          }
          if (
            mode === "success" ||
            (index === 0 &&
              (mode === "aggregate-limit" || mode.startsWith("exact-budget")))
          ) {
            return Promise.resolve(new Response(bytes));
          }
          if (index === 1 && mode === "exact-budget-empty") {
            return Promise.resolve(new Response(new Uint8Array()));
          }
          const stream = new ReadableStream<Uint8Array>({
            pull(controller) {
              pulls[index]++;
              if (mode === "read-error" && index === 0) {
                controller.error(new Error("synthetic read failure"));
              } else if (mode === "chunk-limit" && index === 0) {
                controller.enqueue(
                  new Uint8Array(MEDIA_BUDGETS.maxImageRawBytes + 1),
                );
              } else if (mode === "aggregate-limit" && index === 1) {
                controller.enqueue(new Uint8Array(3));
              } else if (mode === "exact-budget-extra" && index === 1) {
                controller.enqueue(new Uint8Array(1));
                controller.close();
              } else {
                throw new Error("unconsumed sibling must not be read");
              }
            },
            cancel() {
              cancelled.push(index);
            },
          }, { highWaterMark: 0 });
          return Promise.resolve(
            new Response(stream, {
              status: mode === "http-error" && index === 0 ? 404 : 200,
              headers: mode === "header-limit" && index === 0
                ? {
                  "content-length": String(MEDIA_BUDGETS.maxImageRawBytes + 1),
                }
                : undefined,
            }),
          );
        };
        const count = mode.startsWith("exact-budget") ? 2 : 3;
        const run = () =>
          resolveImagePayloads(
            Array.from({ length: count }, (_, i) =>
              `staging/synthetic-owner/${i}.webp`),
            undefined,
            Date.now(),
          );
        if (["fetch-rejection", "http-error", "read-error"].includes(mode)) {
          await assertRejects(run);
        } else {
          const result = await run();
          if (mode === "success") {
            assertEquals(
              result.base64Payloads,
              Array(3).fill(encodeBase64(bytes)),
            );
          } else if (mode === "exact-budget-empty") {
            assertEquals(result.base64Payloads, [encodeBase64(bytes), ""]);
          } else {
            assertEquals(result.errorResponse?.status, 413);
            assertEquals(result.base64Payloads, undefined);
          }
        }
        assertEquals(fetches, count);
        const expected = mode === "success" || mode.startsWith("exact-budget")
          ? []
          : mode === "fetch-rejection" || mode === "read-error" ||
              mode === "aggregate-limit"
          ? [1, 2]
          : [0, 1, 2];
        assertEquals(cancelled.sort(), expected);
        if (!mode.startsWith("exact-budget") && mode !== "success") {
          assertEquals(pulls[2], 0);
        }
        if (mode === "aggregate-limit") assertEquals(pulls[1], 1);
      });
    }
  } finally {
    AwsClient.prototype.fetch = originalFetch;
    names.forEach((name, i) =>
      previous[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, previous[i]!)
    );
  }
});
