import assert from "node:assert/strict";

import { capturedMediaSwiftDTOContract } from "../functions/_shared/capturedMediaContract.ts";
import {
  GENERATED_CAPTURED_MEDIA_SWIFT_BEGIN,
  GENERATED_CAPTURED_MEDIA_SWIFT_END,
  renderGeneratedCapturedMediaSwiftDTOBlock,
  replaceGeneratedCapturedMediaSwiftDTOBlock,
  validateGeneratedCapturedMediaSwiftSource,
} from "./validate_captured_media_dtos.ts";

Deno.test("captured-media generator covers every executable variant and compatibility rule", () => {
  const generated = renderGeneratedCapturedMediaSwiftDTOBlock();
  for (const variant of capturedMediaSwiftDTOContract.variants) {
    assert.match(generated, new RegExp(`case ${variant.swiftCase}\\(`));
    assert.ok(generated.includes(`case "${variant.wireKey}":`));
  }
  assert.ok(generated.includes("source_index"));
  assert.ok(generated.includes("case localFile"));
  assert.ok(generated.includes("if storage == .remoteURL"));
  assert.ok(generated.includes("free_text"));
  assert.ok(generated.includes("addedAt"));
  assert.ok(
    generated.includes(
      "Legacy addedAt/added_at values are intentionally ignored",
    ),
  );
  assert.ok(generated.includes("let audio: CapturedMediaStoredReferenceDTO?"));
  assert.ok(generated.includes(String(capturedMediaSwiftDTOContract.maxItems)));
  assert.ok(
    generated.includes(String(capturedMediaSwiftDTOContract.maxPathLength)),
  );
  assert.ok(
    generated.includes(
      String(capturedMediaSwiftDTOContract.maxDescriptionLength),
    ),
  );
});

Deno.test("captured-media generated block validation is exact", () => {
  const generated = renderGeneratedCapturedMediaSwiftDTOBlock();
  validateGeneratedCapturedMediaSwiftSource(generated);
  assert.throws(
    () =>
      validateGeneratedCapturedMediaSwiftSource(
        generated.replace(
          "// Generated from",
          "// Drifted from",
        ),
      ),
    /stale/,
  );
  assert.throws(
    () =>
      validateGeneratedCapturedMediaSwiftSource(
        generated.replace("case remoteURL", "case documents"),
      ),
    /stale/,
  );
});

Deno.test("captured-media regeneration preserves hand-written domain mapping", () => {
  const stale = [
    "import Foundation",
    "",
    GENERATED_CAPTURED_MEDIA_SWIFT_BEGIN,
    "// stale",
    GENERATED_CAPTURED_MEDIA_SWIFT_END,
    "",
    "// Hand-written mapping remains.",
  ].join("\n");
  const regenerated = replaceGeneratedCapturedMediaSwiftDTOBlock(stale);
  assert.ok(regenerated.includes(renderGeneratedCapturedMediaSwiftDTOBlock()));
  assert.ok(regenerated.endsWith("// Hand-written mapping remains."));
  assert.equal(
    regenerated.match(/BEGIN GENERATED: CapturedMedia wire DTOs/g)?.length,
    1,
  );
});
