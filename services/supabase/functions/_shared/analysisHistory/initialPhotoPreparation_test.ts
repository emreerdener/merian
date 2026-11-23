import { assertEquals, assertNotEquals, assertThrows } from "@std/assert";
import {
  initialPhotoPreparationFields,
  parseInitialPhotoPreparation,
} from "./initialPhotoPreparation.ts";
import {
  initialEvidenceDigest,
  parseInitialEvidenceManifest,
} from "./initialEvidenceManifest.ts";

export const selectedPreparation = () => ({
  schema_version: 1,
  coordinate_basis: "upright_source_top_left_v1",
  format: "nativeSelectedStillImageV2",
  crop_display_size: 390,
  quarter_turns: 1,
  scale: 1.5,
  offset_x: -30,
  offset_y: 25,
  camera_vertical_center: null,
  source_selection: {
    x: 0.2,
    y: 0.3,
    width: 0.1,
    height: 0.2,
    source: "user_selection",
  },
});
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const manifest = () => ({
  schema_version: 9,
  items: [{
    kind: "image",
    source: {
      media_id: id(3),
      content_type: "image/heic",
      byte_count: 33_554_432,
      sha256: "a".repeat(64),
    },
    prepared: {
      media_id: id(4),
      content_type: "image/jpeg",
      byte_count: 100,
      sha256: "b".repeat(64),
    },
    coordinate_basis: "prepared_image_top_left_v1",
    focus_region: null,
    preparation: selectedPreparation(),
  }],
});

Deno.test("initial geometry preserves full-aspect still camera and manually selected recipes", () => {
  const selected = selectedPreparation();
  assertEquals<unknown>(parseInitialPhotoPreparation(selected), selected);
  const still = {
    ...selected,
    format: "nativeStillImageV1",
    source_selection: null,
  };
  assertEquals<unknown>(parseInitialPhotoPreparation(still), still);
  const fullFrame = {
    ...still,
    crop_display_size: null,
    scale: 1,
    offset_x: 0,
    offset_y: 0,
    quarter_turns: 0,
  };
  assertEquals<unknown>(parseInitialPhotoPreparation(fullFrame), fullFrame);
  const fullSelected = {
    ...fullFrame,
    format: "nativeSelectedStillImageV2",
    source_selection: selected.source_selection,
  };
  assertEquals<unknown>(
    parseInitialPhotoPreparation(fullSelected),
    fullSelected,
  );
  for (
    const delta of [
      { quarter_turns: 1 },
      { scale: 1.1 },
      { offset_x: 1 },
      { offset_y: 1 },
      { camera_vertical_center: 0.5 },
      { source_selection: null },
    ]
  ) {
    assertThrows(() =>
      parseInitialPhotoPreparation({ ...fullSelected, ...delta })
    );
  }
  const camera = {
    ...fullFrame,
    format: "nativeCameraStillV1",
    camera_vertical_center: 0.7,
  };
  assertEquals<unknown>(parseInitialPhotoPreparation(camera), camera);
});

Deno.test("initial geometry rejects ambiguous native recipe combinations and private fields", () => {
  for (
    const delta of [
      { isPro: true },
      { environment: {} },
      { schema_version: 2 },
      { coordinate_basis: "prepared_image_top_left_v1" },
      { format: "unknown" },
      { crop_display_size: null },
      { crop_display_size: 0 },
      { crop_display_size: Infinity },
      { quarter_turns: 4 },
      { quarter_turns: 1.5 },
      { scale: NaN },
      { scale: 0.5 },
      { offset_x: Infinity },
      { offset_y: NaN },
      { camera_vertical_center: 0.5 },
      { source_selection: null },
      {
        source_selection: {
          ...selectedPreparation().source_selection,
          source: "vision_objectness",
        },
      },
      {
        source_selection: {
          ...selectedPreparation().source_selection,
          width: 1,
        },
      },
      { format: "nativeStillImageV1" },
      { format: "nativeCameraStillV1" },
    ]
  ) {
    assertThrows(() =>
      parseInitialPhotoPreparation({ ...selectedPreparation(), ...delta })
    );
  }
});

Deno.test("V9 binds geometry and both artifact identities without rewriting V7 or V8", async () => {
  const value = manifest(),
    expected = await initialEvidenceDigest(value, id(1), id(2));
  assertEquals(
    parseInitialEvidenceManifest(value, id(1), id(2)).schema_version,
    9,
  );
  for (const version of [7, 8]) {
    assertThrows(() =>
      parseInitialEvidenceManifest(
        { ...value, schema_version: version },
        id(1),
        id(2),
      )
    );
  }
  for (
    const delta of [
      { quarter_turns: 2 },
      { offset_x: -31 },
      { offset_y: 24 },
      { scale: 1.6 },
      { crop_display_size: 393 },
      {
        source_selection: {
          ...selectedPreparation().source_selection,
          x: 0.21,
        },
      },
    ]
  ) {
    const changed = structuredClone(value);
    Object.assign(changed.items[0].preparation, delta);
    assertNotEquals(
      await initialEvidenceDigest(changed, id(1), id(2)),
      expected,
    );
  }
  for (const role of ["source", "prepared"] as const) {
    const changed = structuredClone(value);
    changed.items[0][role].sha256 = "c".repeat(64);
    assertNotEquals(
      await initialEvidenceDigest(changed, id(1), id(2)),
      expected,
    );
  }
  assertEquals(
    initialPhotoPreparationFields({ ...selectedPreparation(), offset_x: -0 }),
    initialPhotoPreparationFields({ ...selectedPreparation(), offset_x: 0 }),
  );
});
