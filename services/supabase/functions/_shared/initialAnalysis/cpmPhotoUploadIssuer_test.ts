import { assert, assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import {
  type CpmPhotoIssuanceBridge,
  issueInitialCpmPhotoUpload,
} from "./cpmPhotoUploadIssuer.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const signal = () => new AbortController().signal;
async function fixture(role = "source") {
  const config = {
    generation: id(4),
    provider: "r2",
    direct_endpoint:
      "https://00000000000000000000000000000000.r2.cloudflarestorage.com",
    private_bucket: "synthetic-private",
    namespace: "initial-preparation/v2",
    credential_profile: "synthetic_only",
    storage_protocol: "conditional_create_permanent_same_key_marker_v1",
  };
  const digest = await initialMediaHash(
    new TextEncoder().encode(
      `merian.initial-analysis.media.backend.v1\n${
        initialCanonicalText(config)
      }`,
    ),
  );
  const now = Date.now();
  const identity = {
    owner: id(9),
    scan: id(2),
    assignment_digest: "a".repeat(64),
    object: id(3),
    policy: "b".repeat(64),
  };
  const profiles = [{
    credential_profile: "synthetic_only",
    backend_generation: id(4),
    backend_configuration_digest: digest,
    access_key_id: "SYNTHETIC_KEY_NOT_REAL",
    secret_access_key: "SYNTHETIC_SECRET_NOT_REAL",
  }];
  const fresh = {
    outcome: "fresh",
    attempt_id: id(1),
    created_at_ms: now - 1000,
    capability_expires_at_ms: now + 30_000,
    observation: {
      binding: {
        attempt_id: id(1),
        scan_id: id(2),
        object_id: id(3),
        assignment_digest: identity.assignment_digest,
        backend_generation: id(4),
        backend_configuration_digest: digest,
        issued_at_ms: now - 500,
        verification_policy_digest: identity.policy,
      },
      target: {
        outcome: "live_object",
        role,
        byte_count: 4,
        content_type: "image/jpeg",
        sha256: "c".repeat(64),
      },
      backend: { ...config, configuration_digest: digest },
      admission_expires_at_ms: now + 30_000,
      erasure_claim: null,
    },
  };
  const calls: string[] = [];
  const bridge: CpmPhotoIssuanceBridge = {
    begin: (i) => {
      assertEquals(i, identity);
      calls.push("begin");
      return Promise.resolve(fresh);
    },
    requireCurrent: (v) => {
      assertEquals<unknown>(v, fresh.observation);
      calls.push("current");
      return Promise.resolve();
    },
  };
  return { identity, profiles, fresh, bridge, calls };
}
for (const role of ["source", "ai", "display"]) {
  Deno.test(`CPM ${role} issuer signs one exact conditional request after committed fresh`, async () => {
    const f = await fixture(role);
    const result = await issueInitialCpmPhotoUpload(
      f.bridge,
      f.identity,
      f.profiles,
      signal(),
    );
    assertEquals(f.calls, ["begin", "current", "current"]);
    assert(result.outcome === "issued");
    const url = new URL(result.url);
    assertEquals(url.origin, f.fresh.observation.backend.direct_endpoint);
    assertEquals(
      url.pathname,
      `/synthetic-private/initial-preparation/v2/${id(2)}/${id(3)}`,
    );
    assertEquals(result.headers, {
      "If-None-Match": "*",
      "Content-Type": "image/jpeg",
      "Content-Length": "4",
      "Cache-Control": "private, no-store",
      "x-amz-content-sha256": "c".repeat(64),
    });
    assertEquals(
      url.searchParams.get("X-Amz-SignedHeaders"),
      "cache-control;content-length;content-type;host;if-none-match;x-amz-content-sha256",
    );
    assertEquals(
      [...url.searchParams.keys()].sort(),
      [
        "X-Amz-Algorithm",
        "X-Amz-Credential",
        "X-Amz-Date",
        "X-Amz-Expires",
        "X-Amz-Signature",
        "X-Amz-SignedHeaders",
      ].sort(),
    );
    assertEquals(url.searchParams.get("X-Amz-Algorithm"), "AWS4-HMAC-SHA256");
    assert(/^[a-f0-9]{64}$/.test(url.searchParams.get("X-Amz-Signature")!));
    assert(result.signed_expires_at_ms <= f.fresh.capability_expires_at_ms);
    assert(result.signed_expires_at_ms > Date.now());
    assertEquals(
      result.capability_expires_at_ms,
      f.fresh.capability_expires_at_ms,
    );
    assertEquals(result.provider_enforcement, "unqualified");
    assertEquals(Object.isFrozen(result), true);
    assertEquals(Object.isFrozen(result.headers), true);
  });
}
Deno.test("CPM held and lost acknowledgement never renew or retry issuance", async () => {
  const f = await fixture();
  let began = 0;
  f.bridge.begin = () => {
    began++;
    return Promise.reject(new Error("synthetic lost acknowledgement"));
  };
  await assertRejects(() =>
    issueInitialCpmPhotoUpload(f.bridge, f.identity, f.profiles, signal())
  );
  assertEquals(began, 1);
  assertEquals(f.calls, []);
  f.bridge.begin = () => {
    began++;
    return Promise.resolve({ outcome: "held", attempt_id: id(1) });
  };
  const result = await issueInitialCpmPhotoUpload(
    f.bridge,
    f.identity,
    f.profiles,
    signal(),
  );
  assertEquals(result, { outcome: "held", attempt_id: id(1) });
  assertEquals(began, 2);
  assertEquals(f.calls, []);
});
Deno.test("CPM late fresh acknowledgement after cancellation cannot issue", async () => {
  const f = await fixture();
  const c = new AbortController();
  let complete!: (value: unknown) => void;
  f.bridge.begin = () =>
    new Promise((resolve) => {
      complete = resolve;
    });
  const pending = issueInitialCpmPhotoUpload(
    f.bridge,
    f.identity,
    f.profiles,
    c.signal,
  );
  await Promise.resolve();
  c.abort();
  await assertRejects(() => pending);
  complete(f.fresh);
  await Promise.resolve();
  assertEquals(f.calls, []);
});
Deno.test("CPM malformed or mismatched fresh acknowledgement fails before lifecycle or signing", async (t) => {
  const changes: Array<(f: Awaited<ReturnType<typeof fixture>>) => void> = [
    (f) => {
      f.fresh.observation.binding.scan_id = id(7);
    },
    (f) => {
      f.fresh.observation.binding.object_id = id(7);
    },
    (f) => {
      f.fresh.observation.binding.assignment_digest = "d".repeat(64);
    },
    (f) => {
      f.fresh.observation.binding.verification_policy_digest = "d".repeat(64);
    },
    (f) => {
      f.fresh.capability_expires_at_ms++;
    },
    (f) => {
      f.fresh.observation.binding.issued_at_ms = Date.now() + 60_000;
    },
    (f) => {
      f.fresh.observation.target.role = "unknown";
    },
    (f) => {
      f.profiles[0].backend_generation = id(7);
    },
    (f) => {
      Object.assign(f.fresh, { url: "https://untrusted.invalid" });
    },
    (f) => {
      f.fresh.outcome = "held";
    },
  ];
  for (const [index, change] of changes.entries()) {
    await t.step(String(index), async () => {
      const f = await fixture();
      change(f);
      await assertRejects(() =>
        issueInitialCpmPhotoUpload(f.bridge, f.identity, f.profiles, signal())
      );
      assertEquals(f.calls, ["begin"]);
    });
  }
});
Deno.test("CPM lifecycle changes before or after signing suppress capability delivery", async (t) => {
  for (const denyAt of [1, 2]) {
    await t.step(String(denyAt), async () => {
      const f = await fixture();
      let checks = 0;
      f.bridge.requireCurrent = () =>
        ++checks === denyAt
          ? Promise.reject(new Error("synthetic retirement"))
          : Promise.resolve();
      await assertRejects(() =>
        issueInitialCpmPhotoUpload(f.bridge, f.identity, f.profiles, signal())
      );
      assertEquals(checks, denyAt);
      assertEquals(f.calls, ["begin"]);
    });
  }
});
Deno.test("CPM issuer snapshots identity and trusted profiles before begin suspends", async () => {
  const f = await fixture();
  const expected = structuredClone(f.identity);
  let complete!: (value: unknown) => void;
  f.bridge.begin = (i) => {
    assertEquals(i, expected);
    return new Promise((resolve) => {
      complete = resolve;
    });
  };
  const pending = issueInitialCpmPhotoUpload(
    f.bridge,
    f.identity,
    f.profiles,
    signal(),
  );
  await Promise.resolve();
  f.identity.object = id(7);
  f.profiles[0].access_key_id = "CHANGED_SYNTHETIC_KEY";
  f.profiles.splice(0);
  complete(f.fresh);
  const result = await pending;
  assert(result.outcome === "issued");
  assert(
    new URL(result.url).searchParams.get("X-Amz-Credential")!.startsWith(
      "SYNTHETIC_KEY_NOT_REAL/",
    ),
  );
});
Deno.test("CPM issuer rejects invalid trusted profiles before durable advancement", async () => {
  const f = await fixture();
  f.profiles[0].secret_access_key = "";
  await assertRejects(() =>
    issueInitialCpmPhotoUpload(f.bridge, f.identity, f.profiles, signal())
  );
  assertEquals(f.calls, []);
});

Deno.test("CPM signature cryptographically binds declared hash and all fixed headers", async () => {
  const f = await fixture();
  const result = await issueInitialCpmPhotoUpload(
    f.bridge,
    f.identity,
    f.profiles,
    signal(),
  );
  assert(result.outcome === "issued");
  const url = new URL(result.url);
  const signature = url.searchParams.get("X-Amz-Signature");
  url.searchParams.delete("X-Amz-Signature");
  const encode = (s: string) =>
    encodeURIComponent(s).replace(
      /[!'()*]/g,
      (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
    );
  const query = [...url.searchParams].sort(([a], [b]) => a < b ? -1 : 1).map((
    [k, v],
  ) => `${encode(k)}=${encode(v)}`).join("&");
  const names = url.searchParams.get("X-Amz-SignedHeaders")!;
  const headers = new Headers(result.headers);
  const canonicalHeaders =
    names.split(";").map((k) =>
      `${k}:${k === "host" ? url.host : headers.get(k)}`
    ).join("\n") + "\n";
  const datetime = url.searchParams.get("X-Amz-Date")!;
  const scope = `${datetime.slice(0, 8)}/auto/s3/aws4_request`;
  const bytes = (s: string) => new TextEncoder().encode(s);
  async function hmac(key: Uint8Array<ArrayBuffer>, value: string) {
    const imported = await crypto.subtle.importKey(
      "raw",
      key,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    return new Uint8Array(
      await crypto.subtle.sign("HMAC", imported, bytes(value)),
    );
  }
  let key = bytes("AWS4" + f.profiles[0].secret_access_key);
  for (const value of [datetime.slice(0, 8), "auto", "s3", "aws4_request"]) {
    key = await hmac(key, value);
  }
  async function signatureFor(payloadHash: string) {
    const canonical = [
      "PUT",
      url.pathname,
      query,
      canonicalHeaders,
      names,
      payloadHash,
    ].join("\n");
    const toSign = [
      "AWS4-HMAC-SHA256",
      datetime,
      scope,
      await initialMediaHash(bytes(canonical)),
    ].join("\n");
    return [...await hmac(key, toSign)].map((v) =>
      v.toString(16).padStart(2, "0")
    ).join("");
  }
  assertEquals(signature, await signatureFor("c".repeat(64)));
  assert(signature !== await signatureFor("UNSIGNED-PAYLOAD"));
  assert(signature !== await signatureFor("d".repeat(64)));
});
