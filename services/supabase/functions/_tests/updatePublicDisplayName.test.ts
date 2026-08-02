import { assertEquals } from "@std/assert";
import {
  makePublicDisplayNameResponse,
  normalizePublicDisplayName,
  publicDisplayNameValidationError,
} from "../update-public-display-name/displayName.ts";

Deno.test("update-public-display-name - normalizes whitespace", () => {
  assertEquals(normalizePublicDisplayName("  River   Wren  "), "River Wren");
  assertEquals(normalizePublicDisplayName("\nStone\tGlen\n"), "Stone Glen");
});

Deno.test("update-public-display-name - validates display name policy", () => {
  assertEquals(publicDisplayNameValidationError("River Wren"), null);
  assertEquals(publicDisplayNameValidationError(""), null);
  assertEquals(
    publicDisplayNameValidationError("A".repeat(41)),
    "Display name must be 40 characters or fewer.",
  );
  assertEquals(
    publicDisplayNameValidationError("River\u0000Wren"),
    "Display name cannot include control characters.",
  );
});

Deno.test("update-public-display-name - response uses API field name", () => {
  assertEquals(makePublicDisplayNameResponse("River Wren"), {
    display_name: "River Wren",
  });
});
