import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  jsonResponse,
  logStructuredError,
  runBackground,
  withEdgeHandler,
  withPublicEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { publicErrorResponse, publicHttpError } from "../_shared/http.ts";

// ---------------------------------------------------------------------------
// jsonResponse
// ---------------------------------------------------------------------------

Deno.test("jsonResponse — sets Content-Type to application/json", () => {
  const res = jsonResponse({ ok: true }, 200);
  assertEquals(res.headers.get("Content-Type"), "application/json");
});

Deno.test("jsonResponse — encodes payload as JSON", async () => {
  const payload = { error: "Not found", code: 42 };
  const res = jsonResponse(payload, 404);
  const body = await res.json();
  assertEquals(body, payload);
});

Deno.test("jsonResponse — status code is preserved", () => {
  assertEquals(jsonResponse({}, 200).status, 200);
  assertEquals(jsonResponse({}, 400).status, 400);
  assertEquals(jsonResponse({}, 401).status, 401);
  assertEquals(jsonResponse({}, 422).status, 422);
  assertEquals(jsonResponse({}, 500).status, 500);
});

Deno.test("jsonResponse — default status is 200", () => {
  assertEquals(jsonResponse({ ok: true }).status, 200);
});

Deno.test("jsonResponse — null payload encodes to 'null'", async () => {
  const res = jsonResponse(null, 200);
  const text = await res.text();
  assertEquals(text, "null");
});

// ---------------------------------------------------------------------------
// runBackground
// ---------------------------------------------------------------------------

Deno.test("runBackground — calls task.catch when EdgeRuntime is absent", async () => {
  // Ensure EdgeRuntime is not set in this test environment
  const globalObj = globalThis as unknown as { EdgeRuntime?: unknown };
  const original = globalObj.EdgeRuntime;
  delete globalObj.EdgeRuntime;

  let resolved = false;
  const task = new Promise<void>((resolve) => {
    setTimeout(() => {
      resolved = true;
      resolve();
    }, 10);
  });

  runBackground(task);
  await task;
  assertEquals(resolved, true);

  globalObj.EdgeRuntime = original;
});

Deno.test("runBackground — swallows rejection and logs when EdgeRuntime is absent", async () => {
  const globalObj = globalThis as unknown as { EdgeRuntime?: unknown };
  const original = globalObj.EdgeRuntime;
  delete globalObj.EdgeRuntime;

  // Replace console.error temporarily to capture the rejection log
  const errors: unknown[] = [];
  const originalError = console.error;
  console.error = (...args: unknown[]) => errors.push(args);

  const task = Promise.reject<void>(new Error("bg failure"));
  runBackground(task);

  // Wait for the microtask queue to flush
  await new Promise((r) => setTimeout(r, 20));

  assertEquals(errors.length, 1);

  console.error = originalError;
  globalObj.EdgeRuntime = original;
});

Deno.test("runBackground — uses EdgeRuntime.waitUntil when available", () => {
  const globalObj = globalThis as unknown as {
    EdgeRuntime?: { waitUntil: (p: Promise<void>) => void };
  };
  const original = globalObj.EdgeRuntime;

  let capturedTask: Promise<void> | undefined;
  globalObj.EdgeRuntime = {
    waitUntil: (p: Promise<void>) => {
      capturedTask = p;
    },
  };

  const task = Promise.resolve();
  runBackground(task);

  assertEquals(capturedTask, task);

  globalObj.EdgeRuntime = original;
});

// ---------------------------------------------------------------------------
// logStructuredError
// ---------------------------------------------------------------------------

