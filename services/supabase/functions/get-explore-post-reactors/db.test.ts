import { assertEquals, assertRejects } from "@std/assert";
import { PublicHttpError } from "../_shared/http.ts";
import { fetchPostReactors } from "./db.ts";
import { parseReactorsRequest } from "./types.ts";

Deno.test("reactor adapter passes authenticated identity and unchanged cursor to the guarded RPC", async () => {
  const postId = "00000000-0000-4000-8000-000000000001";
  const cursor = "00000000-0000-4000-8000-000000000002";
  const request = parseReactorsRequest({
    post_id: postId,
    after_user_id: cursor,
    self_id: "untrusted",
  });
  const expected = {
    total_count: 0,
    preview_names: [],
    reactors: [],
    next_cursor: null,
  };
  const client = {
    rpc(name: string, parameters: Record<string, unknown>) {
      assertEquals(name, "get_explore_post_reactors");
      assertEquals(parameters, {
        self_id: "authenticated-viewer",
        target_post_id: postId,
        after_user_id: cursor,
      });
      return Promise.resolve({ data: expected, error: null });
    },
  };
  assertEquals(
    await fetchPostReactors(
      "authenticated-viewer",
      request.postId,
      request.afterUserId,
      client as never,
    ),
    expected,
  );
});
Deno.test("reactor adapter maps unavailable targets to the public 403 envelope", async () => {
  const client = {
    rpc: () => Promise.resolve({ data: null, error: { code: "42501" } }),
  };
  const error = await assertRejects(
    () => fetchPostReactors("viewer", "post", null, client as never),
    PublicHttpError,
  );
  assertEquals(error.status, 403);
  assertEquals(error.message, "This post is no longer available.");
});
Deno.test("reactor adapter does not expose internal database errors", async () => {
  const client = {
    rpc: () =>
      Promise.resolve({
        data: null,
        error: { code: "XX000", message: "Internal fixture detail" },
      }),
  };
  const error = await assertRejects(
    () => fetchPostReactors("viewer", "post", null, client as never),
    Error,
  );
  assertEquals(error.message, "Could not load post reactions.");
});
