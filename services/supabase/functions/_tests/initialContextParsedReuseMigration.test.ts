import { assertEquals, assertMatch } from "@std/assert";

const base = new URL("../../", import.meta.url);
const read = (path: string) => Deno.readTextFile(new URL(path, base));
const lifecycle = await read(
  "migrations/20261011194522_prepare_initial_media_source_lifecycle.sql",
);
const context = await read(
  "migrations/20261011233227_prepare_initial_qualified_codecs.sql",
);
const repair = await read(
  "migrations/20261111030135_reuse_initial_context_parsed_values.sql",
);
const catalog = await read("tests/initial_qualified_codecs.sql");

function routine(sql: string, name: string): string {
  const start = sql.indexOf(name + "(");
  assertEquals(start >= 0, true);
  const end = sql.indexOf("END; $$;", start);
  assertEquals(end > start, true);
  return sql.slice(start, end + "END; $$;".length);
}

Deno.test("parsed helpers preserve original declaration semantics exactly", () => {
  const pair = "internal.valid_initial_media_assignment_pair";
  const profile = "internal.assert_initial_media_profile_matches";
  assertEquals(
    routine(repair, "internal.initial_media_assignment_pair_values"),
    routine(lifecycle, pair)
      .replace(
        pair + "(p_candidate TEXT,p_assignment TEXT)",
        "internal.initial_media_assignment_pair_values(p_candidate TEXT,p_assignment TEXT,p_candidate_value JSONB)",
      )
      .replace(
        "c:=internal.parse_initial_media_source_candidate(p_candidate);",
        "c:=p_candidate_value;",
      ),
  );
  assertEquals(
    routine(repair, "internal.assert_initial_media_profile_values"),
    routine(lifecycle, profile)
      .replace(
        profile + "(p_candidate TEXT,p_profile TEXT)",
        "internal.assert_initial_media_profile_values(p_candidate_value JSONB,p_profile_value JSONB)",
      )
      .replace(
        "plan:=internal.parse_initial_media_source_candidate(p_candidate)->'source_plan'; spec:=internal.parse_initial_media_profile(p_profile)->'spec';",
        "plan:=p_candidate_value->'source_plan'; spec:=p_profile_value->'spec';",
      ),
  );
  for (const name of [pair, profile]) {
    assertEquals(
      (routine(repair, name).match(
        /parse_initial_media_source_candidate\(p_candidate\)/g,
      ) ?? []).length,
      1,
    );
  }
  assertMatch(
    routine(repair, profile),
    /candidate_value:=internal.parse_initial_media_source_candidate\(p_candidate\);\s+profile_value:=internal.parse_initial_media_profile\(p_profile\);\s+PERFORM internal.assert_initial_media_profile_values\(candidate_value,profile_value\);/,
  );
});

Deno.test("qualified context reuses only same-invocation candidate and declared profile", () => {
  const name = "internal.initial_qualified_context";
  const expected = routine(context, name)
    .replace(
      "DECLARE a JSONB:=",
      "DECLARE pair_text TEXT; candidate_value JSONB; a JSONB:=",
    )
    .replace(
      " IF NOT internal.valid_initial_media_assignment_pair(p_candidate,internal.initial_canonical(jsonb_set(a-'handoff','{version}','2'))) THEN",
      " pair_text:=internal.initial_canonical(jsonb_set(a-'handoff','{version}','2'));\n candidate_value:=internal.parse_initial_media_source_candidate(p_candidate);\n IF NOT internal.initial_media_assignment_pair_values(p_candidate,pair_text,candidate_value) THEN",
    )
    .replace(
      " PERFORM internal.assert_initial_media_profile_matches(p_candidate,p_preparation);",
      " PERFORM internal.assert_initial_media_profile_values(candidate_value,profile);",
    );
  assertEquals(routine(repair, name), expected);
  assertEquals(
    [...repair.matchAll(/CREATE(?: OR REPLACE)? FUNCTION (\S+)\(/g)].map((m) =>
      m[1]
    ),
    [
      "internal.initial_media_assignment_pair_values",
      "internal.assert_initial_media_profile_values",
      "internal.valid_initial_media_assignment_pair",
      "internal.assert_initial_media_profile_matches",
      name,
    ],
  );
  assertEquals(
    /\b(?:GRANT|ALTER|DROP|SECURITY DEFINER|set_config|current_setting)\b/i
      .test(repair),
    false,
  );
  assertMatch(
    repair,
    /REVOKE ALL ON FUNCTION internal.initial_media_assignment_pair_values\(TEXT,TEXT,JSONB\),internal.assert_initial_media_profile_values\(JSONB,JSONB\) FROM PUBLIC,anon,authenticated,service_role;/,
  );
});

Deno.test("differential oracles retain independent original pair and profile validation", () => {
  for (
    const [original, oracle] of [
      [
        "internal.valid_initial_media_assignment_pair",
        "pg_temp.original_media_assignment_pair",
      ],
      [
        "internal.assert_initial_media_profile_matches",
        "pg_temp.original_media_profile_matches",
      ],
    ]
  ) {
    assertEquals(
      routine(catalog, oracle).replace(oracle, original),
      routine(lifecycle, original),
    );
  }
  assertEquals(
    routine(catalog, "pg_temp.original_qualified_context")
      .replace(
        "pg_temp.original_qualified_context",
        "internal.initial_qualified_context",
      )
      .replace(
        "pg_temp.original_media_assignment_pair",
        "internal.valid_initial_media_assignment_pair",
      )
      .replace(
        "pg_temp.original_media_profile_matches",
        "internal.assert_initial_media_profile_matches",
      ),
    routine(context, "internal.initial_qualified_context"),
  );
  assertMatch(catalog, /original \? 'sqlstate' AND proposed \? 'sqlstate'/);
  assertMatch(catalog, /jsonb_typeof\(original->'value'\)='object'/);
  assertMatch(catalog, /direct entry denial/);
  assertMatch(catalog, /multiple invalid denied/);
});
