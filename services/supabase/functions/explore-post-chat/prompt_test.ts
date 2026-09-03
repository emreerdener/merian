import { assertEquals, assertFalse, assertStringIncludes } from "@std/assert";
import {
  buildExplorePostContextBlock,
  buildSystemInstruction,
} from "./prompt.ts";
import type { ExplorePostChatContext } from "./types.ts";

const context: ExplorePostChatContext = {
  post: {
    post_id: "00000000-0000-4000-8000-000000000001",
    scan_id: "private-scan-id",
    hero_image_url: "https://private.example/media.jpg",
    shared_at: "2026-07-21T12:00:00Z",
    author_user_id: "00000000-0000-4000-8000-000000000002",
    author_name: "Observer",
    species_common_name: "Monarch",
    species_scientific_name: "Danaus plexippus",
    public_location_label: "Illinois",
    location_sharing: "obscured",
    time_of_day: "afternoon",
    current_month: 7,
    weather_condition: "clear",
    weather_temperature_f: 78,
    like_count: 3,
    comment_count: 1,
    viewer_has_liked: false,
    is_owned_by_viewer: false,
  },
  detail: {
    post_id: "00000000-0000-4000-8000-000000000001",
    field_notes: "Observed feeding on milkweed.",
    location_sharing: "obscured",
    species_dictionary_id: "00000000-0000-4000-8000-000000000003",
    taxonomy_kingdom: "Animalia",
    taxonomy_phylum: "Arthropoda",
    taxonomy_class: "Insecta",
    taxonomy_order: "Lepidoptera",
    taxonomy_family: "Nymphalidae",
    taxonomy_genus: "Danaus",
    ai_reasoning: "Orange wings with black venation.",
    habitat_description: "Open fields and gardens.",
    iucn_red_list_status: "Least Concern",
    hazard_type: "none",
    wikipedia_overview: "A migratory milkweed butterfly.",
    similar_species: [{
      scientific_name: "Limenitis archippus",
      common_name: "Viceroy",
      reference_image_url: "https://private.example/lookalike.jpg",
      iucn_red_list_status: null,
      reason: "Similar orange-and-black pattern.",
      visual_traits: ["Black line across the hindwing"],
    }],
  },
};

Deno.test("Explore chat context contains public educational fields", () => {
  const block = buildExplorePostContextBlock(context);
  assertEquals(block.includes("Danaus plexippus"), true);
  assertEquals(block.includes("Observed feeding on milkweed"), true);
  assertEquals(block.includes("Illinois"), true);
});

Deno.test("Explore chat prompt excludes media and private scan identifiers", () => {
  const prompt = buildSystemInstruction(context);
  assertFalse(prompt.includes(context.post.hero_image_url));
  assertFalse(prompt.includes("https://private.example/lookalike.jpg"));
  assertFalse(prompt.includes(context.post.scan_id));
  assertFalse(prompt.includes(context.post.author_user_id));
  assertFalse(prompt.includes("private-scan-id"));
});

Deno.test("Explore chat permits species knowledge without public reference prose", () => {
  const prompt = buildSystemInstruction({
    ...context,
    detail: {
      ...context.detail,
      wikipedia_overview: null,
      habitat_description: null,
    },
  });
  assertStringIncludes(prompt, "Overview: Unavailable");
  assertStringIncludes(
    prompt,
    "using well-established species knowledge even when that detail is absent from the supplied context",
  );
  assertStringIncludes(
    prompt,
    "Never present general species knowledge as a trait observed in this individual",
  );
  assertStringIncludes(prompt, "You cannot inspect the post's photo");
  assertStringIncludes(prompt, "Do not provide edible certainty");
  assertStringIncludes(prompt, "You have no live search or source retrieval");
  assertFalse(prompt.includes("using only the public"));
});
