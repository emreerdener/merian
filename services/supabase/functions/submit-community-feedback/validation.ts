const MAX_FEEDBACK_LENGTH = 4000;
const MAX_METADATA_LENGTH = 160;

export type CommunityFeedbackInsert = {
  feedback: string;
  app_version: string | null;
  build_number: string | null;
  platform: string;
  os_version: string | null;
};

export function parseCommunityFeedbackPayload(
  body: unknown,
): CommunityFeedbackInsert {
  if (!isRecord(body)) {
    throw badRequest("JSON body must be an object.");
  }

  const feedback = requiredString(body, "feedback", MAX_FEEDBACK_LENGTH);

  return {
    feedback,
    app_version: optionalNullableString(
      body,
      "app_version",
      MAX_METADATA_LENGTH,
    ),
    build_number: optionalNullableString(
      body,
      "build_number",
      MAX_METADATA_LENGTH,
    ),
    platform: optionalString(body, "platform", MAX_METADATA_LENGTH) || "ios",
    os_version: optionalNullableString(body, "os_version", MAX_METADATA_LENGTH),
  };
}

function requiredString(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): string {
  const value = body[key];
  if (typeof value !== "string") {
    throw badRequest(`${key} must be a string.`);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw badRequest(`${key} cannot be blank.`);
  }
  if (trimmed.length > maxLength) {
    throw badRequest(`${key} is too long.`);
  }
  return trimmed;
}

function optionalString(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): string {
  const value = body[key];
  if (value == null) return "";
  if (typeof value !== "string") {
    throw badRequest(`${key} must be a string.`);
  }
  const trimmed = value.trim();
  if (trimmed.length > maxLength) {
    throw badRequest(`${key} is too long.`);
  }
  return trimmed;
}

function optionalNullableString(
  body: Record<string, unknown>,
  key: string,
  maxLength: number,
): string | null {
  const value = optionalString(body, key, maxLength);
  return value === "" ? null : value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function badRequest(message: string): Error & { status: number } {
  return Object.assign(new Error(message), { status: 400 });
}
