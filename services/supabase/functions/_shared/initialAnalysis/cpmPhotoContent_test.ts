import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import { encodeBase64 } from "../encoding.ts";
import { initialCanonicalText } from "./canonical.ts";
import {
  initialCpmPhotoContentDigest,
  parseInitialCpmPhotoContent,
  validateInitialCpmPhotoContent,
} from "./cpmPhotoContent.ts";
import fixture from "./fixtures/cpm-photo-content-v1.json" with {
  type: "json",
};

const make = () => structuredClone(fixture.content);
const encoded = (text: string) => encodeBase64(new TextEncoder().encode(text));
const reject = (value: unknown) =>
  assertThrows(
    () => validateInitialCpmPhotoContent(value),
    Error,
    "initial_analysis_input_invalid",
  );
const uid = (last: number) =>
  `00000000-0000-4000-8000-${last.toString(16).padStart(12, "0")}`;
function two() {
  const value = make(), photo = structuredClone(value.photos[0]);
  photo.ordinal = 1;
  [photo.source, photo.ai, photo.display].forEach((role, index) =>
    role.reference_id = uid(6 + index)
  );
  value.photos.push(photo);
  return value;
}
const bits = (value: number) => {
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, value, false);
  return view.getBigUint64(0, false).toString(16).padStart(16, "0");
};

Deno.test("CPM photo declaration matches independent canonical/digest vector", async () => {
  assertEquals(validateInitialCpmPhotoContent(make()), fixture.canonical);
  assertEquals(
    parseInitialCpmPhotoContent(fixture.canonical),
    fixture.canonical,
  );
  assertEquals(await initialCpmPhotoContentDigest(make()), fixture.digest);
});

Deno.test("CPM snapshot cannot change while digest awaits", async () => {
  const value = make(), pending = initialCpmPhotoContentDigest(value);
  value.contexts[0].text_utf8_base64 = encoded("changed");
  value.photos.reverse();
  value.photos[0].source.sha256 = "b".repeat(64);
  assertEquals(await pending, fixture.digest);
});

Deno.test("CPM preserves logical multiplicity, cohort order and context order", async () => {
  const value = two();
  validateInitialCpmPhotoContent(value); // Identical hashes are separate logical references.
  const digest = await initialCpmPhotoContentDigest(value);
  value.photos.reverse();
  reject(value);
  value.photos.forEach((photo, i) => photo.ordinal = i);
  assertNotEquals(await initialCpmPhotoContentDigest(value), digest);
  value.photos[1].source.reference_id = value.photos[0].source.reference_id;
  reject(value);
  const ordered = make();
  ordered.contexts = [{ text_utf8_base64: encoded("a") }, {
    text_utf8_base64: encoded("b"),
  }];
  const original = await initialCpmPhotoContentDigest(ordered);
  ordered.contexts.reverse();
  assertNotEquals(await initialCpmPhotoContentDigest(ordered), original);
});

Deno.test("CPM exact text preserves NUL, BOM, whitespace and normalization", async () => {
  const digests = new Set<string>();
  for (
    const text of ["", " ", "a\u0000b", "\ufeffa", "a", "é", "e\u0301", "🦭"]
  ) {
    const value = make();
    value.contexts = [{ text_utf8_base64: encoded(text) }];
    const result = JSON.parse(validateInitialCpmPhotoContent(value));
    assertEquals(result.contexts, value.contexts);
    digests.add(await initialCpmPhotoContentDigest(value));
  }
  assertEquals(digests.size, 8);
});

Deno.test("CPM rejects malformed base64 and UTF8 before accepting text", () => {
  for (
    const text of [
      "YQ",
      "YQ=",
      "YQ===",
      "YR==",
      "YQ==\n",
      "-w==",
      "/w==",
      "wK8=",
      "7aCA",
    ]
  ) {
    const value = make();
    value.contexts[0].text_utf8_base64 = text;
    reject(value);
  }
});

