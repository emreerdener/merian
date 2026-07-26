import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

const appRoot = new URL("../", import.meta.url);

async function source(path: string) {
  return await readFile(new URL(path, appRoot), "utf8");
}

async function productionSourcePaths(path: string): Promise<string[]> {
  const entries = await readdir(new URL(path, appRoot), {
    withFileTypes: true,
  });
  const ignoredDirectories = new Set([
    ".next",
    ".turbo",
    ".vercel",
    "coverage",
    "node_modules",
    "out",
  ]);
  const paths = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = `${path}/${entry.name}`;
      if (entry.isDirectory()) {
        if (ignoredDirectories.has(entry.name)) {
          return [];
        }
        return productionSourcePaths(entryPath);
      }
      if (
        /\.(?:[cm]?[jt]sx?)$/.test(entry.name) &&
        !entry.name.includes(".test.")
      ) {
        return [entryPath];
      }
      return [];
    }),
  );
  return paths.flat();
}

const allowedProductionEnvironment = new Set([
  "NEXT_PUBLIC_ADMIN_ORIGIN",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "NEXT_PUBLIC_SUPABASE_URL",
]);

type EnvironmentAccess = {
  key: string;
  location: string;
};

function isProcessEnv(node: ts.Node): boolean {
  if (
    ts.isPropertyAccessExpression(node) &&
    ts.isIdentifier(node.expression) &&
    node.expression.text === "process"
  ) {
    return node.name.text === "env";
  }
  return ts.isElementAccessExpression(node) &&
    ts.isIdentifier(node.expression) &&
    node.expression.text === "process" &&
    ts.isStringLiteralLike(node.argumentExpression) &&
    node.argumentExpression.text === "env";
}

function productionSourceAssurance(
  path: string,
  text: string,
): {
  credentialReferences: string[];
  environmentAccesses: EnvironmentAccess[];
} {
  const scriptKind = path.endsWith(".tsx")
    ? ts.ScriptKind.TSX
    : ts.ScriptKind.TS;
  const syntaxTree = ts.createSourceFile(
    path,
    text,
    ts.ScriptTarget.Latest,
    true,
    scriptKind,
  );
  const credentialReferences: string[] = [];
  const environmentAccesses: EnvironmentAccess[] = [];

  function location(node: ts.Node): string {
    const position = syntaxTree.getLineAndCharacterOfPosition(
      node.getStart(syntaxTree),
    );
    return `${path}:${position.line + 1}`;
  }

  function visit(node: ts.Node) {
    if (ts.isIdentifier(node) || ts.isStringLiteralLike(node)) {
      if (/service[_-]?role|supabase[_-]?secret|sb_secret_/i.test(node.text)) {
        credentialReferences.push(location(node));
      }
    }
    if (isProcessEnv(node)) {
      const parent = node.parent;
      if (ts.isPropertyAccessExpression(parent) && parent.expression === node) {
        environmentAccesses.push({
          key: parent.name.text,
          location: location(parent),
        });
      } else if (
        ts.isElementAccessExpression(parent) &&
        parent.expression === node &&
        ts.isStringLiteralLike(parent.argumentExpression)
      ) {
        environmentAccesses.push({
          key: parent.argumentExpression.text,
          location: location(parent),
        });
      } else {
        environmentAccesses.push({
          key: "<computed-or-whole-process.env>",
          location: location(node),
        });
      }
    }
    ts.forEachChild(node, visit);
  }

  visit(syntaxTree);
  return { credentialReferences, environmentAccesses };
}

function assignedEnvironment(text: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (
    const line of text
      .split(/\r?\n/)
      .map((candidate) => candidate.trim())
      .filter((candidate) => candidate.length > 0 && !candidate.startsWith("#"))
  ) {
    const assignment = /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$/.exec(
      line,
    );
    assert.ok(assignment, `Invalid .env.example assignment: ${line}`);
    assert.equal(
      result[assignment[1]],
      undefined,
      `Duplicate .env.example key: ${assignment[1]}`,
    );
    result[assignment[1]] = assignment[2].trim();
  }
  return result;
}

