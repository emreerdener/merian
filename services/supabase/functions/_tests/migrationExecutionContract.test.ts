import { assert } from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationsDirectoryUrl = new URL("../../migrations/", import.meta.url);

function withoutSqlComments(sql: string): string {
  return sql
    .replaceAll(/\/\*[\s\S]*?\*\//g, " ")
    .replaceAll(/--[^\r\n]*/g, " ");
}

function usesPipelineIncompatibleConcurrentIndexDdl(sql: string): boolean {
  const executableSql = withoutSqlComments(sql);

  return (
    /\b(?:CREATE\s+(?:UNIQUE\s+)?INDEX|DROP\s+INDEX)\s+CONCURRENTLY\b/i
      .test(executableSql) ||
    /\bREINDEX\b[^;]*\bCONCURRENTLY\b/i.test(executableSql)
  );
}

async function migrationFileNames(): Promise<string[]> {
  const names: string[] = [];

  for await (const entry of Deno.readDir(migrationsDirectoryUrl)) {
    if (entry.isFile && entry.name.endsWith(".sql")) {
      names.push(entry.name);
    }
  }

  return names.sort();
}

Deno.test("concurrent index detector ignores comments and catches DDL", () => {
  assert(
    !usesPipelineIncompatibleConcurrentIndexDdl(
      "-- CREATE INDEX CONCURRENTLY example_idx ON example(id);\n" +
        "/* REINDEX INDEX CONCURRENTLY example_idx; */",
    ),
  );

  for (
    const sql of [
      "CREATE INDEX CONCURRENTLY example_idx ON example(id);",
      "CREATE UNIQUE INDEX CONCURRENTLY example_idx ON example(id);",
      "DROP INDEX CONCURRENTLY example_idx;",
      "REINDEX (VERBOSE) INDEX CONCURRENTLY example_idx;",
    ]
  ) {
    assert(usesPipelineIncompatibleConcurrentIndexDdl(sql), sql);
  }
});

Deno.test(
  "Supabase migrations avoid pipeline-incompatible concurrent index DDL",
  async () => {
    const violations: string[] = [];

    for (const fileName of await migrationFileNames()) {
      const sql = await Deno.readTextFile(
        new URL(fileName, migrationsDirectoryUrl),
      );

      if (usesPipelineIncompatibleConcurrentIndexDdl(sql)) {
        violations.push(fileName);
      }
    }

    assert(
      violations.length === 0,
      "Concurrent index DDL cannot run in every Supabase fresh-schema " +
        `migration pipeline. Move it to a supervised operation: ${
          violations.join(", ")
        }`,
    );
  },
);
