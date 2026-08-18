import { assertEquals, assertStringIncludes } from "@std/assert";
import {
  AUDIO_ONLY_SUBJECT_SELECTION_INSTRUCTION,
  type AudioSubjectResult,
  BLENDED_AUDIO_SUBJECT_PRECEDENCE_INSTRUCTION,
  canonicalizeStructuredHumanSubject,
  normalizeAudioOnlySubject,
} from "./audioSubjectPolicy.ts";

function result(
  overrides: Partial<AudioSubjectResult>,
): AudioSubjectResult {
  return {
    is_biological_subject: true,
    is_live_capture: true,
    scientific_name: "Turdus migratorius",
    common_name: "American Robin",
    ecology_type: "wild",
    is_invasive: false,
    sex: "cannot_determine",
    candidates: [{ scientific_name: "Turdus migratorius" }],
    ...overrides,
  };
}

Deno.test("audio policy canonicalizes human breathing to Homo sapiens", () => {
  const data = result({
    is_biological_subject: false,
    scientific_name: undefined,
    common_name: "Human Breathing",
  });

  assertEquals(normalizeAudioOnlySubject(data), "human");
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.common_name, "Human");
  assertEquals(data.scientific_name, "Homo sapiens");
  assertEquals(data.sex, "not_applicable");
  assertEquals(data.candidates, []);
  assertEquals(data.is_invasive, undefined);
});

Deno.test("private audio type repairs the reported no-taxon human breathing response", () => {
  const data = result({
    audio_subject_type: "human_only",
    is_biological_subject: true,
    scientific_name: undefined,
    common_name: "Unknown Subject",
  });

  assertEquals(normalizeAudioOnlySubject(data), "human");
  assertEquals(data.common_name, "Human");
  assertEquals(data.scientific_name, "Homo sapiens");
  assertEquals(data.audio_subject_type, undefined);
  assertEquals(data.candidates, []);
});

Deno.test("unresolved non-human sound takes precedence over conflicting Human fields", () => {
  const data = result({
    audio_subject_type: "unidentified_non_human",
    is_biological_subject: true,
    scientific_name: "Homo sapiens",
    common_name: "Human",
  });

  assertEquals(normalizeAudioOnlySubject(data), "unidentified_wildlife");
  assertEquals(data.common_name, "Unidentified Wildlife");
  assertEquals(data.scientific_name, undefined);
  assertEquals(data.audio_subject_type, undefined);
  assertEquals(data.candidates, []);
});

Deno.test("private non-biological type clears conflicting taxonomy", () => {
  const data = result({
    audio_subject_type: "no_confident_biological_source",
    is_biological_subject: true,
  });

  assertEquals(normalizeAudioOnlySubject(data), "non_biological");
  assertEquals(data.is_biological_subject, false);
  assertEquals(data.common_name, "No Wildlife Detected");
  assertEquals(data.scientific_name, undefined);
  assertEquals(data.audio_subject_type, undefined);
});

Deno.test("private identified non-human type repairs a conflicting biology boolean", () => {
  const data = result({
    audio_subject_type: "identified_non_human",
    is_biological_subject: false,
    is_live_capture: false,
  });

  assertEquals(normalizeAudioOnlySubject(data), "identified_non_human");
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.is_live_capture, true);
  assertEquals(data.scientific_name, "Turdus migratorius");
  assertEquals(data.audio_subject_type, undefined);
});

Deno.test("audio policy repairs malformed Homo sapien", () => {
  const data = result({
    scientific_name: "Homo sapien",
    common_name: "Person",
  });

  assertEquals(normalizeAudioOnlySubject(data), "human");
  assertEquals(data.common_name, "Human");
  assertEquals(data.scientific_name, "Homo sapiens");
});

Deno.test("human speech without non-human evidence maps to Homo sapiens", () => {
  const data = result({
    is_biological_subject: false,
    scientific_name: undefined,
    common_name: "Human Speech",
  });

  assertEquals(normalizeAudioOnlySubject(data), "human");
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.common_name, "Human");
  assertEquals(data.scientific_name, "Homo sapiens");
});

Deno.test("resolved bird, frog, and dog taxa win over conflicting human aliases", () => {
  const cases = [
    ["Turdus migratorius", "Human Speech"],
    ["Dryophytes cinereus", "Human Breathing"],
    ["Canis lupus familiaris", "Human"],
  ] as const;

  for (const [scientificName, conflictingCommonName] of cases) {
    const data = result({
      scientific_name: scientificName,
      common_name: conflictingCommonName,
    });

    assertEquals(normalizeAudioOnlySubject(data), "identified_non_human");
    assertEquals(data.scientific_name, scientificName);
    assertEquals(data.common_name, scientificName);
    assertEquals(data.candidates?.length, 1);
  }
});

Deno.test("resolved non-human taxon takes precedence over conflicting Human common name", () => {
  const data = result({ common_name: "Human" });

  assertEquals(normalizeAudioOnlySubject(data), "identified_non_human");
  assertEquals(data.scientific_name, "Turdus migratorius");
  assertEquals(data.common_name, "Turdus migratorius");
  assertEquals(data.candidates?.length, 1);
});

