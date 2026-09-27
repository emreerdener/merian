import {
  type IdentificationInputProfile,
  isIdentificationInputProfile,
} from "./identificationInput.ts";

/** Database-owned identification recipient. No client/runtime provider selector. */
export interface IdentificationProviderAssignment {
  readonly inputProfile: IdentificationInputProfile;
  readonly provider: "gemini";
  readonly binding: "gemini_baseline_v1";
  readonly permission: "google_gemini";
}

export function isIdentificationProviderAssignment(
  value: unknown,
): value is IdentificationProviderAssignment {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const assignment = value as Record<string, unknown>;
  return isIdentificationInputProfile(assignment.inputProfile) &&
    assignment.provider === "gemini" &&
    assignment.binding === "gemini_baseline_v1" &&
    assignment.permission === "google_gemini";
}
