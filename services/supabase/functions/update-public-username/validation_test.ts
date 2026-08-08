import { assertEquals } from "@std/assert";
import {
  isReservedPublicUsername,
  publicUsernameValidationError,
} from "./validation.ts";

Deno.test("Naturebook and legacy Merian usernames remain reserved", () => {
  assertEquals(
    publicUsernameValidationError("merian"),
    "That username is reserved.",
  );
  assertEquals(
    publicUsernameValidationError("naturebook"),
    "That username is reserved.",
  );
  assertEquals(
    publicUsernameValidationError("naturebookearth"),
    "That username is reserved.",
  );
  assertEquals(publicUsernameValidationError("naturebook_fan"), null);
});

Deno.test("official roles and exact brand-role combinations are reserved", () => {
  for (
    const username of [
      "security",
      "naturebook_support",
      "support_naturebook",
      "explore_team",
      "naturebook_customer_support",
      "customer_support_naturebook",
    ]
  ) {
    assertEquals(isReservedPublicUsername(username), true, username);
  }

  for (
    const username of [
      "naturebook_fan",
      "security_researcher",
      "team_wren",
      "naturebook_supporter",
    ]
  ) {
    assertEquals(isReservedPublicUsername(username), false, username);
  }
});
