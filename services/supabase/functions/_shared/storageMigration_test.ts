import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { migrateUserStorage } from "./storageMigration.ts";

type ScanRow = {
  id: string;
  image_storage_urls: string[] | null;
};

function supabaseForScans(scans: ScanRow[]) {
  const updates: Array<{ id: string; image_storage_urls: string[] }> = [];

  const selectQuery = {
    select: () => selectQuery,
    eq: () => selectQuery,
    order: () => selectQuery,
    range: () => Promise.resolve({ data: scans, error: null }),
  };

  const updateQuery = {
    eq: (_column: string, id: string) => {
      updates[updates.length - 1].id = id;
      return Promise.resolve({ error: null });
    },
  };

  return {
    updates,
    client: {
      from: (table: string) => {
        if (table !== "scans") throw new Error(`Unexpected table ${table}`);
        return {
          select: selectQuery.select,
          update: (values: { image_storage_urls: string[] }) => {
            updates.push({
              id: "",
              image_storage_urls: values.image_storage_urls,
            });
            return updateQuery;
          },
        };
      },
    },
  };
}

Deno.test("migrateUserStorage: copies source-prefix assets, deletes originals, and rewrites scan URLs", async () => {
  const copied: Array<{ sourceKey: string; targetKey: string }> = [];
  const deleted: string[] = [];
  const userId = "user-123";
  const { client, updates } = supabaseForScans([
    {
      id: "scan-1",
      image_storage_urls: [
        `https://media.merian.app/public_uploads/free/${userId}/leaf.webp`,
        `https://media.merian.app/public_uploads/pro/${userId}/already.webp`,
        "https://example.com/external.webp",
      ],
    },
  ]);

  await migrateUserStorage(userId, "free", "pro", client as never, {
    getR2Config: () => ({}) as never,
    copyR2Object: (sourceKey, targetKey) => {
      copied.push({ sourceKey, targetKey });
      return Promise.resolve(new Response(null, { status: 200 }));
    },
    deleteR2Object: (key) => {
      deleted.push(key);
      return Promise.resolve(new Response(null, { status: 204 }));
    },
  });

  assertEquals(copied, [{
    sourceKey: `public_uploads/free/${userId}/leaf.webp`,
    targetKey: `public_uploads/pro/${userId}/leaf.webp`,
  }]);
  assertEquals(deleted, [`public_uploads/free/${userId}/leaf.webp`]);
  assertEquals(updates, [{
    id: "scan-1",
    image_storage_urls: [
      `https://media.merian.app/public_uploads/pro/${userId}/leaf.webp`,
      `https://media.merian.app/public_uploads/pro/${userId}/already.webp`,
      "https://example.com/external.webp",
    ],
  }]);
});

Deno.test("migrateUserStorage: skips assets owned by another user", async () => {
  const copied: string[] = [];
  const deleted: string[] = [];
  const { client, updates } = supabaseForScans([
    {
      id: "scan-1",
      image_storage_urls: [
        "https://media.merian.app/public_uploads/free/other-user/leaf.webp",
      ],
    },
  ]);

  await migrateUserStorage("user-123", "free", "pro", client as never, {
    getR2Config: () => ({}) as never,
    copyR2Object: (sourceKey) => {
      copied.push(sourceKey);
      return Promise.resolve(new Response(null, { status: 200 }));
    },
    deleteR2Object: (key) => {
      deleted.push(key);
      return Promise.resolve(new Response(null, { status: 204 }));
    },
  });

  assertEquals(copied, []);
  assertEquals(deleted, []);
  assertEquals(updates, []);
});

Deno.test("migrateUserStorage: leaves source URL in place when copy fails", async () => {
  const deleted: string[] = [];
  const userId = "user-123";
  const sourceUrl =
    `https://media.merian.app/public_uploads/pro/${userId}/leaf.webp`;
  const { client, updates } = supabaseForScans([
    { id: "scan-1", image_storage_urls: [sourceUrl] },
  ]);

  await migrateUserStorage(userId, "pro", "free", client as never, {
    getR2Config: () => ({}) as never,
    copyR2Object: () =>
      Promise.resolve(
        new Response(null, {
          status: 500,
          statusText: "copy failed",
        }),
      ),
    deleteR2Object: (key) => {
      deleted.push(key);
      return Promise.resolve(new Response(null, { status: 204 }));
    },
  });

  assertEquals(deleted, []);
  assertEquals(updates, []);
});
