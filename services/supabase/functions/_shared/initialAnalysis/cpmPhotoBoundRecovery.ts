/** Negotiated metadata enrichment. Legacy private v1 recovery stays closed. */
import { initialCanonicalText, invalidInitialInput } from "./canonical.ts";
import { validateInitialCpmPhotoRecovery } from "./cpmPhotoRecovery.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./cpm-photo-recovery-schema-v3.json" with { type: "json" };

export async function validateInitialCpmPhotoBoundRecovery(
  candidate: unknown,
  response: unknown,
  savedAssignmentCanonical: string | null,
): Promise<string> {
  // Snapshot all fields before digest verification suspends.
  const text = initialCanonicalText(response);
  const value = JSON.parse(text);
  if (matchesInitialSchema(value, schema.terminal_held)) {
    return await validateInitialCpmPhotoRecovery(
      candidate,
      value,
      savedAssignmentCanonical,
    );
  }
  if (!matchesInitialSchema(value, schema.allocated)) {
    return invalidInitialInput();
  }
  const {
    backend_generation,
    backend_configuration_digest: _digest,
    ...legacy
  } = value;
  await validateInitialCpmPhotoRecovery(
    candidate,
    { ...legacy, version: 1 },
    savedAssignmentCanonical,
  );
  const assignment = JSON.parse(value.assignment_canonical);
  if (backend_generation !== assignment.preparation.backend_generation) {
    return invalidInitialInput();
  }
  // The service-only SQL projection binds the opaque digest to its immutable
  // registry. It is not derivable from an assignment containing generation only.
  return text;
}
