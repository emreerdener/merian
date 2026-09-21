import { assertEquals, assertThrows } from "@std/assert";
import {
  parseContext,
  parseInterpretation,
  parseSearchRequest,
} from "./contract.ts";
import { SEARCH_INSTRUCTION } from "./provider.ts";
const id = "00000000-0000-4000-8000-000000000001";
const context = {
  query: "orange black butterfly",
  group: "insects",
  media: null,
  mode: "description",
} as const;
Deno.test("discovery validates bounded question, context, filters and cursor kind", () => {
  assertEquals(
    parseSearchRequest({
      request_id: id,
      question: "Only butterflies",
      context,
      result_kind: "species",
    }).context,
    context,
  );
  for (const invalid of ["", "x".repeat(601), 1]) {
    assertThrows(() =>
      parseSearchRequest({
        request_id: id,
        question: invalid,
        result_kind: "species",
      })
    );
  }
  assertThrows(() => parseContext({ ...context, group: "nearby" }));
  assertThrows(() => parseContext({ ...context, media: "location" }));
  assertThrows(() =>
    parseSearchRequest({
      request_id: id,
      context,
      result_kind: "sightings",
      cursor: { id, rank: 1 },
    })
  );
  assertThrows(() =>
    parseSearchRequest({
      request_id: id,
      context,
      question: "new",
      result_kind: "species",
      cursor: { id, rank: 1 },
    })
  );
  assertThrows(() =>
    parseSearchRequest({
      request_id: id,
      context,
      result_kind: "species",
      cursor: { id, rank: NaN },
    })
  );
});
Deno.test("model interpretation fails closed and cannot supply results", () => {
  assertEquals(
    parseInterpretation({
      status: "results",
      context,
      message: "Orange and black butterflies",
    }).context,
    context,
  );
  assertThrows(() =>
    parseInterpretation({
      status: "results",
      context: { ...context, query: "x".repeat(241) },
      message: "ok",
    })
  );
  assertThrows(() =>
    parseInterpretation({ status: "fiction", context, message: "ok" })
  );
  for (const status of ["results", "clarification", "unsupported"]) {
    assertThrows(() => parseInterpretation({ status, context, message: "  " }));
  }
  for (
    const boundary of [
      "never species IDs",
      "Preserve every requested trait",
      "never silently discard",
      "untrusted data",
      "No tools",
    ]
  ) assertEquals(SEARCH_INSTRUCTION.includes(boundary), true);
});
Deno.test("request tolerates Swift omitted nullable keys, not unsupported enum values", () => {
  assertEquals(parseContext({ query: "monarch", mode: "name" }), {
    query: "monarch",
    group: null,
    media: null,
    mode: "name",
  });
  assertThrows(() => parseContext({ query: "", mode: "description" }));
});
