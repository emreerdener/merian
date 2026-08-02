import { assertEquals } from "@std/assert";
import {
  buildGroupTagsProvenanceRows,
  buildLookalikesProvenanceRows,
  buildSpeciesDictionaryProvenanceRows,
  defaultRefreshAfter,
  speciesContentProvenanceRow,
} from "./speciesContentProvenance.ts";

const REFRESHED_AT = new Date("2026-05-13T00:00:00.000Z");

Deno.test("species content provenance - builds rows for dictionary field sources", () => {
  const rows = buildSpeciesDictionaryProvenanceRows(
    "species-id",
    {
      common_names: { en: "Monarch Butterfly" },
      alternative_common_names: ["Monarch", "Common Tiger"],
      kingdom: "Animalia",
      order: "Lepidoptera",
      wikipedia_url: "https://en.wikipedia.org/wiki/Monarch_butterfly",
      wikipedia_overview: "A butterfly overview.",
      habitat_description: "Open meadows and milkweed.",
      gbif_taxon_key: 5139790,
      reference_image_url:
        "https://upload.wikimedia.org/monarch.jpg,https://gbif.example/photo.jpg",
    },
    REFRESHED_AT,
  );

  assertEquals(
    rows.map((row) => [row.content_key, row.source]),
    [
      ["common_names", "model_enrichment"],
      ["alternative_common_names", "gbif"],
      ["taxonomy", "model_enrichment"],
      ["wikipedia_url", "wikipedia"],
      ["wikipedia_overview", "wikipedia"],
      ["habitat_description", "model_enrichment"],
      ["gbif_taxon_key", "gbif"],
      ["reference_images", "mixed"],
    ],
  );
  assertEquals(rows[0].last_refreshed_at, "2026-05-13T00:00:00.000Z");
  assertEquals(rows[7].metadata, { url_count: 2 });
});

Deno.test("species content provenance - refresh windows distinguish source quality", () => {
  assertEquals(
    speciesContentProvenanceRow(
      "species-id",
      "wikipedia_overview",
      "wikipedia",
      {
        refreshedAt: REFRESHED_AT,
      },
    ).refresh_after,
    "2026-11-09T00:00:00.000Z",
  );
  assertEquals(
    speciesContentProvenanceRow(
      "species-id",
      "habitat_description",
      "model_enrichment",
      {
        refreshedAt: REFRESHED_AT,
      },
    ).refresh_after,
    "2026-08-11T00:00:00.000Z",
  );
  assertEquals(
    speciesContentProvenanceRow(
      "species-id",
      "common_names",
      "manual_curation",
      {
        refreshedAt: REFRESHED_AT,
      },
    ).refresh_after,
    null,
  );
  assertEquals(
    defaultRefreshAfter("system_backfill", "taxonomy", REFRESHED_AT)
      ?.toISOString(),
    "2026-06-12T00:00:00.000Z",
  );
});

Deno.test("species content provenance - group tags and lookalikes rows are explicit", () => {
  assertEquals(
    buildGroupTagsProvenanceRows(
      "species-id",
      ["animal", "insect"],
      REFRESHED_AT,
    ),
    [
      {
        species_id: "species-id",
        content_key: "group_tags",
        source: "model_enrichment",
        source_detail: "group tag generation",
        confidence: 0.8,
        metadata: { count: 2 },
        last_refreshed_at: "2026-05-13T00:00:00.000Z",
        refresh_after: "2026-08-11T00:00:00.000Z",
      },
    ],
  );

  assertEquals(
    buildLookalikesProvenanceRows(
      "species-id",
      3,
      "model_enrichment",
      REFRESHED_AT,
    )[0].metadata,
    { count: 3 },
  );
  assertEquals(buildLookalikesProvenanceRows("species-id", 0), []);
});
