import {
  assert,
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationsDirectory = new URL("../../migrations/", import.meta.url);
const reactionHardeningMigration = new URL(
  "../../migrations/20260727190637_secure_explore_comment_reactions_and_defaults.sql",
  import.meta.url,
);
const userForeignKeyIndexMigration = new URL(
  "../../migrations/20260727190804_index_user_foreign_keys_for_identity_lifecycle.sql",
  import.meta.url,
);
const POLICY_GUARD_START = "20260727190637";
const TRANSACTION_CONTROL_GUARD_START = "20260727183356";

function withoutSqlComments(sql: string): string {
  return sql
    .replaceAll(/\/\*[\s\S]*?\*\//g, " ")
    .replaceAll(/--[^\r\n]*/g, " ");
}

function withoutSqlBodiesCommentsOrStrings(sql: string): string {
  const executableCharacters = sql.split("");
  const mask = (start: number, end: number) =>
    executableCharacters.fill(" ", start, end);

  for (let index = 0; index < sql.length;) {
    if (sql.startsWith("--", index)) {
      const newline = sql.indexOf("\n", index + 2);
      const end = newline === -1 ? sql.length : newline;
      mask(index, end);
      index = end;
      continue;
    }

    if (sql.startsWith("/*", index)) {
      const start = index;
      let depth = 1;
      index += 2;
      while (index < sql.length && depth > 0) {
        if (sql.startsWith("/*", index)) {
          depth += 1;
          index += 2;
        } else if (sql.startsWith("*/", index)) {
          depth -= 1;
          index += 2;
        } else {
          index += 1;
        }
      }
      mask(start, index);
      continue;
    }

    const dollarQuote = sql[index] === "$"
      ? sql.slice(index).match(
        /^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/,
      )?.[0]
      : undefined;
    if (dollarQuote) {
      const end = sql.indexOf(dollarQuote, index + dollarQuote.length);
      const quoteEnd = end === -1 ? sql.length : end + dollarQuote.length;
      mask(index, quoteEnd);
      index = quoteEnd;
      continue;
    }

    if (sql[index] === "'" || sql[index] === '"') {
      const delimiter = sql[index];
      const start = index;
      const escapePrefixIndex = index - 1;
      const escapeString = delimiter === "'" &&
        (sql[escapePrefixIndex] === "E" || sql[escapePrefixIndex] === "e") &&
        (escapePrefixIndex === 0 ||
          !/[A-Za-z0-9_$]/.test(sql[escapePrefixIndex - 1]));
      index += 1;
      while (index < sql.length) {
        if (sql[index] === delimiter && sql[index + 1] === delimiter) {
          index += 2;
        } else if (
          escapeString &&
          delimiter === "'" &&
          sql[index] === "\\" &&
          index + 1 < sql.length
        ) {
          index += 2;
        } else if (sql[index] === delimiter) {
          index += 1;
          break;
        } else {
          index += 1;
        }
      }
      mask(start, index);
      continue;
    }

    index += 1;
  }

  return executableCharacters.join("");
}

function usesTopLevelTransactionControl(sql: string): boolean {
  const executableSql = withoutSqlBodiesCommentsOrStrings(sql);
  return /(?:^|;)\s*(?:BEGIN(?:\s+(?:WORK|TRANSACTION))?\b|START\s+TRANSACTION\b|COMMIT\b|END(?:\s+(?:WORK|TRANSACTION))?\b|ROLLBACK\b|ABORT\b)/i
    .test(executableSql);
}

function normalizedIdentifier(identifier: string): string {
  return identifier.replaceAll('"', "").toLowerCase();
}

async function migrationSources(): Promise<Array<[string, string]>> {
  const sources: Array<[string, string]> = [];
  for await (const entry of Deno.readDir(migrationsDirectory)) {
    if (entry.isFile && entry.name.endsWith(".sql")) {
      sources.push([
        entry.name,
        await Deno.readTextFile(new URL(entry.name, migrationsDirectory)),
      ]);
    }
  }
  return sources.sort(([left], [right]) => left.localeCompare(right));
}

Deno.test("every migration-created public table has effective RLS", async () => {
  const createdTables = new Set<string>();
  const rlsTables = new Set<string>();
  const disableViolations: string[] = [];
  const unqualifiedTableViolations: string[] = [];

  for (const [name, source] of await migrationSources()) {
    const sql = withoutSqlComments(source);
    for (
      const match of sql.matchAll(
        /\bCREATE\s+(?:UNLOGGED\s+)?TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:(public)\.)?("[^"]+"|[a-z_][a-z0-9_]*)(?=\s*(?:\(|AS\b|PARTITION\b))/gi,
      )
    ) {
      createdTables.add(normalizedIdentifier(match[2]));
      if (name >= POLICY_GUARD_START && !match[1]) {
        unqualifiedTableViolations.push(
          `${name}: ${normalizedIdentifier(match[2])}`,
        );
      }
    }
    for (
      const match of sql.matchAll(
        /\bALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?(?:public\.)?("[^"]+"|[a-z_][a-z0-9_]*)\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY\b/gi,
      )
    ) {
      rlsTables.add(normalizedIdentifier(match[1]));
    }
    if (/\bDISABLE\s+ROW\s+LEVEL\s+SECURITY\b/i.test(sql)) {
      disableViolations.push(name);
    }
  }

  assert(createdTables.size > 0, "No public table declarations were found.");
  assertEquals(disableViolations, []);
  assertEquals(
    unqualifiedTableViolations,
    [],
    "New migration tables must use an explicit schema.",
  );
  assertEquals(
    [...createdTables].filter((table) => !rlsTables.has(table)).sort(),
    [],
    "Every table in the exposed public schema must enable RLS in migration history.",
  );
});

Deno.test("reaction hardening closes grants and RLS gaps", async () => {
  const sql = withoutSqlComments(
    await Deno.readTextFile(reactionHardeningMigration),
  ).replaceAll(/\s+/g, " ");

  for (
    const fragment of [
      "SET LOCAL lock_timeout = '5s'",
      "SET LOCAL statement_timeout = '5min'",
      "ALTER TABLE public.explore_comment_reactions ENABLE ROW LEVEL SECURITY",
      "REVOKE ALL PRIVILEGES ON TABLE public.explore_comment_reactions FROM PUBLIC, anon, authenticated, service_role",
      "GRANT SELECT, INSERT, DELETE ON TABLE public.explore_comment_reactions TO service_role",
      "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated, service_role",
      "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, anon, authenticated, service_role",
      "ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role",
      "ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, anon, authenticated, service_role",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("identity lifecycle migration indexes effective user foreign keys", async () => {
  const sql = withoutSqlComments(
    await Deno.readTextFile(userForeignKeyIndexMigration),
  ).replaceAll(/\s+/g, " ");

  for (
    const fragment of [
      "SET LOCAL lock_timeout = '5s'",
      "SET LOCAL statement_timeout = '15min'",
      "constraint_row.confrelid IN ( 'public.users'::REGCLASS, 'auth.users'::REGCLASS )",
      "source_namespace.nspname IN ('public', 'internal')",
      "source_table.relkind IN ('r', 'p')",
      "max_inline_relation_bytes CONSTANT BIGINT := 33554432",
      "index_row.indisvalid",
      "index_row.indisready",
      "index_row.indpred IS NULL",
      "index_row.indexprs IS NULL",
      "index_row.indkey[0] = constraint_row.conkey[1]",
      "ORDER BY source_namespace.nspname, source_table.relname, source_column.attname",
      "IF foreign_key.relation_kind = 'p' THEN",
      "Build valid leading indexes concurrently on every leaf partition, create the parent partitioned index as a metadata-only operation, then retry.",
      "IF pg_catalog.PG_RELATION_SIZE(foreign_key.table_oid) > max_inline_relation_bytes THEN",
      "Run CREATE INDEX CONCURRENTLY %I ON %I.%I (%I) outside db push, verify indisvalid and indisready, then retry.",
      "'CREATE INDEX %I ON %I.%I (%I)'",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }
});

Deno.test("new migrations preserve the CLI batch and history transaction", async () => {
  const violations: string[] = [];

  for (const [name, source] of await migrationSources()) {
    if (name < TRANSACTION_CONTROL_GUARD_START) continue;
    if (usesTopLevelTransactionControl(source)) {
      violations.push(name);
    }
  }

  assertEquals(
    violations,
    [],
    "Supabase CLI batches each migration and its history insert atomically; explicit transaction control can split them.",
  );
});

Deno.test("transaction-control guard covers aliases but ignores routine bodies", () => {
  for (
    const statement of [
      "BEGIN;",
      "BEGIN TRANSACTION;",
      "START TRANSACTION;",
      "COMMIT AND CHAIN;",
      "END;",
      "END WORK;",
      "ROLLBACK;",
      "ABORT;",
    ]
  ) {
    assert(
      usesTopLevelTransactionControl(statement),
      `Transaction control escaped the migration guard: ${statement}`,
    );
  }

  assert(
    !usesTopLevelTransactionControl(
      "DO $body$ BEGIN RAISE NOTICE 'COMMIT;'; END; $body$;\n" +
        "SELECT 'BEGIN;'; SELECT \"ROLLBACK\";",
    ),
  );
  assert(usesTopLevelTransactionControl("SELECT '--'; COMMIT;"));
  assert(usesTopLevelTransactionControl("SELECT '/*'; ROLLBACK;"));
});

Deno.test("new RLS policies use selected auth helpers and role clauses", async () => {
  const violations: string[] = [];

  for (const [name, source] of await migrationSources()) {
    if (name < POLICY_GUARD_START) continue;
    const sql = withoutSqlComments(source);
    for (
      const policy of sql.matchAll(/\bCREATE\s+POLICY\b[\s\S]*?;/gi)
    ) {
      const definition = policy[0];
      const withoutSelectedUid = definition.replaceAll(
        /\(\s*SELECT\s+auth\.uid\(\)\s*\)/gi,
        "",
      );
      if (/\bauth\.uid\(\)/i.test(withoutSelectedUid)) {
        violations.push(`${name}: direct auth.uid()`);
      }
      if (/\bauth\.role\(\)/i.test(definition)) {
        violations.push(`${name}: deprecated auth.role()`);
      }
      if (!/\bTO\s+(?:"[^"]+"|[a-z_][a-z0-9_]*)/i.test(definition)) {
        violations.push(`${name}: missing explicit TO role`);
      }
    }
  }

  assertEquals(
    violations,
    [],
    "New policies must use (select auth.uid()) and target roles with TO.",
  );
});
