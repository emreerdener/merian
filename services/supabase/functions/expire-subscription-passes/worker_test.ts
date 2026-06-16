import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { processExpiredSubscriptionPasses } from "./worker.ts";

Deno.test("processExpiredSubscriptionPasses: downgrades expired timed pro users and migrates storage", async () => {
  const downgraded: Array<{ userId: string; boundaryIso: string }> = [];
  const migrated: Array<{ userId: string; source: string; target: string }> =
    [];
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
    storageMigrator: (userId, source, target) => {
      migrated.push({ userId, source, target });
      return Promise.resolve();
    },
  });

  assertEquals(result, { scanned: 1, downgraded: 1 });
  assertEquals(downgraded, [{
    userId: "expired-pass-user",
    boundaryIso: "2026-06-16T12:00:00.000Z",
  }]);
  assertEquals(migrated, [{
    userId: "expired-pass-user",
    source: "pro",
    target: "free",
  }]);
});

Deno.test("processExpiredSubscriptionPasses: standard pro and future pass users are untouched when fetch returns none", async () => {
  const downgraded: string[] = [];
  const migrated: string[] = [];

  const result = await processExpiredSubscriptionPasses(
    {} as never,
    new Date("2026-06-16T12:00:00.000Z"),
    {
      fetchExpiredUsers: () => Promise.resolve([]),
      downgradeUser: (userId) => {
        downgraded.push(userId);
        return Promise.resolve(true);
      },
      storageMigrator: (userId) => {
        migrated.push(userId);
        return Promise.resolve();
      },
    },
  );

  assertEquals(result, { scanned: 0, downgraded: 0 });
  assertEquals(downgraded, []);
  assertEquals(migrated, []);
});

Deno.test("processExpiredSubscriptionPasses: skips migration when guarded downgrade no longer matches", async () => {
  const migrated: string[] = [];

  const result = await processExpiredSubscriptionPasses(
    {} as never,
    new Date("2026-06-16T12:00:00.000Z"),
    {
      fetchExpiredUsers: () => Promise.resolve([{ id: "renewed-user" }]),
      downgradeUser: () => Promise.resolve(false),
      storageMigrator: (userId) => {
        migrated.push(userId);
        return Promise.resolve();
      },
    },
  );

  assertEquals(result, { scanned: 1, downgraded: 0 });
  assertEquals(migrated, []);
});
