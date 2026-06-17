import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { processExpiredSubscriptionPasses } from "./worker.ts";

Deno.test("processExpiredSubscriptionPasses: downgrades expired timed pro users", async () => {
  const downgraded: Array<{ userId: string; boundaryIso: string }> = [];
  const now = new Date("2026-06-16T12:00:00.000Z");

  const result = await processExpiredSubscriptionPasses({} as never, now, {
    fetchExpiredUsers: (boundaryIso) => {
      assertEquals(boundaryIso, "2026-06-16T12:00:00.000Z");
      return Promise.resolve([{ id: "expired-pass-user" }]);
    },
    downgradeUser: (userId, boundaryIso) => {
      downgraded.push({ userId, boundaryIso });
      return Promise.resolve(true);
    },
  });

  assertEquals(result, { scanned: 1, downgraded: 1 });
  assertEquals(downgraded, [{
    userId: "expired-pass-user",
    boundaryIso: "2026-06-16T12:00:00.000Z",
  }]);
});

Deno.test("processExpiredSubscriptionPasses: standard pro and future pass users are untouched when fetch returns none", async () => {
  const downgraded: string[] = [];

  const result = await processExpiredSubscriptionPasses(
    {} as never,
    new Date("2026-06-16T12:00:00.000Z"),
    {
      fetchExpiredUsers: () => Promise.resolve([]),
      downgradeUser: (userId) => {
        downgraded.push(userId);
        return Promise.resolve(true);
      },
    },
  );

  assertEquals(result, { scanned: 0, downgraded: 0 });
  assertEquals(downgraded, []);
});

Deno.test("processExpiredSubscriptionPasses: skips stale rows when guarded downgrade no longer matches", async () => {
  const result = await processExpiredSubscriptionPasses(
    {} as never,
    new Date("2026-06-16T12:00:00.000Z"),
    {
      fetchExpiredUsers: () => Promise.resolve([{ id: "renewed-user" }]),
      downgradeUser: () => Promise.resolve(false),
    },
  );

  assertEquals(result, { scanned: 1, downgraded: 0 });
});
