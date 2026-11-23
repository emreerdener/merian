import { assertEquals } from "@std/assert";
import {
  imageFocusFingerprintFields,
  parseImageFocusRegion,
} from "./imageFocus.ts";

Deno.test("focus evidence uses strict immutable finite unit bounds", async () => {
  const rows: { name: string; focus_region: unknown; valid: boolean }[] = JSON
    .parse(
      await Deno.readTextFile(
        new URL(
          "../analysisHistory/fixtures/composition-focus-v6.json",
          import.meta.url,
        ),
      ),
    );
  for (const row of rows) {
    const parsed = parseImageFocusRegion(row.focus_region);
    assertEquals(parsed !== null, row.valid, row.name);
    if (parsed) {
      assertEquals(parsed, row.focus_region);
      assertEquals(Object.isFrozen(parsed), true);
    }
  }
  const valid = {
    x: 0.1,
    y: 0.2,
    width: 0.4,
    height: 0.5,
    source: "user_selection",
  };
  const parsed = parseImageFocusRegion(valid);
  valid.x = 0.9;
  assertEquals(parsed?.x, 0.1);
  for (const key of ["x", "y", "width", "height"]) {
    for (const value of [NaN, Infinity, -Infinity]) {
      assertEquals(
        parseImageFocusRegion({ ...valid, x: 0.1, [key]: value }),
        null,
      );
    }
  }
});

Deno.test("focus fingerprint V2 preserves binary64 across runtimes", async () => {
  const rows = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../analysisHistory/fixtures/focus-fingerprint-v2.json",
        import.meta.url,
      ),
    ),
  );
  for (const row of rows) {
    assertEquals(
      imageFocusFingerprintFields(row.focus_region),
      row.fields,
      row.name,
    );
  }
  const focus = {
    x: 0.1,
    y: 0.2,
    width: 0.3,
    height: 0.4,
    source: "user_selection",
  };
  const fields = imageFocusFingerprintFields(focus);
  assertEquals(Object.isFrozen(fields), true);
  assertEquals(
    imageFocusFingerprintFields({ ...focus, x: 0.10000000000000002 })[0] ===
      fields[0],
    false,
  );
  assertEquals(
    imageFocusFingerprintFields({ ...focus, source: "vision_objectness" })[4],
    "vision_objectness",
  );
});
