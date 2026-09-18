import { assertEquals, assertThrows } from "@std/assert";
import {
  canonicalReactionEmoji,
  postReactionCapability,
} from "./exploreReactions.ts";
import catalog from "./emojiCatalog.json" with { type: "json" };

Deno.test("Reaction catalog accepts complex emoji and canonicalizes only qualification aliases", () => {
  for (const emoji of ["😀", "👍🏽", "🇹🇷", "👨‍👩‍👧‍👦", "1️⃣", "🏳️‍🌈"]) {
    assertEquals(canonicalReactionEmoji(emoji), emoji);
  }
  assertEquals(canonicalReactionEmoji("❤"), "❤️");
  assertEquals(canonicalReactionEmoji("👍"), "👍");
  assertEquals(canonicalReactionEmoji("👍🏽"), "👍🏽");
  for (const entry of catalog.entries) {
    for (const alias of entry.aliases) {
      assertEquals(canonicalReactionEmoji(alias), entry.emoji);
    }
  }
});
Deno.test("Reaction input rejects arbitrary text, bare components and multi-emoji input", () => {
  for (
    const input of [
      null,
      {},
      "",
      " ",
      "hello",
      "1",
      "😀😀",
      " 😀 ",
      "🏽",
      "x".repeat(1000),
    ]
  ) {
    assertThrows(() => canonicalReactionEmoji(input));
  }
});
Deno.test("Post reaction compatibility is opt-in and boolean", () => {
  assertEquals(postReactionCapability(undefined), false);
  assertEquals(postReactionCapability(false), false);
  assertEquals(postReactionCapability(true), true);
  for (const input of [null, 1, "true"]) {
    assertThrows(() => postReactionCapability(input));
  }
});

Deno.test("iOS and server bundle the identical versioned emoji catalog", async () => {
  const clientCatalog = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../../../../apps/ios/Merian/Resources/ExploreEmojiCatalog.json",
        import.meta.url,
      ),
    ),
  );
  assertEquals(clientCatalog, catalog);
  assertEquals(catalog.version, "17.0");
});
