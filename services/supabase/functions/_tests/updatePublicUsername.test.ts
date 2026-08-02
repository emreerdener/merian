import { assertEquals } from "@std/assert";
import {
  normalizePublicUsername,
  publicUsernameValidationError,
} from "../update-public-username/validation.ts";

Deno.test("update-public-username - normalizes pasted display text", () => {
  assertEquals(normalizePublicUsername("@Stone Glen 72"), "stone_glen_72");
  assertEquals(normalizePublicUsername("  River--Wren!!  "), "river_wren");
});

Deno.test("update-public-username - validates username policy", () => {
  assertEquals(publicUsernameValidationError("stone_glen_72"), null);
  assertEquals(
    publicUsernameValidationError("admin"),
    "That username is reserved.",
  );
  assertEquals(
    publicUsernameValidationError("72_stone"),
    "Username must start with a letter.",
  );
  assertEquals(
    publicUsernameValidationError("stone__glen"),
    "Username cannot use repeated underscores.",
  );
});
