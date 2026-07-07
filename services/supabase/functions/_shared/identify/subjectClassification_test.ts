import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { normalizeProcessedMaterialSubject } from "./subjectClassification.ts";
import type { MerianIdentification } from "./types.ts";

function identification(
  overrides: Partial<MerianIdentification>,
): MerianIdentification {
  return {
    is_biological_subject: true,
    is_live_capture: true,
    scientific_name: "Ovis aries",
    common_name: "Domestic Sheep",
    confidence_score: 0.82,
    ai_reasoning: "The subject appears biological.",
    extracted_visual_traits: ["visible organism"],
    candidates: [
      {
        scientific_name: "Capra hircus",
        confidence_score: 0.48,
        distinguishing_feature: "horn shape differs",
      },
    ],
    ...overrides,
  };
}

Deno.test("processed material normalization demotes a wool kilim rug false positive", () => {
  const data = identification({
    common_name: "Wool Kilim Rug",
    scientific_name: "Ovis aries",
    ai_reasoning:
      "The subject is a man-made textile, likely a kilim rug. While inanimate, it is composed of processed wool from domestic sheep.",
    extracted_visual_traits: [
      "flat-woven texture",
      "geometric pattern",
      "fringed edge",
    ],
    ecology_type: "domesticated",
    is_invasive: false,
    life_stage: "adult",
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, true);
  assertEquals(result.previousScientificName, "Ovis aries");
  assertEquals(data.is_biological_subject, false);
  assertEquals(data.is_live_capture, false);
  assertEquals(data.scientific_name, undefined);
  assertEquals(data.common_name, "Wool Kilim Rug");
  assertEquals(data.candidates, null);
  assertEquals(data.ecology_type, undefined);
  assertEquals(data.life_stage, undefined);
});

Deno.test("processed material normalization strips candidates from existing non-biological results", () => {
  const data = identification({
    is_biological_subject: false,
    common_name: "Leather Jacket",
    scientific_name: "Bos taurus",
    candidates: [
      {
        scientific_name: "Ovis aries",
        confidence_score: 0.44,
        distinguishing_feature: "fiber texture differs",
      },
    ],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, false);
  assertEquals(data.scientific_name, undefined);
  assertEquals(data.candidates, null);
});

Deno.test("processed material normalization preserves a living sheep observation", () => {
  const data = identification({
    common_name: "Domestic Sheep",
    scientific_name: "Ovis aries",
    ai_reasoning:
      "A live sheep is standing in a field with visible fleece, legs, head, and ears.",
    extracted_visual_traits: ["fleece", "standing posture", "visible head"],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, false);
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.scientific_name, "Ovis aries");
});

Deno.test("processed material normalization preserves biological names that contain material words", () => {
  const data = identification({
    common_name: "Paper Birch",
    scientific_name: "Betula papyrifera",
    ai_reasoning:
      "A living birch tree is present with peeling white bark, visible branches, and leaves.",
    extracted_visual_traits: ["peeling white bark", "branches", "green leaves"],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, false);
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.scientific_name, "Betula papyrifera");
});

Deno.test("processed material normalization preserves names that only contain artifact substrings", () => {
  const data = identification({
    common_name: "Tomato",
    scientific_name: "Solanum lycopersicum",
    ai_reasoning:
      "A living tomato plant is present with leaves, stems, and visible fruit.",
    extracted_visual_traits: ["compound leaves", "green stems", "red fruit"],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, false);
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.scientific_name, "Solanum lycopersicum");
});

Deno.test("processed material normalization preserves species with artifact words in common names", () => {
  const data = identification({
    common_name: "Varied Carpet Beetle",
    scientific_name: "Anthrenus verbasci",
    ai_reasoning:
      "A small beetle with mottled wing covers and visible antennae is the primary subject.",
    extracted_visual_traits: [
      "mottled wing covers",
      "oval beetle body",
      "antennae",
    ],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, false);
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.scientific_name, "Anthrenus verbasci");
});

Deno.test("processed material normalization demotes manufactured paper with source species", () => {
  const data = identification({
    common_name: "Paper Sheet",
    scientific_name: "Picea abies",
    ai_reasoning:
      "The subject is manufactured paper, an inanimate processed wood-pulp material.",
    extracted_visual_traits: ["flat sheet", "processed fiber", "no organism"],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, true);
  assertEquals(data.is_biological_subject, false);
  assertEquals(data.scientific_name, undefined);
});

Deno.test("processed material normalization preserves a pressed plant specimen", () => {
  const data = identification({
    common_name: "Pressed Plant Specimen",
    scientific_name: "Quercus alba",
    ai_reasoning:
      "The subject is a pressed plant specimen with visible leaves and preserved botanical structures.",
    extracted_visual_traits: [
      "pressed plant",
      "visible leaf shape",
      "preserved specimen",
    ],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, false);
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.scientific_name, "Quercus alba");
});

Deno.test("processed material normalization preserves a woodpecker perched on a wooden fence", () => {
  const data = identification({
    common_name: "Downy Woodpecker",
    scientific_name: "Dryobates pubescens",
    ai_reasoning:
      "The bird is perched on a wooden fence, but the primary subject is the living woodpecker.",
    extracted_visual_traits: [
      "black-and-white plumage",
      "short bill",
      "wooden fence perch",
    ],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, false);
  assertEquals(data.is_biological_subject, true);
  assertEquals(data.scientific_name, "Dryobates pubescens");
});

Deno.test("processed material normalization preserves non-biological geological names", () => {
  const data = identification({
    is_biological_subject: false,
    common_name: "Quartz",
    scientific_name: "SiO2",
    ai_reasoning: "The subject is an identifiable mineral specimen.",
    candidates: [
      {
        scientific_name: "Calcite",
        confidence_score: 0.31,
        distinguishing_feature: "different crystal habit",
      },
    ],
  });

  const result = normalizeProcessedMaterialSubject(data);

  assertEquals(result.demoted, false);
  assertEquals(data.scientific_name, "SiO2");
  assertEquals(data.candidates, null);
});
