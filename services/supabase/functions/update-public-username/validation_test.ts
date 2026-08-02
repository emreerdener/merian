import { assertEquals } from "@std/assert";
import { publicUsernameValidationError } from "./validation.ts";

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
