import { assert, assertEquals, assertRejects } from "@std/assert";
import { fileJournal } from "./journal.ts";

Deno.test("durable local journal refuses existing and truncated runs", async () => {
  const root = ".artifacts/client-prepared-media/verifier-local-candidate";
  const directory = await Deno.makeTempDir({
    dir: root,
    prefix: "journal-check-",
  });
  const path = `${directory}/run.jsonl`, journal = fileJournal(path);
  await journal.begin();
  await journal.save({
    phase: "running",
    attempted: [1],
    ordinaryCallsReserved: 53,
    cleanupCalls: 0,
    transferReserved: 67_239_936,
    obligations: [1],
    reason: "",
  });
  const lines = (await Deno.readTextFile(path)).trim().split("\n");
  assertEquals(lines.length, 2);
  assert(JSON.parse(lines[0]).started);
  assertEquals(JSON.parse(lines[1]).obligations, [1]);
  await assertRejects(() => journal.begin());
  await assertRejects(() => fileJournal(path).begin());
  const truncated = `${directory}/interrupted.jsonl`;
  await Deno.writeTextFile(truncated, "{");
  await assertRejects(() => fileJournal(truncated).begin());
  // Retained tiny synthetic evidence; never remove prior run journals.
});
