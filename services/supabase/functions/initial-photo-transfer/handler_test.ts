import { assert, assertEquals, assertThrows } from "@std/assert";
import { initialPhotoTransfer } from "./handler.ts";
import { parseTransferRequest } from "./contract.ts";
import { transferPolicyCatalog } from "./catalog.ts";
import { attempt, fixture, owner } from "./fixtures.ts";

const req = (signal?: AbortSignal) =>
  new Request("https://synthetic.invalid/initial-photo-transfer", { signal });
for (const index of [0, 1, 2]) {
  Deno.test(`dormant transfer role ${index} issues once and replay remains held`, async () => {
    const f = await fixture(index);
    const first = await initialPhotoTransfer(
      req(),
      f.request,
      owner,
      () => f.deps,
    );
    assertEquals(first.status, 200);
    assertEquals(first.headers.get("Cache-Control"), "private, no-store");
    const result = await first.json();
    assertEquals(result.outcome, "issued");
    assertEquals(result.role, f.fresh.observation.target.role);
    assertEquals(result.provider_enforcement, "unqualified");
    assertEquals(result.backend_configuration_digest, f.backendDigest);
    assertEquals(f.calls, ["recover", "begin", "current", "current"]);
    const replay = await initialPhotoTransfer(
      req(),
      f.request,
      owner,
      () => f.deps,
    );
    assertEquals(await replay.json(), { outcome: "held", attempt_id: attempt });
    assertEquals(f.calls.slice(4), ["recover", "begin"]);
  });
}
Deno.test("dormant transfer status needs no allocation recovery or signing configuration", async () => {
  const f = await fixture();
  f.deps.catalog = {
    resolve() {
      throw new Error("must not resolve");
    },
  };
  f.deps.recover = () => {
    throw new Error("must not recover allocation");
  };
  f.deps.bridge.begin = () => {
    throw new Error("must not issue");
  };
  const response = await initialPhotoTransfer(
    req(),
    f.status,
    owner,
    () => f.deps,
  );
  assertEquals(response.status, 200);
  assertEquals((await response.json()).attempt, null);
  assertEquals(f.calls, ["status"]);
});
Deno.test("dormant transfer lost begin acknowledgement never retries and status recovers", async () => {
  const f = await fixture(), begin = f.deps.bridge.begin;
  f.deps.bridge.begin = async (identity, signal) => {
    await begin(identity, signal);
    throw new Error("synthetic lost commit acknowledgement");
  };
  const response = await initialPhotoTransfer(
    req(),
    f.request,
    owner,
    () => f.deps,
  );
  assertEquals(response.status, 503);
  assertEquals(f.calls, ["recover", "begin"]);
  assert(!JSON.stringify(await response.json()).includes("synthetic lost"));
  f.deps.catalog = transferPolicyCatalog([]);
  const status = await initialPhotoTransfer(
    req(),
    f.status,
    owner,
    () => f.deps,
  );
  assertEquals((await status.json()).attempt.attempt_id, attempt);
  assertEquals(f.calls, ["recover", "begin", "status"]);
});
Deno.test("dormant transfer rejects request identity authority and clock substitutions before dependencies", async (t) => {
  const f = await fixture();
  for (
    const change of [
      { owner },
      { policy: "b".repeat(64) },
      { backend_generation: f.entry.profile.backend_generation },
      { version: 2 },
      { action: "retry" },
      { object_id: "invalid" },
      { scan_id: owner },
      { assignment_digest: null },
      { allocation_expires_at_ms: f.request.allocation_expires_at_ms + 1 },
      { candidate_canonical: "{}" },
    ]
  ) {
    await t.step(Object.keys(change)[0], async () => {
      const response = await initialPhotoTransfer(
        req(),
        { ...f.request, ...change },
        owner,
        () => {
          throw new Error("must not load dependencies");
        },
      );
      assertEquals(response.status, 400);
    });
  }
  assertThrows(() =>
    parseTransferRequest({
      ...f.status,
      candidate_canonical: f.request.candidate_canonical,
    })
  );
});
Deno.test("dormant transfer checks exact saved receipt role and backend before begin", async (t) => {
  for (
    const change of [
      "clock",
      "object",
      "digest",
      "backend",
      "held",
      "foreign_owner",
    ]
  ) {
    await t.step(change, async () => {
      const f = await fixture();
      if (change === "clock") {
        f.request.allocation_created_at_ms++;
        f.request.allocation_expires_at_ms++;
      }
      if (change === "object") f.request.object_id = owner;
      if (change === "digest") f.request.assignment_digest = "f".repeat(64);
      if (change === "backend") {
        f.recovered.backend_configuration_digest = "d".repeat(64);
      }
      if (change === "held") {
        f.deps.recover = () =>
          Promise.resolve({
            version: 1,
            variant: "client_prepared_photo",
            outcome: "terminal_held",
            authority: "none",
            scan_id: f.request.scan_id,
            reason: "expired",
          });
      }
      if (change === "foreign_owner") {
        f.deps.recover = () => {
          throw new Error("synthetic owner denial");
        };
      }
      assertEquals(
        (await initialPhotoTransfer(req(), f.request, owner, () => f.deps))
          .status,
        503,
      );
      assert(!f.calls.includes("begin"));
    });
  }
});
Deno.test("dormant transfer rejects conflicting fresh observation before signing", async (t) => {
  for (
    const change of [
      "policy",
      "backend",
      "role",
      "bytes",
      "type",
      "hash",
      "expiry",
      "created",
    ]
  ) {
    await t.step(change, async () => {
      const f = await fixture(), o = f.fresh.observation;
      if (change === "policy") {
        o.binding.verification_policy_digest = "d".repeat(64);
      }
      if (change === "backend") {
        o.binding.backend_configuration_digest = "d".repeat(64);
      }
      if (change === "role") o.target.role = "display";
      if (change === "bytes") o.target.byte_count++;
      if (change === "type") o.target.content_type = "image/png";
      if (change === "hash") o.target.sha256 = "d".repeat(64);
      if (change === "expiry") o.admission_expires_at_ms++;
      if (change === "created") {
        f.fresh.created_at_ms = f.request.allocation_created_at_ms - 1;
      }
      assertEquals(
        (await initialPhotoTransfer(req(), f.request, owner, () => f.deps))
          .status,
        503,
      );
      assertEquals(f.calls, ["recover", "begin"]);
    });
  }
});
Deno.test("dormant policy catalog snapshots exact tuples and rejects ambiguity", async () => {
  const f = await fixture(), original = structuredClone(f.entry);
  const catalog = transferPolicyCatalog([f.entry]);
  f.entry.policy_digest = "d".repeat(64);
  f.entry.profile.secret_access_key = "CHANGED_SYNTHETIC_VALUE";
  assertEquals(
    catalog.resolve(
      original.profile.backend_generation,
      original.profile.backend_configuration_digest,
    ),
    original,
  );
  assertEquals(JSON.stringify(catalog), "{}");
  assertThrows(() => transferPolicyCatalog([original, original]));
  assertThrows(() =>
    transferPolicyCatalog([original, {
      ...original,
      policy_digest: "d".repeat(64),
    }])
  );
  assertThrows(() => transferPolicyCatalog(Array(17).fill(original)));
  assertThrows(() =>
    catalog.resolve(owner, original.profile.backend_configuration_digest)
  );
  assertThrows(() =>
    catalog.resolve(original.profile.backend_generation, "d".repeat(64))
  );
  assertThrows(() =>
    transferPolicyCatalog([{
      ...original,
      profile: { ...original.profile, secret_access_key: "invalid" },
    }])
  );
});
Deno.test("dormant transfer cancellation and malformed status remain opaque without issuance", async () => {
  const f = await fixture(), controller = new AbortController();
  controller.abort();
  assertEquals(
    (await initialPhotoTransfer(
      req(controller.signal),
      f.request,
      owner,
      () => f.deps,
    )).status,
    503,
  );
  assertEquals(f.calls, []);
  const read = f.deps.bridge.readStatus;
  f.deps.bridge.readStatus = async (identity, saved, signal) => ({
    ...await read(identity, saved, signal),
    scan_id: owner,
  });
  assertEquals(
    (await initialPhotoTransfer(req(), f.status, owner, () => f.deps)).status,
    503,
  );
  assertEquals(f.calls, ["status"]);
});

