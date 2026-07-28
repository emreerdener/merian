import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { authorizeDwcaArchiveDownload } from "./db.ts";

const tokenHash = "a".repeat(64);
const ipHash = "b".repeat(64);
const objectKey =
  "exports/00000000-0000-4000-8000-000000000201/00000000-0000-4000-8000-000000000202/00000000-0000-4000-8000-000000000203.zip";

function client(data: unknown, error: unknown = null): SupabaseClient {
  return {
    rpc(name: string, args: Record<string, unknown>) {
      assertEquals(name, "authorize_dwca_archive_download");
      assertEquals(args, {
        p_token_sha256: tokenHash,
        p_ip_hash: ipHash,
      });
      return Promise.resolve({ data, error });
    },
  } as unknown as SupabaseClient;
}

Deno.test("download authorization validates each database outcome", async () => {
  assertEquals(
    await authorizeDwcaArchiveDownload(
      tokenHash,
      ipHash,
      client({ status: "authorized", object_key: objectKey }),
    ),
    { status: "authorized", objectKey },
  );
  assertEquals(
    await authorizeDwcaArchiveDownload(
      tokenHash,
      ipHash,
      client({ status: "rate_limited", retry_after_seconds: 300 }),
    ),
    { status: "rate_limited", retryAfterSeconds: 300 },
  );
  assertEquals(
    await authorizeDwcaArchiveDownload(
      tokenHash,
      ipHash,
      client({ status: "not_ready", retry_after_seconds: 5 }),
    ),
    { status: "not_ready", retryAfterSeconds: 5 },
  );
  assertEquals(
    await authorizeDwcaArchiveDownload(
      tokenHash,
      ipHash,
      client({ status: "gone" }),
    ),
    { status: "gone" },
  );
});

Deno.test("download authorization fails closed on malformed or failed RPCs", async () => {
  await assertRejects(
    () =>
      authorizeDwcaArchiveDownload(
        tokenHash,
        ipHash,
        client({ status: "authorized", object_key: "../private.zip" }),
      ),
    Error,
    "invalid key",
  );
  await assertRejects(
    () =>
      authorizeDwcaArchiveDownload(
        tokenHash,
        ipHash,
        client(null, { message: "offline" }),
      ),
    Error,
    "unavailable",
  );
});
