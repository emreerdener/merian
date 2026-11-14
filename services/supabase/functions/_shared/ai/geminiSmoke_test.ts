import { assertEquals, assertRejects } from "@std/assert";
import {
  type FrozenGeminiSmokeCase,
  type GeminiSmokeRepository,
  runGeminiReleaseSmoke,
} from "./geminiSmoke.ts";
import type { GeminiResponseReceipt } from "./geminiEnvelope.ts";
const receipt: GeminiResponseReceipt = {
  returnedModel: "gemini-3.8-flash",
  usage: null,
  usageConsistent: false,
  finishReason: "STOP",
  failure: null,
};
function fixture(crash = false) {
  let calls = 0;
  let state = "ready";
  let stored: GeminiResponseReceipt | null = null;
  const catalog = new Map<string, FrozenGeminiSmokeCase>([["synthetic", {
    id: "synthetic",
    digest: "digest",
    model: "gemini-3.8-flash",
    reservationMicrousd: 100,
    async execute(hooks) {
      await hooks.beforeTransport();
      calls++;
      if (crash) throw new Error("synthetic crash after provider dispatch");
      await hooks.recordResponse(receipt);
    },
  }]]);
  const repository: GeminiSmokeRepository = {
    claim() {
      if (state !== "ready") return Promise.resolve({ state, receipt: stored });
      state = "claimed";
      return Promise.resolve({
        state,
        owner_token: "owner",
        case_digest: "digest",
        model: "gemini-3.8-flash",
      });
    },
    dispatch() {
      state = "dispatch_intent";
      return Promise.resolve();
    },
    receipt(_r, _c, _o, value) {
      stored = value;
      return Promise.resolve();
    },
    outcome(_r, _c, _o, _v, valid) {
      state = valid ? "passed" : "failed";
      return Promise.resolve(state);
    },
    uncertain() {
      state = "uncertain";
      return Promise.resolve();
    },
  };
  return { catalog, repository, calls: () => calls };
}
Deno.test("concurrent smoke claims execute exactly once and retry only reads receipts", async () => {
  const f = fixture();
  await Promise.all([
    runGeminiReleaseSmoke("release", "synthetic", f.catalog, f.repository),
    runGeminiReleaseSmoke("release", "synthetic", f.catalog, f.repository),
  ]);
  assertEquals(f.calls(), 1);
  assertEquals(
    await runGeminiReleaseSmoke(
      "release",
      "synthetic",
      f.catalog,
      f.repository,
    ),
    { state: "passed", reused: true },
  );
  assertEquals(f.calls(), 1);
});
Deno.test("crash after dispatch cannot become passing evidence or repeat a paid call", async () => {
  const f = fixture(true);
  assertEquals(
    await runGeminiReleaseSmoke(
      "release",
      "synthetic",
      f.catalog,
      f.repository,
    ),
    { state: "uncertain", reused: false },
  );
  assertEquals(
    await runGeminiReleaseSmoke(
      "release",
      "synthetic",
      f.catalog,
      f.repository,
    ),
    { state: "uncertain", reused: true },
  );
  assertEquals(f.calls(), 1);
});
Deno.test("unknown smoke case cannot claim or dispatch", async () => {
  const f = fixture();
  await assertRejects(
    () => runGeminiReleaseSmoke("release", "override", f.catalog, f.repository),
    Error,
    "gemini_smoke_case_unknown",
  );
  assertEquals(f.calls(), 0);
});