Deno.test("dormant transfer snapshots recovered allocation before catalog resolution", async () => {
  const f = await fixture(), catalog = f.deps.catalog;
  f.deps.catalog = {
    resolve(generation, digest) {
      f.recovered.assignment_canonical = "{}";
      return catalog.resolve(generation, digest);
    },
  };
  const response = await initialPhotoTransfer(
    req(),
    f.request,
    owner,
    () => f.deps,
  );
  assertEquals(response.status, 200);
  assertEquals((await response.json()).outcome, "issued");
});

for (const stage of ["recover", "begin"]) {
  Deno.test(`dormant transfer cancellation during ${stage} discards late reply without signing`, async () => {
    const f = await fixture(), controller = new AbortController();
    let entered!: () => void, release!: (value: unknown) => void;
    const started = new Promise<void>((resolve) => {
      entered = resolve;
    });
    const delayed = new Promise<unknown>((resolve) => {
      release = resolve;
    });
    if (stage === "recover") {
      f.deps.recover = () => {
        f.calls.push("recover");
        entered();
        return delayed;
      };
    } else {f.deps.bridge.begin = () => {
        f.calls.push("begin");
        entered();
        return delayed;
      };}
    const pending = initialPhotoTransfer(
      req(controller.signal),
      f.request,
      owner,
      () => f.deps,
    );
    await started;
    controller.abort();
    try {
      assertEquals((await pending).status, 503);
    } finally {
      release(stage === "recover" ? f.recovered : f.fresh);
      await delayed;
    }
    // Drain the late dependency continuation; it must not reach requireCurrent/signing.
    await new Promise((resolve) => setTimeout(resolve, 0));
    assertEquals(
      f.calls,
      stage === "recover" ? ["recover"] : ["recover", "begin"],
    );
  });
}
