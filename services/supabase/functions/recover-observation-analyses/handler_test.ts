import { assertEquals, assertRejects } from "@std/assert";
import { recoverObservationAnalyses } from "./handler.ts";
const item = {
  owner_id: "00000000-0000-4000-8000-000000000001",
  observation_id: "00000000-0000-4000-8000-000000000002",
  analysis_id: "00000000-0000-4000-8000-000000000003",
};
Deno.test("history recovery uses one bounded pass and continues past deleted work", async () => {
  let calls = 0;
  assertEquals(
    await recoverObservationAnalyses({
      list: () => Promise.resolve([item, item]),
      now: () => 0,
      recover: () => {
        calls++;
        return calls === 1
          ? Promise.reject(new Error("deleted"))
          : Promise.resolve(true);
      },
    }),
    { attempted: 2, completed: 1 },
  );
});
Deno.test("history recovery enforces both runtime and batch limits", async () => {
  let now = 0;
  assertEquals(
    await recoverObservationAnalyses({
      list: () => Promise.resolve([item, item]),
      now: () => now,
      recover: () => {
        now = 40_001;
        return Promise.resolve(true);
      },
    }),
    { attempted: 1, completed: 1 },
  );
  await assertRejects(() =>
    recoverObservationAnalyses({
      list: () => Promise.resolve(Array(11).fill(item)),
      now: () => 0,
      recover: () => Promise.resolve(true),
    })
  );
});
