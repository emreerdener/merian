import { assert, assertEquals } from "@std/assert";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import { resolveHistoryMedia } from "./handler.ts";

const identity = {
  owner_id: "00000000-0000-4000-8000-000000000001",
  observation_id: "00000000-0000-4000-8000-000000000002",
  analysis_id: "00000000-0000-4000-8000-000000000003",
  media_id: "00000000-0000-4000-8000-000000000004",
};
const { owner_id: owner, ...ids } = identity;
const body = { ...ids, resolution_protocol: 1 };
const request = new Request("https://example.invalid/resolve-history-media", {
  method: "POST",
});
const url =
  "https://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.r2.cloudflarestorage.com/synthetic?signature=synthetic";
const saved = {
  ...identity,
  object_id: "00000000-0000-4000-8000-000000000005",
  content_type: "audio/wav",
  byte_count: 46,
  sha256: "a".repeat(64),
  expires_at: "2026-01-01T00:00:00Z",
  ready_at: "2026-01-01T00:00:00Z",
};

Deno.test("completed media resolution signs only bounded ready artifacts and returns no object identity", async () => {
  for (
    const type of [
      "audio/wav",
      "video/mp4",
      "image/webp",
      "image/jpeg",
      "image/png",
      "image/heic",
    ]
  ) {
    let reads = 0;
    const response = await resolveHistoryMedia(request, body, owner, {
      receipt: (value) => {
        assertEquals(value, identity);
        reads++;
        return Promise.resolve({ ...saved, content_type: type });
      },
      sign: () => Promise.resolve(url),
      now: () => 1000,
    });
    assertEquals(response.status, 200);
    assertEquals(reads, 2);
    assertEquals(response.headers.get("cache-control"), "private, no-store");
    const result = await response.json();
    assertEquals(result.content_type, type);
    assertEquals(result.expires_at_ms, 31000);
    assert(!("object_id" in result));
    assert(!("ready_at" in result));
  }
});

Deno.test("completed media denies injected ownership, invalid protocol and unready or oversized receipts", async () => {
  for (
    const input of [{ ...body, owner_id: owner }, {
      ...body,
      resolution_protocol: 8,
    }, { ...body, media_id: "invalid" }]
  ) {
    const result = await resolveHistoryMedia(request, input, owner, {
      receipt: () => {
        throw new Error("unexpected access");
      },
      sign: () => {
        throw new Error("unexpected signing");
      },
    });
    assertEquals(result.status, 400);
  }
  for (
    const change of [
      { ready_at: null },
      { byte_count: 2_700_001 },
      { content_type: "audio/mp4" },
      { content_type: "video/mp4", byte_count: 12_582_913 },
      { content_type: "image/webp", byte_count: 5_242_881 },
      { byte_count: 45 },
      { owner_id: identity.analysis_id },
      { extra: true },
    ]
  ) {
    let signed = false;
    const result = await resolveHistoryMedia(request, body, owner, {
      receipt: () => Promise.resolve({ ...saved, ...change }),
      sign: () => {
        signed = true;
        return Promise.resolve(url);
      },
    });
    assertEquals(result.status, 503);
    assertEquals(signed, false);
  }
});

Deno.test("completed media rechecks immutable receipt and deletion after signing without leaking errors", async () => {
  for (
    const change of [
      { object_id: "00000000-0000-4000-8000-000000000006" },
      { sha256: "b".repeat(64) },
      { ready_at: null },
      { ready_at: "2026-01-02T00:00:00Z" },
      { expires_at: "2026-01-02T00:00:00Z" },
    ]
  ) {
    let reads = 0;
    const result = await resolveHistoryMedia(request, body, owner, {
      receipt: () =>
        Promise.resolve(++reads === 1 ? saved : { ...saved, ...change }),
      sign: () => Promise.resolve(url),
    });
    assertEquals(result.status, 503);
  }
  let reads = 0;
  const deleted = await resolveHistoryMedia(request, body, owner, {
    receipt: () => {
      if (++reads === 2) throw new HistoryError("analysis_history_not_found");
      return Promise.resolve(saved);
    },
    sign: () => Promise.resolve(url),
  });
  assertEquals(deleted.status, 404);
  const failed = await resolveHistoryMedia(request, body, owner, {
    receipt: () => Promise.resolve(saved),
    sign: () => {
      throw new Error("private-signed-url-secret");
    },
  });
  assertEquals(failed.status, 503);
  assert(!(await failed.text()).includes("private-signed-url-secret"));
});