Deno.test("CPM enforces native context scalar, UTF16 and aggregate bounds", () => {
  for (const text of ["a".repeat(8192), "🦭".repeat(8192)]) {
    const value = make();
    value.contexts = [{ text_utf8_base64: encoded(text) }];
    validateInitialCpmPhotoContent(value);
    value.contexts[0].text_utf8_base64 = encoded(text + "a");
    reject(value);
  }
  const value = make();
  value.contexts = Array.from(
    { length: 4 },
    () => ({ text_utf8_base64: encoded("a".repeat(8000)) }),
  );
  validateInitialCpmPhotoContent(value);
  value.contexts.push({ text_utf8_base64: encoded("a") });
  reject(value);
  value.contexts = Array.from({ length: 64 }, () => ({ text_utf8_base64: "" }));
  validateInitialCpmPhotoContent(value);
  value.contexts.push({ text_utf8_base64: "" });
  reject(value);
});

Deno.test("CPM enforces role ceilings and rejects empty or oversized cohorts", () => {
  const value = two();
  value.photos.forEach((photo) => {
    photo.source.byte_count = 32 * 1048576;
    photo.display.byte_count = 4 * 1048576;
    photo.ai.byte_count = 5 * 1048576 / 2;
  });
  validateInitialCpmPhotoContent(value);
  for (const role of ["source", "ai", "display"] as const) {
    const invalid = structuredClone(value);
    invalid.photos[0][role].byte_count++;
    reject(invalid);
    invalid.photos[0][role].byte_count = 0;
    reject(invalid);
  }
  value.photos.push(value.photos[0]);
  reject(value);
  value.photos = [];
  reject(value);
});

Deno.test("CPM binary64 preserves signed zero and validates recipe combinations", async () => {
  const value = make(), negative = await initialCpmPhotoContentDigest(value);
  value.photos[0].recipe.offset_x_bits = bits(0);
  assertNotEquals(await initialCpmPhotoContentDigest(value), negative);
  for (
    const bit of [
      bits(NaN),
      bits(Infinity),
      bits(-Infinity),
      "000000000000000",
      "3FF0000000000000",
    ]
  ) {
    const invalid = make();
    invalid.photos[0].recipe.scale_bits = bit;
    reject(invalid);
  }
  for (
    const patch of [
      { scale_bits: bits(0.5) },
      { offset_y_bits: bits(1) },
      { quarter_turns: 1 },
      { camera_vertical_center_bits: bits(0.5) },
      { crop_display_size_bits: bits(-0) },
      { format: "nativeCameraStillV1" },
      { format: "nativeCameraStillV1", camera_vertical_center_bits: bits(1.1) },
      {
        format: "nativeCameraStillV1",
        camera_vertical_center_bits: bits(0.5),
        crop_display_size_bits: bits(1),
      },
    ]
  ) {
    reject({
      ...make(),
      photos: [{
        ...make().photos[0],
        recipe: { ...make().photos[0].recipe, ...patch },
      }],
    });
  }
  for (
    const patch of [
      {
        crop_display_size_bits: bits(1),
        scale_bits: bits(2),
        quarter_turns: 3,
        offset_x_bits: bits(-1),
      },
      { format: "nativeCameraStillV1", camera_vertical_center_bits: bits(0.5) },
    ]
  ) {
    validateInitialCpmPhotoContent({
      ...make(),
      photos: [{
        ...make().photos[0],
        recipe: { ...make().photos[0].recipe, ...patch },
      }],
    });
  }
});

Deno.test("CPM rejects old or open declarations and private authority fields", () => {
  for (
    const patch of [
      { version: 2 },
      { contract: "server_prepared" },
      { kind: "text" },
      { resource_profile: "new" },
      { owner_id: uid(9) },
      { url: "https://example.invalid" },
      { funding: "free" },
      { scan_id: uid(1).toUpperCase() + "x" },
    ]
  ) reject({ ...make(), ...patch });
  const missing: Record<string, unknown> = make();
  delete missing.package_id;
  reject(missing);
  const role = make();
  Object.assign(role.photos[0].source, { generation: uid(9) });
  reject(role);
  const fraction = make();
  fraction.photos[0].ai.byte_count = 1.5;
  reject(fraction);
  const getter = {
    ...make(),
    get extra() {
      throw new Error("must not invoke");
    },
  };
  reject(getter);
});

Deno.test("CPM wire parser rejects duplicate keys, whitespace and oversized input", () => {
  for (
    const text of [
      fixture.canonical + "\n",
      '{"version":1,' + fixture.canonical.slice(1),
      " ".repeat(1048577),
    ]
  ) assertThrows(() => parseInitialCpmPhotoContent(text));
  assertEquals(
    parseInitialCpmPhotoContent(initialCanonicalText(two())),
    initialCanonicalText(two()),
  );
});
