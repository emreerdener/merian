import { assert, assertStringIncludes } from "@std/assert";
const migration = Deno.readTextFileSync(
  new URL(
    "../../migrations/20260920221622_add_species_discovery_search.sql",
    import.meta.url,
  ),
);
Deno.test("discovery SQL retains public eligibility, viewer projection, service-only access and bounded pages", () => {
  for (
    const contract of [
      "SECURITY INVOKER",
      "SET search_path = ''",
      "CURRENT_USER <> 'service_role'",
      "is_public_biological = TRUE",
      "public.explore_projected_post_cards(self_id)",
      "projection.projection_state::TEXT = 'community_resolved'",
      "LIMIT 21",
      "LIMIT 20",
      "FROM PUBLIC, anon, authenticated",
      "species_discovery_search",
      "species_search:",
    ]
  ) assertStringIncludes(migration, contract);
  assert(!/SECURITY DEFINER/i.test(migration));
});