Deno.test("logStructuredError — emits JSON with event, ts, and all detail fields", () => {
  const logs: unknown[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logs.push(args[0]);

  logStructuredError("safe_delete_partial_failure", {
    user_id: "u123",
    state: "auth_deleted_data_not_anonymised",
  });

  console.error = original;
  assertEquals(logs.length, 1);
  const parsed = JSON.parse(logs[0] as string);
  assertEquals(parsed.event, "safe_delete_partial_failure");
  assertEquals(parsed.user_id, "u123");
  assertEquals(parsed.state, "auth_deleted_data_not_anonymised");
  assert(typeof parsed.ts === "string", "ts field must be present");
  assert(parsed.ts.endsWith("Z"), "ts must be UTC ISO-8601");
});

Deno.test("logStructuredError — ts is a valid ISO date", () => {
  const logs: unknown[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logs.push(args[0]);

  logStructuredError("test_event", {});

  console.error = original;
  const parsed = JSON.parse(logs[0] as string);
  assert(!isNaN(Date.parse(parsed.ts)), "ts must parse as a valid date");
});

Deno.test("logStructuredError — event key is always present even with empty details", () => {
  const logs: unknown[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logs.push(args[0]);

  logStructuredError("empty_detail_event", {});

  console.error = original;
  const parsed = JSON.parse(logs[0] as string);
  assertEquals(parsed.event, "empty_detail_event");
  assertEquals(typeof parsed.ts, "string");
});

Deno.test("logStructuredError — detail fields do not overwrite event or ts", () => {
  const logs: unknown[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => logs.push(args[0]);

  logStructuredError("real_event", {
    event: "injected_event",
    ts: "injected_ts",
  });

  console.error = original;
  assertEquals(logs.length, 1);
  const parsed = JSON.parse(logs[0] as string);
  assertEquals(parsed.event, "real_event");
  assert(parsed.ts !== "injected_ts");
  assert(!isNaN(Date.parse(parsed.ts)));
});

// ---------------------------------------------------------------------------
// withEdgeHandler public error boundary
// ---------------------------------------------------------------------------

Deno.test("withEdgeHandler ignores duck-typed exception status and message", async () => {
  const response = await invokeTestHandler(() => {
    throw {
      status: 418,
      code: "attacker_selected",
      message: "database host and schema details",
    };
  });
  const body = await response.json();

  assertEquals(response.status, 500);
  assertEquals(body.code, "internal_error");
  assertEquals(body.error, "The request could not be completed.");
  assertEquals(JSON.stringify(body).includes("database host"), false);
  assertEquals(response.headers.get("X-Request-ID"), body.request_id);
});

Deno.test("withEdgeHandler preserves explicitly trusted public errors", async () => {
  const response = await invokeTestHandler(() => {
    throw publicHttpError(
      409,
      "That operation was already completed.",
      "already_completed",
    );
  });
  const body = await response.json();

  assertEquals(response.status, 409);
  assertEquals(body.code, "already_completed");
  assertEquals(body.error, "That operation was already completed.");
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
});

Deno.test("withEdgeHandler sanitizes returned 5xx bodies and keeps bounded retry metadata", async () => {
  const response = await invokeTestHandler(() =>
    jsonResponse(
      {
        error: "provider secret and database details",
        debug: "private",
      },
      503,
      { "Retry-After": "30" },
    )
  );
  const body = await response.json();

  assertEquals(response.status, 503);
  assertEquals(body.code, "service_unavailable");
  assertEquals(body.error, "The service is temporarily unavailable.");
  assertEquals(JSON.stringify(body).includes("private"), false);
  assertEquals(response.headers.get("Retry-After"), "30");
  assertEquals(body.retry_after_seconds, 30);
});

Deno.test("withEdgeHandler adds stable metadata to returned 4xx errors", async () => {
  const response = await invokeTestHandler(() =>
    jsonResponse({ error: "Invalid field.", code: "invalid_field" }, 400)
  );
  const body = await response.json();

  assertEquals(response.status, 400);
  assertEquals(body.error, "Invalid field.");
  assertEquals(body.code, "invalid_field");
  assertEquals(typeof body.request_id, "string");
  assertEquals(response.headers.get("X-Request-ID"), body.request_id);
});

Deno.test("withPublicEdgeHandler applies metadata without auth timing", async () => {
  const request = new Request(
    "https://test-project.supabase.co/functions/v1/public",
  );
  const response = await withPublicEdgeHandler(
    request,
    () => jsonResponse({ ok: true }),
  );

  assertEquals(response.status, 200);
  assertEquals(typeof response.headers.get("X-Request-ID"), "string");
  assertEquals(response.headers.get("Server-Timing"), null);
});

Deno.test("withPublicEdgeHandler sanitizes custom-handler exceptions", async () => {
  const originalError = console.error;
  console.error = () => {};
  try {
    const request = new Request(
      "https://test-project.supabase.co/functions/v1/public",
    );
    const response = await withPublicEdgeHandler(request, () => {
      throw new Error("private provider and schema details");
    });
    const body = await response.json();

    assertEquals(response.status, 500);
    assertEquals(body.code, "internal_error");
    assertEquals(JSON.stringify(body).includes("private provider"), false);
    assertEquals(response.headers.get("X-Request-ID"), body.request_id);
  } finally {
    console.error = originalError;
  }
});

Deno.test("withPublicEdgeHandler preserves explicit safe 5xx contracts", async () => {
  const request = new Request(
    "https://test-project.supabase.co/functions/v1/public",
  );
  const response = await withPublicEdgeHandler(
    request,
    () =>
      publicErrorResponse(
        request,
        503,
        "provider_snapshot_unavailable",
        "The provider snapshot is temporarily unavailable.",
        { retryAfterSeconds: 30 },
      ),
  );
  const body = await response.json();

  assertEquals(response.status, 503);
  assertEquals(body.code, "provider_snapshot_unavailable");
  assertEquals(
    body.error,
    "The provider snapshot is temporarily unavailable.",
  );
  assertEquals(body.retry_after_seconds, 30);
  assertEquals(response.headers.get("Retry-After"), "30");
});

// ---------------------------------------------------------------------------
// Sanitized error message shapes (expected response bodies from identify)
// ---------------------------------------------------------------------------

Deno.test("jsonResponse — Gemini sanitized error shape matches contract", async () => {
  const res = jsonResponse(
    { error: "AI processing error. Please try again." },
    400,
  );
  const body = await res.json();
  assertEquals(res.status, 400);
  assertStringIncludes(body.error, "AI processing error");
});

Deno.test("jsonResponse — malformed AI response shape matches contract", async () => {
  const res = jsonResponse({
    error: "Processing Error: Malformed AI response.",
  }, 422);
  const body = await res.json();
  assertEquals(res.status, 422);
  assertStringIncludes(body.error, "Processing Error");
});

async function invokeTestHandler(
  handler: () => Response | Promise<Response>,
): Promise<Response> {
  const previousUrl = Deno.env.get("SUPABASE_URL");
  const previousKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const originalError = console.error;
  console.error = () => {};
  Deno.env.set("SUPABASE_URL", "https://test-project.supabase.co");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");

  try {
    return await withEdgeHandler(
      new Request("https://test-project.supabase.co/functions/v1/test", {
        method: "POST",
      }),
      async () => await handler(),
      {
        authenticate: () =>
          Promise.resolve({
            user: { id: "00000000-0000-0000-0000-000000000001" } as never,
            response: null,
          }),
      },
    );
  } finally {
    console.error = originalError;
    if (previousUrl === undefined) Deno.env.delete("SUPABASE_URL");
    else Deno.env.set("SUPABASE_URL", previousUrl);
    if (previousKey === undefined) Deno.env.delete("SUPABASE_SERVICE_ROLE_KEY");
    else Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", previousKey);
  }
}
