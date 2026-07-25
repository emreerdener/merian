import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { keysetPages } from "./db.ts";
import { ExportWorkerError } from "./types.ts";

async function collectPages<T extends { id: string }>(
  pages: AsyncGenerator<T[]>,
): Promise<T[][]> {
  const result: T[][] = [];
  for await (const page of pages) result.push(page);
  return result;
}

Deno.test("keysetPages advances with the prior page's last id", async () => {
  const calls: Array<{ afterId: string | null; limit: number }> = [];
  const rows = [
    { id: "00000000-0000-4000-8000-000000000001" },
    { id: "00000000-0000-4000-8000-000000000002" },
    { id: "00000000-0000-4000-8000-000000000003" },
  ];

  const pages = await collectPages(
    keysetPages((afterId, limit) => {
      calls.push({ afterId, limit });
      return Promise.resolve(
        rows.filter((row) => afterId === null || row.id > afterId)
          .slice(0, limit),
      );
    }, 2),
  );

  assertEquals(pages, [rows.slice(0, 2), rows.slice(2)]);
  assertEquals(calls, [
    { afterId: null, limit: 2 },
    {
      afterId: "00000000-0000-4000-8000-000000000002",
      limit: 2,
    },
  ]);
});

Deno.test("keysetPages rejects non-monotonic provider results", async () => {
  const error = await assertRejects(
    () =>
      collectPages(
        keysetPages(() =>
          Promise.resolve([
            { id: "00000000-0000-4000-8000-000000000002" },
            { id: "00000000-0000-4000-8000-000000000001" },
          ])
        ),
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "database_unavailable");
});
