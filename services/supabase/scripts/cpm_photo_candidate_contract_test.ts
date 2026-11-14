import { historicalI6Schema } from "../functions/_shared/initialAnalysis/fixtures/historicalSchema.ts";
import { assertEquals } from "@std/assert";
import candidateSchema from "../functions/_shared/initialAnalysis/cpm-photo-candidate-schema-v1.json" with {
  type: "json",
};
import contentSchema from "../functions/_shared/initialAnalysis/cpm-photo-content-schema-v1.json" with {
  type: "json",
};
import assignmentSchema from "../functions/_shared/initialAnalysis/cpm-photo-assignment-schema-v1.json" with {
  type: "json",
};
import recoverySchema from "../functions/_shared/initialAnalysis/cpm-photo-recovery-schema-v1.json" with {
  type: "json",
};
import assignmentVector from "../functions/_shared/initialAnalysis/fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};
import sourceSchema from "../functions/_shared/initialAnalysis/media-source-candidate-schema-v2.json" with {
  type: "json",
};
import candidateVector from "../functions/_shared/initialAnalysis/fixtures/cpm-photo-candidate-v1.json" with {
  type: "json",
};
import contentVector from "../functions/_shared/initialAnalysis/fixtures/cpm-photo-content-v1.json" with {
  type: "json",
};

const migration = new URL(
  "../migrations/20261027222458_prepare_initial_cpm_photo_allocation.sql",
  import.meta.url,
);
const catalog = new URL(
  "../tests/initial_cpm_photo_allocation_contract.sql",
  import.meta.url,
);

Deno.test("CPM SQL embeds the authoritative content and candidate schemas exactly", async () => {
  const source = await Deno.readTextFile(migration);
  for (
    const [kind, expected] of [
      ["content", contentSchema],
      ["candidate", candidateSchema],
      ["assignment", assignmentSchema],
      ["recovery", recoverySchema],
    ] as const
  ) {
    const pattern = new RegExp(
      `CREATE FUNCTION internal\\.initial_cpm_photo_${kind}_schema_v1\\(\\)[\\s\\S]*?SELECT \\$schema\\$([\\s\\S]*?)\\$schema\\$::JSONB;`,
      "g",
    );
    const matches = [...source.matchAll(pattern)];
    assertEquals(matches.length, 1);
    assertEquals(JSON.parse(matches[0][1]), historicalI6Schema(expected));
  }
});

Deno.test("CPM SQL and Deno exercise the same independent golden vectors", async () => {
  const source = await Deno.readTextFile(catalog);
  for (
    const [kind, expected] of [
      ["content", contentVector],
      ["candidate", candidateVector],
      ["assignment", assignmentVector],
    ] as const
  ) {
    const pattern = new RegExp(
      `\\$${kind}_vector\\$([\\s\\S]*?)\\$${kind}_vector\\$::JSONB`,
      "g",
    );
    const matches = [...source.matchAll(pattern)];
    assertEquals(matches.length, 1);
    assertEquals(JSON.parse(matches[0][1]), historicalI6Schema(expected));
  }
});

Deno.test("CPM retains existing saved protocol and processor-expectation semantics", () => {
  assertEquals(
    candidateSchema.properties.admission,
    sourceSchema.properties.source_plan.properties.admission,
  );
});

Deno.test("CPM allocation lifecycle tests start from the exact candidate golden envelope", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../tests/initial_cpm_photo_intents.sql",
      import.meta.url,
    ),
  );
  const matches = [
    ...source.matchAll(/\$fixture\$([\s\S]*?)\$fixture\$::JSONB/g),
  ];
  assertEquals(matches.length, 1);
  assertEquals(JSON.parse(matches[0][1]), candidateVector.candidate);
});
