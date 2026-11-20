import assert from "node:assert/strict";
import test from "node:test";
import { requestExploreFeedRows } from "./exploreFeedRequest.ts";

test("a deployed pagination RPC retains its lookahead row and exact cursor", async () => {
  const cursor = {
    sharedAt: "2026-11-08T00:00:00.123456Z",
    postId: "fixture-post",
  };
  const rows = Array.from({ length: 49 }, (_, id) => ({ id }));
  const result = await requestExploreFeedRows(async (name, args) => {
    assert.equal(name, "get_public_web_explore_posts_page");
    assert.deepEqual(args, {
      p_max_limit: 48,
      p_before_shared_at: cursor.sharedAt,
      p_before_post_id: cursor.postId,
    });
    return { data: rows, error: null };
  }, cursor);
  assert.deepEqual(result, rows);
});

test("missing pagination RPC uses only the existing public first-page projection", async () => {
  const calls: string[] = [];
  const result = await requestExploreFeedRows(async (name, args) => {
    calls.push(name);
    if (name === "get_public_web_explore_posts_page") {
      return { data: null, error: { code: "PGRST202" } };
    }
    assert.deepEqual(args, { p_target_post_id: null, p_max_limit: 48 });
    return {
      data: Array.from({ length: 49 }, (_, id) => ({ id })),
      error: null,
    };
  }, null);
  assert.deepEqual(calls, [
    "get_public_web_explore_posts_page",
    "get_public_web_explore_posts",
  ]);
  assert.equal(result.length, 48); // No invented cursor/lookahead on the legacy RPC.
});

test("permission and connection failures never trigger compatibility reads", async () => {
  for (const code of ["42501", "PGRST301", "PGRST000", "57014", "42883"]) {
    let requests = 0;
    await assert.rejects(
      requestExploreFeedRows(async () => {
        requests++;
        return { data: null, error: { code } };
      }, null),
      /Explore unavailable/,
    );
    assert.equal(requests, 1);
  }
});

test("a continuation failure never restarts or repeats the first page", async () => {
  let requests = 0;
  await assert.rejects(requestExploreFeedRows(async () => {
    requests++;
    return { data: null, error: { code: "PGRST202" } };
  }, { sharedAt: "2026-11-08T00:00:00Z", postId: "fixture-post" }));
  assert.equal(requests, 1);
});

test("empty public feeds remain distinct from unavailable or malformed results", async () => {
  assert.deepEqual(
    await requestExploreFeedRows(async () => ({ data: [], error: null }), null),
    [],
  );
  await assert.rejects(
    requestExploreFeedRows(async () => ({ data: null, error: null }), null),
  );
  let requests = 0;
  await assert.rejects(requestExploreFeedRows(async () => {
    requests++;
    return {
      data: null,
      error: { code: requests === 1 ? "PGRST202" : "42501" },
    };
  }, null));
  assert.equal(requests, 2);
});
