import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migrationUrl = new URL(
  "../../migrations/20260729044500_grant_atomic_explore_service_privileges.sql",
  import.meta.url,
);

function compact(source: string): string {
  return source.replaceAll(/--.*$/gm, "").replaceAll(/\s+/g, " ").trim();
}

Deno.test("atomic Explore transactions have an explicit invoker privilege allowlist", async () => {
  const sql = compact(await Deno.readTextFile(migrationUrl));
  const expectedGrants = [
    "GRANT SELECT, UPDATE ON TABLE public.scans TO service_role;",
    "GRANT SELECT ON TABLE public.taxon_nodes, public.species_dictionary TO service_role;",
    "GRANT SELECT, INSERT, UPDATE ON TABLE public.explore_posts, public.explore_community_requests TO service_role;",
    "GRANT SELECT, INSERT, DELETE ON TABLE public.explore_post_media, public.explore_post_hashtags TO service_role;",
    "GRANT SELECT, UPDATE ON TABLE public.explore_identifications TO service_role;",
    "GRANT SELECT, DELETE ON TABLE public.community_consensus_jobs TO service_role;",
  ];

  for (
    const fragment of [
      "SET lock_timeout = '10s'",
      "SET statement_timeout = '2min'",
      "RESET statement_timeout",
      "RESET lock_timeout",
    ]
  ) {
    assertStringIncludes(sql, fragment);
  }

  for (
    const forbidden of [
      " TO anon",
      " TO authenticated",
      " TO PUBLIC",
      "GRANT ALL",
      "TRUNCATE",
      "REFERENCES",
      "TRIGGER",
      "MAINTAIN",
    ]
  ) {
    assert(
      !sql.includes(forbidden),
      `Atomic invoker privilege migration contains forbidden grant: ${forbidden}`,
    );
  }

  assertEquals(
    sql.match(/GRANT [^;]+ TO service_role;/g) ?? [],
    expectedGrants,
    "Atomic invoker privilege migration must contain only the reviewed grants.",
  );
});
