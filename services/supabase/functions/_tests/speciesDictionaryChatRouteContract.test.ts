import {
  assert,
  assertEquals,
  assertFalse,
  assertMatch,
  assertStringIncludes,
} from "@std/assert";

const routeDir = new URL("../species-dictionary-chat/", import.meta.url);

async function routeSource(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(name, routeDir));
}

Deno.test("dictionary chat is authenticated, Pro-only, and action bounded", async () => {
  const index = await routeSource("index.ts");

  assertStringIncludes(
    index,
    "Deno.serve((req: Request) =>",
  );
  assertStringIncludes(
    index,
    "export function createSpeciesDictionaryChatHttpHandler(",
  );
  assertStringIncludes(index, "options: { authenticate?: EdgeAuthenticator }");
  assertStringIncludes(index, "withEdgeHandler(");
  assertStringIncludes(index, "fieldChatDeploymentContractHeaders");
  assertStringIncludes(index, '"species-dictionary-chat"');
  assertMatch(
    index,
    /Deno\.serve\(\(req: Request\) =>\s*withEdgeHandler\(\s*req,/,
  );
  assertMatch(
    index,
    /\.\.\.options,[\s\S]*?responseHeaders: FIELD_CHAT_RESPONSE_HEADERS/,
  );
  assertStringIncludes(index, "handleSpeciesDictionaryChat(");
  assertStringIncludes(index, '"load"');
  assertStringIncludes(index, '"send"');
  assertStringIncludes(index, '"delete"');
  assertStringIncludes(index, '"feedback"');
  assertStringIncludes(index, '"suggest_prompts"');
  assertStringIncludes(index, 'requireUuid(body.species_id, "species_id")');
  assertStringIncludes(index, 'code: "species_not_available"');
  assertStringIncludes(index, 'tier.effective_tier !== "pro"');
  assertStringIncludes(index, 'code: "pro_required"');
});

Deno.test("dictionary chat reads only bounded biological dictionary fields", async () => {
  const db = await routeSource("db.ts");
  const match = db.match(/const SPECIES_CONTEXT_SELECT\s*=\s*\n?\s*"([^"]+)";/);
  assert(match, "Expected an explicit Species Dictionary context projection.");
  const selectedFields = match[1].split(",");

  assertEquals(selectedFields, [
    "id",
    "scientific_name",
    "common_names",
    "alternative_common_names",
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "wikipedia_overview",
    "hazard_type",
    "iucn_red_list_status",
    "habitat_description",
    "gbif_taxon_key",
    "group_tags",
  ]);
  for (
    const forbidden of [
      "scan_id",
      "user_id",
      "field_notes",
      "latitude",
      "longitude",
      "reference_image_url",
      "wikipedia_url",
      "attribution",
      "license",
    ]
  ) {
    assertFalse(selectedFields.includes(forbidden));
  }

  const lookalikeMatch = db.match(
    /const LOOKALIKE_SELECT\s*=\s*\n?\s*"([^"]+)";/,
  );
  assert(lookalikeMatch, "Expected an explicit lookalike context projection.");
  assertFalse(lookalikeMatch[1].includes("reference_image_url"));
  assertFalse(lookalikeMatch[1].includes("attribution"));
});

Deno.test("dictionary chat preserves strict echoes and identity-free product telemetry", async () => {
  const index = await routeSource("index.ts");
  const db = await routeSource("db.ts");

  assertStringIncludes(index, "fieldChatThreadPayload(");
  assertStringIncludes(index, "fieldChatFeedbackPayload(speciesId");
  assertStringIncludes(index, "fieldChatPromptSuggestionsPayload(");
  assertStringIncludes(db, "scan_id: row.species_dictionary_id");
  assertStringIncludes(index, 'sourceType: "species_dictionary"');
  assertFalse(index.includes("sourceId: speciesId"));
  assertMatch(
    index,
    /trackEvent\(user, "SpeciesDictionaryChatSent", \{\s*message_length:[\s\S]*?plan: tier\.plan,\s*\}\)/,
  );
  assertMatch(
    index,
    /trackEvent\(user, "SpeciesDictionaryChatFeedbackSubmitted", \{\s*rating,\s*\}\)/,
  );
});
