import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("the privileged Supabase client is guarded and never falls back", async () => {
  const source = await readFile(
    new URL("./supabaseAdmin.ts", import.meta.url),
    "utf8",
  );

  assert.match(source, /^import "server-only";/);
  assert.match(source, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.doesNotMatch(source, /SUPABASE_ANON_KEY/);
});

test("the public Supabase client cannot consume privileged credentials", async () => {
  const source = await readFile(
    new URL("./supabasePublic.ts", import.meta.url),
    "utf8",
  );

  assert.doesNotMatch(source, /SERVICE_ROLE|sb_secret_/);
  assert.match(source, /SUPABASE_ANON_KEY/);
});
