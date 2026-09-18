import { assertEquals, assertThrows } from "@std/assert";
import { parseReactorsRequest } from "./types.ts";
const id = "00000000-0000-4000-8000-000000000001";
Deno.test("post reactors validates UUIDs and optional cursor without trusting a caller identity", () => {
  assertEquals(parseReactorsRequest({ post_id: id, self_id: "ignored" }), {
    postId: id,
    afterUserId: null,
  });
  assertEquals(parseReactorsRequest({ post_id: id, after_user_id: id }), {
    postId: id,
    afterUserId: id,
  });
  assertEquals(
    parseReactorsRequest({ post_id: id, after_user_id: null }).afterUserId,
    null,
  );
  for (const post_id of [null, 42, "", "not-a-uuid", [id]]) {
    assertThrows(() => parseReactorsRequest({ post_id }));
  }
  for (const after_user_id of [42, "", "not-a-uuid", [id]]) {
    assertThrows(() => parseReactorsRequest({ post_id: id, after_user_id }));
  }
});