Deno.test("completed media refuses expired signing and credentials or unexpected hosts in capabilities", async () => {
  for (
    const address of [
      "http://example.invalid/a",
      "https://example.invalid/a",
      url + "#fragment",
      url.replace("https://", "https://user:password@"),
      url.replace(".com/", ".com:444/"),
    ]
  ) {
    assertEquals(
      (await resolveHistoryMedia(request, body, owner, {
        receipt: () => Promise.resolve(saved),
        sign: () => Promise.resolve(address),
      })).status,
      503,
    );
  }
  let time = 1000;
  assertEquals(
    (await resolveHistoryMedia(request, body, owner, {
      receipt: () => Promise.resolve(saved),
      now: () => time,
      sign: () => {
        time += 30000;
        return Promise.resolve(url);
      },
    })).status,
    503,
  );
});

Deno.test("initial retained media uses explicit durable receipts and rechecks every field", async () => {
  const initial = { ...saved, schema_version: 2, expires_at: null };
  const input = { ...body, resolution_protocol: 2 };
  for (
    const type of [
      "image/heif",
      "audio/mp4",
      "audio/wav",
      "video/mp4",
      "image/jpeg",
    ]
  ) {
    let reads = 0;
    const response = await resolveHistoryMedia(request, input, owner, {
      receipt: (_, protocol) => {
        assertEquals(protocol, 2);
        reads++;
        return Promise.resolve({ ...initial, content_type: type });
      },
      sign: () => Promise.resolve(url),
      now: () => 1000,
    });
    assertEquals(response.status, 200);
    assertEquals(reads, 2);
    const result = await response.json();
    assertEquals(result.expires_at_ms, 31000);
    assert(!("object_id" in result));
  }
  const old = await resolveHistoryMedia(request, body, owner, {
    receipt: () => Promise.resolve(initial),
    sign: () => {
      throw new Error("must not sign");
    },
  });
  assertEquals(old.status, 503);
  for (
    const change of [
      { schema_version: 3 },
      { expires_at: saved.expires_at },
      { ready_at: null },
      { owner_id: identity.analysis_id },
      { byte_count: 2_700_001 },
      { content_type: "image/svg+xml" },
      { sha256: "b".repeat(64) },
      { object_id: "00000000-0000-4000-8000-000000000006" },
    ]
  ) {
    let reads = 0;
    const response = await resolveHistoryMedia(request, input, owner, {
      receipt: () =>
        Promise.resolve(++reads === 1 ? initial : { ...initial, ...change }),
      sign: () => Promise.resolve(url),
    });
    assertEquals(response.status, 503);
  }
});

Deno.test("V8 original resolution requires explicit protocol and verified source role", async () => {
  const original = {
    ...saved,
    schema_version: 3,
    artifact_role: "source_image",
    content_type: "image/heif",
    byte_count: 33_554_432,
    expires_at: null,
  };
  const deps = {
    receipt: () => Promise.resolve(original),
    sign: () => Promise.resolve(url),
    now: () => 1000,
  };
  const response = await resolveHistoryMedia(
    request,
    { ...body, resolution_protocol: 3 },
    owner,
    deps,
  );
  assertEquals(response.status, 200);
  const ticket = await response.json();
  assertEquals(ticket.byte_count, 33_554_432);
  assertEquals(ticket.schema_version, 1);
  assertEquals(ticket.expires_at_ms, 31000);
  assert(!("artifact_role" in ticket));
  assert(!("object_id" in ticket));
  for (const protocol of [1, 2]) {
    assertEquals(
      (await resolveHistoryMedia(
        request,
        { ...body, resolution_protocol: protocol },
        owner,
        deps,
      )).status,
      503,
    );
  }
  for (
    const change of [
      { byte_count: 33_554_433 },
      { artifact_role: "prepared_image" },
      { artifact_role: "inference_frame" },
      { artifact_role: "source_audio" },
      { artifact_role: "__proto__" },
      { schema_version: 2 },
    ]
  ) {
    assertEquals(
      (await resolveHistoryMedia(
        request,
        { ...body, resolution_protocol: 3 },
        owner,
        {
          ...deps,
          receipt: () => Promise.resolve({ ...original, ...change }),
          sign: () => {
            throw new Error("invalid receipt must not sign");
          },
        },
      )).status,
      503,
    );
  }
  let reads = 0;
  assertEquals(
    (await resolveHistoryMedia(
      request,
      { ...body, resolution_protocol: 3 },
      owner,
      {
        ...deps,
        receipt: () =>
          Promise.resolve({
            ...original,
            byte_count: 100,
            content_type: "image/jpeg",
            artifact_role: ++reads === 1 ? "source_image" : "prepared_image",
          }),
      },
    )).status,
    503,
  );
});
