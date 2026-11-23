import { exactObject, invalidHistory } from "./contract.ts";
import {
  imageFocusFingerprintFields,
  parseImageFocusRegion,
} from "../identify/imageFocus.ts";

/** Geometry only. The enclosing V9 manifest binds both source and prepared
 * artifacts. This does not promise pixel-identical re-encoding or carry the
 * native preparation environment, subscription state or file authority. */
export function parseInitialPhotoPreparation(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "coordinate_basis",
    "format",
    "crop_display_size",
    "quarter_turns",
    "scale",
    "offset_x",
    "offset_y",
    "camera_vertical_center",
    "source_selection",
  ]);
  const finite = (v: unknown): v is number =>
    typeof v === "number" && Number.isFinite(v);
  if (
    row.schema_version !== 1 ||
    row.coordinate_basis !== "upright_source_top_left_v1" ||
    !["nativeStillImageV1", "nativeCameraStillV1", "nativeSelectedStillImageV2"]
      .includes(String(row.format)) ||
    !finite(row.quarter_turns) || !Number.isInteger(row.quarter_turns) ||
    row.quarter_turns < 0 || row.quarter_turns > 3 ||
    !finite(row.scale) || row.scale < 1 || !finite(row.offset_x) ||
    !finite(row.offset_y) ||
    (row.crop_display_size !== null &&
      (!finite(row.crop_display_size) || row.crop_display_size <= 0)) ||
    (row.camera_vertical_center !== null &&
      (!finite(row.camera_vertical_center) || row.camera_vertical_center < 0 ||
        row.camera_vertical_center > 1))
  ) {
    return invalidHistory();
  }
  const selection = row.source_selection === null
    ? null
    : parseImageFocusRegion(row.source_selection);
  if (
    row.source_selection !== null &&
    (!selection || selection.source !== "user_selection")
  ) return invalidHistory();
  if (
    row.crop_display_size === null &&
    (row.quarter_turns !== 0 || row.scale !== 1 || row.offset_x !== 0 ||
      row.offset_y !== 0)
  ) return invalidHistory();
  switch (row.format) {
    case "nativeCameraStillV1":
      if (
        row.camera_vertical_center === null || row.crop_display_size !== null ||
        selection !== null
      ) return invalidHistory();
      break;
    case "nativeStillImageV1":
      if (row.camera_vertical_center !== null || selection !== null) {
        return invalidHistory();
      }
      break;
    case "nativeSelectedStillImageV2":
      if (
        row.camera_vertical_center !== null || selection === null
      ) return invalidHistory();
      break;
    default:
      return invalidHistory();
  }
  return Object.freeze({
    schema_version: 1 as const,
    coordinate_basis: "upright_source_top_left_v1" as const,
    format: row.format,
    crop_display_size: row.crop_display_size,
    quarter_turns: row.quarter_turns,
    scale: row.scale,
    offset_x: row.offset_x,
    offset_y: row.offset_y,
    camera_vertical_center: row.camera_vertical_center,
    source_selection: selection,
  });
}

export type InitialPhotoPreparation = ReturnType<
  typeof parseInitialPhotoPreparation
>;

export function initialPhotoPreparationFields(
  value: unknown,
): readonly (string | number)[] {
  const p = parseInitialPhotoPreparation(value);
  const binary64 = (value: number) => {
    const bytes = new Uint8Array(8);
    new DataView(bytes.buffer).setFloat64(0, value === 0 ? 0 : value, false);
    return Array.from(bytes, (x) => x.toString(16).padStart(2, "0")).join("");
  };
  return Object.freeze([
    p.schema_version,
    p.coordinate_basis,
    p.format,
    p.crop_display_size === null ? 0 : 1,
    ...(p.crop_display_size === null ? [] : [binary64(p.crop_display_size)]),
    p.quarter_turns,
    ...[p.scale, p.offset_x, p.offset_y].map(binary64),
    p.camera_vertical_center === null ? 0 : 1,
    ...(p.camera_vertical_center === null
      ? []
      : [binary64(p.camera_vertical_center)]),
    p.source_selection === null ? 0 : 1,
    ...(p.source_selection === null
      ? []
      : imageFocusFingerprintFields(p.source_selection)),
  ]);
}
