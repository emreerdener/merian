import { assert } from "https://deno.land/std@0.224.0/testing/asserts.ts";

const migrationsDirectoryUrl = new URL("../../migrations/", import.meta.url);

interface SqlLexicalView {
  executableSql: string;
  stringLiterals: Array<{
    start: number;
    end: number;
    value: string;
  }>;
}

function sqlLexicalView(sql: string): SqlLexicalView {
  const executableCharacters = sql.split("");
  const stringLiterals: SqlLexicalView["stringLiterals"] = [];

  for (let index = 0; index < sql.length;) {
    if (sql.startsWith("--", index)) {
      const end = sql.indexOf("\n", index + 2);
      const commentEnd = end === -1 ? sql.length : end;
      executableCharacters.fill(" ", index, commentEnd);
      index = commentEnd;
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
      executableCharacters.fill(" ", start, index);
      continue;
    }

    if (sql[index] === "'") {
      const start = index;
      let value = "";
      index += 1;
      while (index < sql.length) {
        if (sql[index] === "'" && sql[index + 1] === "'") {
          value += "'";
          index += 2;
        } else if (sql[index] === "'") {
          index += 1;
          break;
        } else {
          value += sql[index];
          index += 1;
        }
      }
      executableCharacters.fill(" ", start, index);
      stringLiterals.push({ start, end: index, value });
      continue;
    }

    index += 1;
  }

  return {
    executableSql: executableCharacters.join(""),
    stringLiterals,
  };
}

function containsConcurrentIndexDdl(sql: string): boolean {
  return (
    /\b(?:CREATE\s+(?:UNIQUE\s+)?INDEX|DROP\s+INDEX)\s+CONCURRENTLY\b/i
      .test(sql) ||
    /\bREINDEX\b[^;]*\bCONCURRENTLY\b/i.test(sql)
  );
}

function usesPipelineIncompatibleConcurrentIndexDdl(sql: string): boolean {
  const { executableSql, stringLiterals } = sqlLexicalView(sql);

  if (containsConcurrentIndexDdl(executableSql)) return true;

  const statementBoundaries = [0];
  for (const match of executableSql.matchAll(/;/g)) {
    statementBoundaries.push((match.index ?? 0) + 1);
  }
  statementBoundaries.push(executableSql.length + 1);

  return statementBoundaries.slice(0, -1).some((statementStart, offset) => {
    const statementEnd = statementBoundaries[offset + 1];
    const statement = executableSql.slice(statementStart, statementEnd);
    if (!/\bEXECUTE\b/i.test(statement)) return false;

    const dynamicSql = stringLiterals
      .filter(({ start }) => start >= statementStart && start < statementEnd)
      .map(({ value }) => value)
      .join(" ");
    return containsConcurrentIndexDdl(dynamicSql);
  });
}

function usesSchemaQualifiedSubstringKeywordSyntax(sql: string): boolean {
  const { executableSql } = sqlLexicalView(sql);
  const invocationPattern = /\b(?:[a-z_][a-z0-9_$]*\s*\.\s*)+substring\s*\(/gi;

  for (const invocation of executableSql.matchAll(invocationPattern)) {
    const openParenthesis = (invocation.index ?? 0) + invocation[0].length - 1;
    let depth = 1;

    for (
      let index = openParenthesis + 1;
      index < executableSql.length && depth > 0;
      index += 1
    ) {
      const character = executableSql[index];
      if (character === "(") {
        depth += 1;
        continue;
      }
      if (character === ")") {
        depth -= 1;
        continue;
      }
      if (depth !== 1) continue;

      // A top-level comma selects PostgreSQL's ordinary function invocation,
      // which is valid with a schema-qualified name. SQL's FROM/FOR/SIMILAR
      // keyword forms are parser productions for the unqualified SUBSTRING
      // expression and cannot follow pg_catalog.SUBSTRING(.
      if (character === ",") break;
      const keyword = executableSql.slice(index).match(
        /^(?:FROM|FOR|SIMILAR)\b/i,
      );
      if (keyword) return true;
    }
  }

  return false;
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
        "/* REINDEX INDEX CONCURRENTLY example_idx; */\n" +
        "RAISE EXCEPTION 'repair required' USING " +
        "HINT = 'Run CREATE INDEX CONCURRENTLY example_idx';",
    ),
  );

  for (
    const sql of [
      "CREATE INDEX CONCURRENTLY example_idx ON example(id);",
      "CREATE UNIQUE INDEX CONCURRENTLY example_idx ON example(id);",
      "DROP INDEX CONCURRENTLY example_idx;",
      "REINDEX (VERBOSE) INDEX CONCURRENTLY example_idx;",
      "EXECUTE 'CREATE INDEX CONCURRENTLY example_idx ON example(id)';",
      "EXECUTE format('DROP INDEX CONCURRENTLY %I', index_name);",
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

Deno.test(
  "schema-qualified substring calls use ordinary comma invocation syntax",
  async () => {
    assert(
      usesSchemaQualifiedSubstringKeywordSyntax(
        "SELECT pg_catalog.SUBSTRING(value FROM '^prefix/(.*)$');",
      ),
    );
    assert(
      usesSchemaQualifiedSubstringKeywordSyntax(
        "SELECT internal.SUBSTRING(COALESCE(value, '') FOR 4);",
      ),
    );
    assert(
      usesSchemaQualifiedSubstringKeywordSyntax(
        "SELECT pg_catalog . SUBSTRING(value SIMILAR pattern ESCAPE '#');",
      ),
    );
    assert(
      !usesSchemaQualifiedSubstringKeywordSyntax(
        "SELECT SUBSTRING(value FROM '^prefix/(.*)$');",
      ),
    );
    assert(
      !usesSchemaQualifiedSubstringKeywordSyntax(
        "SELECT pg_catalog.SUBSTRING(value, '^prefix/(.*)$');",
      ),
    );
    assert(
      !usesSchemaQualifiedSubstringKeywordSyntax(
        "-- SELECT pg_catalog.SUBSTRING(value FROM pattern);\n" +
          "SELECT 'pg_catalog.SUBSTRING(value FOR 4)';",
      ),
    );

    const violations: string[] = [];
    for (const fileName of await migrationFileNames()) {
      const sql = await Deno.readTextFile(
        new URL(fileName, migrationsDirectoryUrl),
      );
      if (usesSchemaQualifiedSubstringKeywordSyntax(sql)) {
        violations.push(fileName);
      }
    }

    assert(
      violations.length === 0,
      "Schema-qualified SUBSTRING calls must use ordinary comma-separated " +
        `arguments; SQL keyword syntax fails fresh catalog parsing: ${
          violations.join(", ")
        }`,
    );
  },
);
