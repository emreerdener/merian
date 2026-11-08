import { assert, assertEquals, assertThrows } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import {
  decodeInitialCompletionAcquisition,
  snapshotInitialCompletionAdmission,
} from "./completionAcquisition.ts";
import {
  encodeInitialCompletionStatus,
  initialCompletionStatusResponseBytes,
} from "./completionStatusResponse.ts";
import { completionAcquisitionFixture } from "./fixtures/completionAcquisition.ts";
import { cpmCompletionAdmissionFixture } from "./fixtures/cpmCompletionAdmission.ts";

Deno.test("completion status projects exact original bytes for pending and found, including Unicode", async () => {
  const original = await cpmCompletionAdmissionFixture();
  const admission = snapshotInitialCompletionAdmission(original.admission);
  const pending = JSON.parse(
    new TextDecoder().decode(encodeInitialCompletionStatus(admission, null)),
  );
  assertEquals(pending.admission_canonical, initialCanonicalText(admission));
  assertEquals(pending.outcome, "pending");
  for (const [key, value] of Object.entries(pending)) {
    if (!["version", "outcome", "admission_canonical"].includes(key)) {
      assertEquals(value, null);
    }
  }
  for (const reasoning of ["Synthetic result", "\ufeffe\u0301/🦋\n\t"]) {
    const f = await completionAcquisitionFixture(true, admission, reasoning);
    const acquired = await decodeInitialCompletionAcquisition(
      f.reply,
      admission,
    );
    assert(acquired);
    const bytes = encodeInitialCompletionStatus(admission, acquired),
      text = new TextDecoder().decode(bytes);
    const wire = JSON.parse(text);
    assertEquals(text, initialCanonicalText(wire));
    assertEquals(
      wire.result_canonical,
      acquired.delivery.result.result_canonical,
    );
    assertEquals(
      wire.original_provenance_canonical,
      acquired.original_provenance_canonical,
    );
    assertEquals(
      wire.reference_canonical,
      initialCanonicalText(acquired.reference),
    );
    assertEquals(wire.receipt_canonical, acquired.delivery.receipt_canonical);
    assertEquals(
      wire.projection_canonical,
      acquired.delivery.projection_canonical,
    );
    assert(bytes.length <= initialCompletionStatusResponseBytes);
    assertThrows(() =>
      encodeInitialCompletionStatus({
        ...admission,
        config_digest: "0".repeat(64),
      }, acquired)
    );
    assertThrows(() =>
      encodeInitialCompletionStatus(admission, {
        ...acquired,
        delivery: {
          ...acquired.delivery,
          result: {
            ...acquired.delivery.result,
            result_canonical: "x".repeat(1048577),
          },
        },
      })
    );
  }
});
