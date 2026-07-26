import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  sanitizeLifeStage,
  sanitizeReproductiveCondition,
  sanitizeSex,
} from "./context.ts";
import type { MerianIdentification } from "./types.ts";

Deno.test("categorical sanitizers normalize null without advertising nullable output", () => {
  const lifeStage: Exclude<
    MerianIdentification["life_stage"],
    null
  > = sanitizeLifeStage(null);
  const reproductiveCondition: Exclude<
    MerianIdentification["reproductive_condition"],
    null
  > = sanitizeReproductiveCondition(null);
  const sex: Exclude<
    MerianIdentification["sex"],
    null
  > = sanitizeSex(null);

  assertEquals(lifeStage, undefined);
  assertEquals(reproductiveCondition, undefined);
  assertEquals(sex, undefined);
});

Deno.test("categorical sanitizers preserve known values and replace unknown values", () => {
  assertEquals(sanitizeLifeStage("adult"), "adult");
  assertEquals(sanitizeLifeStage("fledgling"), "unknown");
  assertEquals(sanitizeReproductiveCondition("flowering"), "flowering");
  assertEquals(
    sanitizeReproductiveCondition("brooding"),
    "not_applicable",
  );
  assertEquals(sanitizeSex("female"), "female");
  assertEquals(sanitizeSex("worker"), "cannot_determine");
});
