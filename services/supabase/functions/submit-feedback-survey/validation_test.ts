import { assertEquals, assertThrows } from "@std/assert";
import { parseFeedbackSurveyPayload, VALID_CAMPAIGN_ID } from "./validation.ts";

const validPayload = {
  survey_campaign_id: VALID_CAMPAIGN_ID,
  satisfaction_rating: 4,
  recommendation_rating: 9,
  used_features: [
    "identify_found_subject",
    "browse_explore",
    "browse_explore",
  ],
  most_useful_features: [
    "camera_identification",
    "insight_sheet",
    "insight_sheet",
  ],
  confusing_or_disappointing: "  Slow on my older phone.  ",
  wished_next: "Better collection tools.",
  bug_status: "workaround",
  bug_details: "One retry fixed it.",
  may_follow_up: true,
  contact: " beta@example.com ",
  app_version: "1.0",
  build_number: "99",
  platform: "ios",
  device_model: "iPhone",
  os_version: "19.0",
  locale: "en_US",
  timezone: "America/Chicago",
  user_id: "spoofed-user",
};

Deno.test("parseFeedbackSurveyPayload accepts valid survey response and normalizes fields", () => {
  const parsed = parseFeedbackSurveyPayload(validPayload);

  assertEquals(parsed.survey_campaign_id, VALID_CAMPAIGN_ID);
  assertEquals(parsed.satisfaction_rating, 4);
  assertEquals(parsed.recommendation_rating, 9);
  assertEquals(parsed.used_features, [
    "identify_found_subject",
    "browse_explore",
  ]);
  assertEquals(parsed.most_useful_features, [
    "camera_identification",
    "insight_sheet",
  ]);
  assertEquals(parsed.confusing_or_disappointing, "Slow on my older phone.");
  assertEquals(parsed.contact, "beta@example.com");
  assertEquals(parsed.raw_response.user_id, undefined);
});

Deno.test("parseFeedbackSurveyPayload rejects unknown campaign ids", () => {
  assertThrows(
    () =>
      parseFeedbackSurveyPayload({
        ...validPayload,
        survey_campaign_id: "future_campaign",
      }),
    Error,
    "Unknown survey campaign.",
  );
});

Deno.test("parseFeedbackSurveyPayload rejects invalid rating ranges", () => {
  assertThrows(
    () =>
      parseFeedbackSurveyPayload({ ...validPayload, satisfaction_rating: 6 }),
    Error,
    "satisfaction_rating must be an integer from 1 to 5.",
  );

  assertThrows(
    () =>
      parseFeedbackSurveyPayload({
        ...validPayload,
        recommendation_rating: -1,
      }),
    Error,
    "recommendation_rating must be an integer from 0 to 10.",
  );
});

Deno.test("parseFeedbackSurveyPayload rejects invalid enum values", () => {
  assertThrows(
    () =>
      parseFeedbackSurveyPayload({
        ...validPayload,
        used_features: ["unknown"],
      }),
    Error,
    "used_features contains an invalid value.",
  );

  assertThrows(
    () => parseFeedbackSurveyPayload({ ...validPayload, bug_status: "maybe" }),
    Error,
    "bug_status is invalid.",
  );

  assertThrows(
    () =>
      parseFeedbackSurveyPayload({
        ...validPayload,
        most_useful_features: ["unknown"],
      }),
    Error,
    "most_useful_features contains an invalid value.",
  );
});

Deno.test("parseFeedbackSurveyPayload caps long free text", () => {
  assertThrows(
    () =>
      parseFeedbackSurveyPayload({
        ...validPayload,
        wished_next: "x".repeat(4001),
      }),
    Error,
    "wished_next is too long.",
  );
});
