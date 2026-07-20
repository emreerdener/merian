import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const appRoot = new URL("../", import.meta.url);

async function source(path: string) {
  return await readFile(new URL(path, appRoot), "utf8");
}

test("admin data routes require membership, AAL2, role, and an active RPC session", async () => {
  const [admin, mfa, shell] = await Promise.all([
    source("lib/admin.ts"),
    source("app/mfa/page.tsx"),
    source("components/AdminShell.tsx"),
  ]);
  assert.match(admin, /access\.aal !== "aal2"/);
  assert.match(admin, /admin_begin_session/);
  assert.match(admin, /roleRank\[access\.role\] < roleRank\[minimumRole\]/);
  assert.match(mfa, /!access\?\.is_member/);
  assert.match(shell, /owner: 3/);
  assert.match(shell, /href: "\/access", label: "Audit & access", minimum: 3/);
  assert.match(shell, /href: "\/reviews", label: "Review queue", minimum: 2/);
});

test("response and browser boundaries are private by default", async () => {
  const [proxy, config, layout] = await Promise.all([
    source("proxy.ts"),
    source("next.config.ts"),
    source("app/layout.tsx"),
  ]);
  assert.match(proxy, /frame-ancestors 'none'/);
  assert.match(proxy, /script-src 'self' 'nonce-/);
  assert.match(config, /private, no-store/);
  assert.match(config, /noindex, nofollow/);
  assert.match(layout, /robots: \{ index: false/);
});

test("mutations check origin and raw user searches remain out of URLs", async () => {
  const [actions, users] = await Promise.all([
    source("app/actions.ts"),
    source("components/UserSearch.tsx"),
  ]);
  assert.match(actions, /new URL\(origin\)\.host !== host/);
  assert.match(actions, /verifyMutationOrigin\(\)/);
  assert.match(users, /Search terms are sent in the request body/);
  assert.doesNotMatch(users, /URLSearchParams/);
});

test("review, feedback, user, and audit lists use bounded cursor pagination", async () => {
  const [reviews, feedback, users, access] = await Promise.all([
    source("app/(admin)/reviews/page.tsx"),
    source("app/(admin)/feedback/page.tsx"),
    source("components/UserSearch.tsx"),
    source("app/(admin)/access/page.tsx"),
  ]);
  assert.match(reviews, /p_cursor_updated_at/);
  assert.match(feedback, /p_cursor_created_at/);
  assert.match(users, /nextCursor/);
  assert.match(access, /p_cursor_id/);
  for (const text of [reviews, feedback, access]) assert.match(text, /p_limit: 100/);
});

test("server-rendered admin pages pass only serializable component props", async () => {
  const pages = await Promise.all([
    source("app/(admin)/reviews/page.tsx"),
    source("app/(admin)/feedback/page.tsx"),
    source("app/(admin)/access/page.tsx"),
  ]);
  for (const page of pages) {
    assert.doesNotMatch(page, /component=\{Link\}/);
  }
});

test("the admin bundle never references a Supabase service-role secret", async () => {
  const files = await Promise.all([
    source("lib/env.ts"),
    source("lib/supabase-server.ts"),
    source("lib/supabase-browser.ts"),
    source(".env.example"),
  ]);
  assert.doesNotMatch(files.join("\n").toLowerCase(), /service[_-]?role/);
});
