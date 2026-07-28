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
  assert.match(source, /SUPABASE_SECRET_KEYS/);
  assert.match(source, /SUPABASE_SERVER_API_KEY/);
  assert.match(source, /resolveServerApiKeySources/);
  assert.match(source, /startsWith\("sb_secret_"\)/);
  assert.match(source, /input instanceof Request \? input\.headers/);
  assert.match(source, /headers\.delete\("Authorization"\)/);
  assert.match(source, /AbortSignal\.timeout/);
  assert.match(source, /AbortSignal\.any/);
  assert.doesNotMatch(source, /SUPABASE_ANON_KEY/);
});

test("the server API key resolver rejects public-key configuration", async () => {
  const source = await readFile(
    new URL("./serverApiKey.ts", import.meta.url),
    "utf8",
  );

  assert.match(source, /payload\?\.role === "service_role"/);
  assert.match(source, /header\?\.alg === "HS256"/);
  assert.match(source, /invalid_server_api_key_configuration/);
  assert.match(source, /isSupportedServerApiKey/);
  assert.match(source, /isCurrentSecretKey/);
  assert.match(source, /MINIMUM_OPAQUE_KEY_SUFFIX_LENGTH = 20/);
  assert.match(source, /HS256_BASE64URL_SIGNATURE_LENGTH = 43/);
});

test("the public Supabase client cannot consume privileged credentials", async () => {
  const source = await readFile(
    new URL("./supabasePublic.ts", import.meta.url),
    "utf8",
  );

  assert.doesNotMatch(source, /SERVICE_ROLE|sb_secret_/);
  assert.match(source, /SUPABASE_ANON_KEY/);
});

test("anonymous Explore pages use only the scoped server projection", async () => {
  const [source, environmentExample] = await Promise.all([
    readFile(new URL("./explore.ts", import.meta.url), "utf8"),
    readFile(new URL("../.env.example", import.meta.url), "utf8"),
  ]);

  assert.match(source, /^import "server-only";/);
  assert.match(source, /createAdminSupabaseClient/);
  assert.match(source, /get_public_web_explore_posts/);
  assert.match(source, /get_public_web_explore_post_page/);
  assert.match(source, /p_target_post_id: null/);
  assert.match(source, /p_max_limit: Math\.min\(limit, 48\)/);
  assert.doesNotMatch(
    source,
    /supabase\.rpc\(\s*"get_public_web_explore_post_detail"/,
  );
  assert.doesNotMatch(source, /createPublicServerSupabaseClient/);
  assert.doesNotMatch(source, /SUPABASE_PUBLIC_VIEWER_ID/);
  assert.doesNotMatch(source, /\.from\("users"\)/);
  assert.doesNotMatch(source, /get_explore_feed|get_explore_post\b/);
  assert.match(environmentExample, /^SUPABASE_SERVER_API_KEY=/m);
  assert.doesNotMatch(environmentExample, /SUPABASE_PUBLIC_VIEWER_ID/);
});