test("production source assurance fails closed on privileged and dynamic environment access", () => {
  const allowed = productionSourceAssurance(
    "allowed.ts",
    [
      "const url = process.env.NEXT_PUBLIC_SUPABASE_URL;",
      'const key = process.env["NEXT_PUBLIC_SUPABASE_ANON_KEY"];',
      "// SUPABASE_SERVICE_ROLE_KEY is prohibited.",
    ].join("\n"),
  );
  assert.deepEqual(allowed.credentialReferences, []);
  assert.deepEqual(
    allowed.environmentAccesses.map(({ key }) => key),
    ["NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY"],
  );

  const prohibited = productionSourceAssurance(
    "prohibited.ts",
    [
      "const secret = process.env.SUPABASE_SECRET_KEY;",
      "const dynamic = process.env[keyName];",
      "const copiedEnvironment = process.env;",
    ].join("\n"),
  );
  assert.equal(prohibited.credentialReferences.length, 1);
  assert.deepEqual(
    prohibited.environmentAccesses.map(({ key }) => key),
    [
      "SUPABASE_SECRET_KEY",
      "<computed-or-whole-process.env>",
      "<computed-or-whole-process.env>",
    ],
  );
});

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

test("anonymous admin routing does not call the restricted access-state RPC", async () => {
  const admin = await source("lib/admin.ts");
  const getAccessStateBody = admin.slice(
    admin.indexOf("export async function getAccessState"),
    admin.indexOf("export async function requireAdmin"),
  );
  const authCheck = getAccessStateBody.indexOf("supabase.auth.getUser()");
  const accessRpc = getAccessStateBody.indexOf(
    'supabase.rpc("admin_get_access_state")',
  );

  assert.notEqual(authCheck, -1);
  assert.notEqual(accessRpc, -1);
  assert.ok(authCheck < accessRpc);
  assert.match(getAccessStateBody, /!userResult\.user/);
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
  for (const text of [reviews, feedback, access]) {
    assert.match(text, /p_limit: 100/);
  }
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

test("admin production syntax can access only the public environment allowlist", async () => {
  const paths = await productionSourcePaths(".");
  const files = await Promise.all(
    paths.map(async (path) => ({ path, text: await source(path) })),
  );
  const assurances = files.map(({ path, text }) =>
    productionSourceAssurance(path, text)
  );
  const credentialReferences = assurances.flatMap(
    (assurance) => assurance.credentialReferences,
  );
  assert.deepEqual(
    credentialReferences,
    [],
    `Privileged credential references in production syntax: ${
      credentialReferences.join(", ")
    }`,
  );

  const environmentAccesses = assurances.flatMap(
    (assurance) => assurance.environmentAccesses,
  );
  const rejectedAccesses = environmentAccesses.filter(
    ({ key }) => !allowedProductionEnvironment.has(key),
  );
  assert.deepEqual(
    rejectedAccesses,
    [],
    `Unapproved production environment access: ${
      rejectedAccesses
        .map(({ key, location }) => `${key} at ${location}`)
        .join(", ")
    }`,
  );
  const referencedKeys = new Set(environmentAccesses.map(({ key }) => key));
  assert.equal(
    referencedKeys.has("NEXT_PUBLIC_SUPABASE_URL"),
    true,
    "The public Supabase URL boundary was not found",
  );
  assert.equal(
    referencedKeys.has("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
    true,
    "The public Supabase key boundary was not found",
  );

  const environmentExample = await source(".env.example");
  assert.deepEqual(assignedEnvironment(environmentExample), {
    NEXT_PUBLIC_SUPABASE_URL: "https://YOUR_PROJECT.supabase.co",
    NEXT_PUBLIC_SUPABASE_ANON_KEY: "YOUR_PUBLISHABLE_OR_ANON_KEY",
    NEXT_PUBLIC_ADMIN_ORIGIN: "https://admin.naturebook.earth",
  });
});