Deno.test("resolved non-human audio falls back to its taxon for unusable common names", () => {
  for (const commonName of [undefined, "Unknown Subject"]) {
    const data = result({
      audio_subject_type: "identified_non_human",
      common_name: commonName,
    });

    assertEquals(normalizeAudioOnlySubject(data), "identified_non_human");
    assertEquals(data.common_name, "Turdus migratorius");
    assertEquals(data.candidates?.length, 1);
  }
});

Deno.test("confident unresolved wildlife remains biological and clears taxonomy metadata", () => {
  const data = result({
    scientific_name: undefined,
    common_name: undefined,
  });

  assertEquals(normalizeAudioOnlySubject(data), "unidentified_wildlife");
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.common_name, "Unidentified Wildlife");
  assertEquals(data.scientific_name, undefined);
  assertEquals(data.ecology_type, undefined);
  assertEquals(data.candidates, []);
});

Deno.test("unresolved wildlife is not reclassified from human words in reasoning", () => {
  const data = {
    ...result({
      scientific_name: undefined,
      common_name: "Unidentified Wildlife",
    }),
    ai_reasoning:
      "Human speech is audible behind a confident but unresolved non-human call.",
  };

  assertEquals(normalizeAudioOnlySubject(data), "unidentified_wildlife");
  assertEquals(data.common_name, "Unidentified Wildlife");
  assertEquals(data.scientific_name, undefined);
});

Deno.test("human plus environmental noise remains Human", () => {
  const data = {
    ...result({
      is_biological_subject: true,
      scientific_name: undefined,
      common_name: "Person",
    }),
    ai_reasoning: "Human coughing with wind and handling noise.",
  };

  assertEquals(normalizeAudioOnlySubject(data), "human");
  assertEquals(data.common_name, "Human");
  assertEquals(data.scientific_name, "Homo sapiens");
});

Deno.test("environmental and indeterminate audio becomes non-biological", () => {
  const data = result({
    is_biological_subject: false,
    scientific_name: "Turdus migratorius",
    common_name: "Mechanical Hum",
  });

  assertEquals(normalizeAudioOnlySubject(data), "non_biological");
  assertEquals(data.is_biological_subject, false);
  assertEquals(data.is_live_capture, false);
  assertEquals(data.common_name, "No Wildlife Detected");
  assertEquals(data.scientific_name, undefined);
  assertEquals(data.candidates, []);
});

Deno.test("silence and mechanical-only fixtures remain non-biological", () => {
  for (const commonName of ["Silence", "Mechanical Hum"]) {
    const data = result({
      is_biological_subject: false,
      scientific_name: undefined,
      common_name: commonName,
    });

    assertEquals(normalizeAudioOnlySubject(data), "non_biological");
    assertEquals(data.common_name, "No Wildlife Detected");
    assertEquals(data.scientific_name, undefined);
    assertEquals(data.candidates, []);
  }
});

Deno.test("blended Human canonicalization does not override a resolved animal taxon", () => {
  const data = result({ common_name: "Human Speech" });

  assertEquals(canonicalizeStructuredHumanSubject(data), false);
  assertEquals(data.scientific_name, "Turdus migratorius");
});

Deno.test("audio instructions lock non-human precedence and the existing field shape", () => {
  assertStringIncludes(
    AUDIO_ONLY_SUBJECT_SELECTION_INSTRUCTION,
    "takes precedence over human speech, breathing, coughing",
  );
  assertStringIncludes(
    AUDIO_ONLY_SUBJECT_SELECTION_INSTRUCTION,
    'scientific_name="Homo sapiens"',
  );
  assertStringIncludes(
    AUDIO_ONLY_SUBJECT_SELECTION_INSTRUCTION,
    'common_name="Unidentified Wildlife"',
  );
  assertStringIncludes(
    BLENDED_AUDIO_SUBJECT_PRECEDENCE_INSTRUCTION,
    "Preserve the existing cross-modal visual-versus-audio arbitration",
  );
});

Deno.test("active and compatibility audio producers share normalization before enrichment", async () => {
  const activeSource = await Deno.readTextFile(
    new URL("../../identify-multimodal/index.ts", import.meta.url),
  );
  const compatibilitySource = await Deno.readTextFile(
    new URL("../../audio-spec/index.ts", import.meta.url),
  );

  for (const source of [activeSource, compatibilitySource]) {
    const normalization = source.indexOf(
      "normalizeAudioOnlySubject(parsedData)",
    );
    const enrichment = source.indexOf("const isIdentifiedBio", normalization);
    assertEquals(normalization >= 0, true);
    assertEquals(enrichment > normalization, true);
  }

  assertStringIncludes(
    activeSource,
    "BLENDED_AUDIO_SUBJECT_PRECEDENCE_INSTRUCTION",
  );
  assertStringIncludes(
    compatibilitySource,
    "AUDIO_ONLY_SUBJECT_SELECTION_INSTRUCTION",
  );
  for (const source of [activeSource, compatibilitySource]) {
    assertStringIncludes(source, "parseMerianAudioIdentification");
    assertStringIncludes(source, "getMerianAudioResponseSchema");
  }
  assertEquals(compatibilitySource.includes("const audioSchema"), false);
});
