import { preparePublicationPhotoClassifier } from "./photoClassifier.ts";
import { evidenceDigest } from "./evidence.ts";
import { assertEquals, assertRejects, assertStringIncludes } from "@std/assert";
import {
  type PhotoClassifierProof,
  type PhotoClassifierResult,
} from "./photoClassifier.ts";
import {
  executePublicationPhotoModeration,
  type PhotoExecutionDependencies,
  type PhotoModerationWork,
} from "./photoExecution.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
function setup() {
  const calls: string[] = [];
  const identity = { owner_id: id(6), observation_id: id(7) };
  const expectedScope = { ...identity, attempt_id: id(1), lease_token: id(4) };
  const work: PhotoModerationWork = {
    attempt_id: id(1),
    operation_id: id(2),
    media_id: id(3),
    state: "reserved",
    lease_token: id(4),
    source: {
      media_id: id(3),
      object_id: id(5),
      content_type: "image/png",
      byte_count: 8,
      sha256: "a".repeat(64),
    },
    policy_version: "photo_publication_v1",
    provider: "gemini",
    model: "gemini-2.5-flash",
    processor_permission: "google_gemini",
  };
  const proof: PhotoClassifierProof = {
    schema_version: 1,
    policy_version: "photo_publication_v1",
    policy_sha256:
      "b68222cb5cd8b79a8c8553151239ae4026202f70c2fdb5ff9604f7b225a76be9",
    request_sha256: "b".repeat(64),
    provider: "gemini",
    model: "gemini-2.5-flash",
    processor_permission: "google_gemini",
    source: work.source,
  };
  const result: PhotoClassifierResult = {
    decision: "approved",
    classification: "allow",
    confidence: 0.99,
    categories: [],
    model: "gemini-2.5-flash",
    usage: { input_tokens: 100, output_tokens: 10, total_tokens: 110 },
  };
  const deps: PhotoExecutionDependencies = {
    prepare: () => {
      calls.push("prepare");
      return Promise.resolve({
        proof,
        invoke: () => {
          calls.push("invoke");
          return Promise.resolve(result);
        },
      });
    },
    saveProof: (scope) => {
      assertEquals(scope, expectedScope);
      calls.push("saveProof");
      return Promise.resolve();
    },
    dispatch: (scope) => {
      assertEquals(scope, expectedScope);
      calls.push("dispatch");
      return Promise.resolve(true);
    },
    complete: (scope, p, r) => {
      assertEquals(scope, expectedScope);
      calls.push("complete");
      assertEquals(p, proof);
      assertEquals(r, result);
      return Promise.resolve("approved");
    },
    retire: (scope) => {
      assertEquals(scope, expectedScope);
      calls.push("retire");
      return Promise.resolve("cancelled");
    },
  };
  return { calls, identity, work, proof, result, deps };
}
Deno.test("photo execution saves exact proof before dispatch and atomically completes without publication", async () => {
  const f = setup();
  assertEquals(
    await executePublicationPhotoModeration(f.identity, f.work, f.deps),
    "approved",
  );
  assertEquals(f.calls, [
    "prepare",
    "saveProof",
    "dispatch",
    "invoke",
    "complete",
  ]);
});
Deno.test("photo execution lost completion reply retries only the identical write", async () => {
  const f = setup();
  const complete = f.deps.complete;
  let count = 0;
  f.deps.complete = async (scope, p, r) => {
    const state = await complete(scope, p, r);
    if (++count === 1) throw new Error("lost response");
    return state;
  };
  assertEquals(
    await executePublicationPhotoModeration(f.identity, f.work, f.deps),
    "approved",
  );
  assertEquals(f.calls, [
    "prepare",
    "saveProof",
    "dispatch",
    "invoke",
    "complete",
    "complete",
  ]);
});
Deno.test("photo execution denial or lost dispatch reply never invokes or refunds", async (t) => {
  for (const lost of [false, true]) {
    await t.step(String(lost), async () => {
      const f = setup();
      f.deps.dispatch = () => {
        f.calls.push("dispatch");
        if (lost) throw new Error("uncertain");
        return Promise.resolve(false);
      };
      assertEquals(
        await executePublicationPhotoModeration(f.identity, f.work, f.deps),
        "pending",
      );
      assertEquals(f.calls, ["prepare", "saveProof", "dispatch"]);
    });
  }
});
Deno.test("photo execution pre-dispatch failures cancel only through authoritative retirement", async (t) => {
  for (const stage of ["prepare", "saveProof"] as const) {
    await t.step(stage, async () => {
      const f = setup();
      f.deps[stage] = () => {
        f.calls.push(stage);
        throw new Error("preflight");
      };
      assertEquals(
        await executePublicationPhotoModeration(f.identity, f.work, f.deps),
        "cancelled",
      );
      assertEquals(f.calls.at(-1), "retire");
      assertEquals(f.calls.includes("dispatch"), false);
    });
  }
});
Deno.test("photo execution cannot refund a competing dispatch after failed preparation", async () => {
  const f = setup();
  f.deps.prepare = () => {
    throw new Error("preflight");
  };
  f.deps.retire = () => {
    f.calls.push("retire");
    throw new Error("in flight");
  };
  assertEquals(
    await executePublicationPhotoModeration(f.identity, f.work, f.deps),
    "pending",
  );
  assertEquals(f.calls, ["retire"]);
});
Deno.test("photo execution malformed provider outcome retains charge without retry", async () => {
  const f = setup();
  f.deps.prepare = () =>
    Promise.resolve({
      proof: f.proof,
      invoke: () => {
        f.calls.push("invoke");
        throw new Error("uncertain");
      },
    });
  assertEquals(
    await executePublicationPhotoModeration(f.identity, f.work, f.deps),
    "pending",
  );
  assertEquals(f.calls, ["saveProof", "dispatch", "invoke"]);
});
Deno.test("photo execution repeated completion errors remain pending without another invocation", async () => {
  const f = setup();
  f.deps.complete = () => {
    f.calls.push("complete");
    throw new Error("uncertain");
  };
  assertEquals(
    await executePublicationPhotoModeration(f.identity, f.work, f.deps),
    "pending",
  );
  assertEquals(f.calls, [
    "prepare",
    "saveProof",
    "dispatch",
    "invoke",
    "complete",
    "complete",
  ]);
});
Deno.test("photo execution recovery retires expired dispatch but never regenerates output", async () => {
  const f = setup();
  f.work.state = "dispatched";
  f.deps.retire = () => {
    f.calls.push("retire");
    return Promise.resolve("unknown_execution");
  };
  assertEquals(
    await executePublicationPhotoModeration(f.identity, f.work, f.deps),
    "unknown_execution",
  );
  assertEquals(f.calls, ["retire"]);
});
Deno.test("photo execution terminal recovery does no provider work and bad binding fails before I/O", async () => {
  const f = setup();
  f.work.state = "approved";
  f.work.lease_token = null;
  assertEquals(
    await executePublicationPhotoModeration(f.identity, f.work, f.deps),
    "approved",
  );
  assertEquals(f.calls, []);
  f.work.model = "other";
  await assertRejects(
    () => executePublicationPhotoModeration(f.identity, f.work, f.deps),
    Error,
    "invalid_analysis_history",
  );
  assertEquals(f.calls, []);
});

Deno.test("photo execution SQL pins the actual prepared classifier policy digest", async () => {
  const bytes = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  const f = setup();
  f.work.source.byte_count = bytes.length;
  f.work.source.sha256 = await evidenceDigest(bytes);
  const p = await preparePublicationPhotoClassifier(f.work.source, {
    apiKey: () => "synthetic",
    readSource: () => Promise.resolve(bytes),
  });
  const sql = await Deno.readTextFile(
    new URL(
      "../../../migrations/20261004091533_bind_publication_photo_execution.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(sql, `'policy_sha256','${p.proof.policy_sha256}'`);
});

Deno.test("photo execution freezes owner and attempt scope before preparation can suspend", async () => {
  const f = setup();
  const prepare = f.deps.prepare!;
  f.deps.prepare = async (source) => {
    f.identity.owner_id = id(8);
    f.work.attempt_id = id(9);
    f.work.lease_token = id(10);
    return await prepare(source);
  };
  assertEquals(
    await executePublicationPhotoModeration(f.identity, f.work, f.deps),
    "approved",
  );
});
