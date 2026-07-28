import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  createDwcaDownloadGrant,
  DOWNLOAD_GRANT_LIFETIME_SECONDS,
  sha256Hex,
} from "./downloadGrant.ts";

Deno.test("createDwcaDownloadGrant produces an opaque URL and fixed expiry", () => {
  const now = new Date("2026-07-28T04:00:00.000Z");
  const grant = createDwcaDownloadGrant(
    "https://project-ref.supabase.co",
    {
      now,
      randomBytes(bytes) {
        bytes.fill(7);
        return bytes;
      },
    },
  );

  const parsed = new URL(grant.url);
  assertEquals(parsed.origin, "https://project-ref.supabase.co");
  assertEquals(parsed.pathname, "/functions/v1/download-dwca");
  assertEquals(parsed.searchParams.get("token"), grant.token);
  assertEquals(grant.token.length, 43);
  assertEquals(
    grant.expiresAt,
    new Date(
      now.getTime() + DOWNLOAD_GRANT_LIFETIME_SECONDS * 1000,
    ).toISOString(),
  );
});

Deno.test("createDwcaDownloadGrant rejects a non-HTTPS authority", () => {
  assertThrows(
    () => createDwcaDownloadGrant("http://localhost:54321"),
    TypeError,
    "Supabase URL is invalid",
  );
});

Deno.test("sha256Hex hashes tokens without retaining plaintext", async () => {
  assertEquals(
    await sha256Hex("deterministic-token"),
    "5a8a7444739ac5e87029fa814ce77a879c33689b806e35ffefe88ee7fa04603b",
  );
  assertEquals(
    (await sha256Hex("different-token")) ===
      (await sha256Hex("deterministic-token")),
    false,
  );
});
