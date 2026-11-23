import { assertEquals } from "@std/assert";
import { createClient } from "@supabase/supabase-js";
import { recoverVideoAnalyses } from "./db.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const item = (n: number) => ({
  owner_id: id(1),
  observation_id: id(2),
  analysis_id: id(n),
});
function client(
  lists: Record<string, unknown>,
  calls: string[],
  claim: unknown = { claimed: false },
) {
  return createClient("https://example.invalid", "synthetic-key", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input) => {
        const url = typeof input === "string"
          ? input
          : input instanceof URL
          ? input.href
          : input.url;
        const rpc = new URL(url).pathname.split("/").pop()!;
        calls.push(rpc);
        return Promise.resolve(
          new Response(
            JSON.stringify(rpc.startsWith("list_") ? lists[rpc] : claim),
            { headers: { "Content-Type": "application/json" } },
          ),
        );
      },
    },
  });
}
Deno.test("shared recovery interleaves families inside one 32-item budget", async () => {
  const calls: string[] = [];
  const executed: string[] = [];
  const c = client(
    {
      list_observation_video_analysis_recovery: Array.from(
        { length: 32 },
        (_, i) => item(i + 10),
      ),
      list_observation_composition_analysis_recovery: Array.from(
        { length: 32 },
        (_, i) => item(i + 100),
      ),
    },
    calls,
    { claimed: true, state: "draft" },
  );
  await recoverVideoAnalyses(c, {
    video: () => {
      executed.push("video");
      return Promise.resolve("complete" as const);
    },
    composition: () => {
      executed.push("composition");
      return Promise.resolve("complete" as const);
    },
  });
  assertEquals(
    executed,
    Array.from({ length: 16 }, () => ["video", "composition"]).flat(),
  );
  assertEquals(calls.filter((x) => x.startsWith("claim_")).length, 32);
});
Deno.test("disabled composition leaves video recovery working without claims from the disabled family", async () => {
  const calls: string[] = [];
  await recoverVideoAnalyses(
    client({
      list_observation_video_analysis_recovery: [item(10)],
      list_observation_composition_analysis_recovery: [],
    }, calls),
  );
  assertEquals(calls, [
    "list_observation_video_analysis_recovery",
    "list_observation_composition_analysis_recovery",
    "claim_observation_video_analysis_recovery",
  ]);
});
Deno.test("duplicate or malformed discovery cannot claim work", async () => {
  for (const mixed of [[item(10)], [{ ...item(12), token: "forbidden" }]]) {
    const calls: string[] = [];
    try {
      await recoverVideoAnalyses(
        client({
          list_observation_video_analysis_recovery: [item(10)],
          list_observation_composition_analysis_recovery: mixed,
        }, calls),
      );
    } catch { /* closed discovery */ }
    assertEquals(calls.filter((x) => x.startsWith("claim_")), []);
  }
});
Deno.test("unknown claim state never runs either executor", async () => {
  const calls: string[] = [];
  let executions = 0;
  const run = () => {
    executions++;
    return Promise.resolve("complete" as const);
  };
  await recoverVideoAnalyses(
    client(
      {
        list_observation_video_analysis_recovery: [],
        list_observation_composition_analysis_recovery: [item(10)],
      },
      calls,
      { claimed: true, state: "claimed" },
    ),
    { video: run, composition: run },
  );
  assertEquals(executions, 0);
});
