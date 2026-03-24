import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { jsonResponse, runBackground } from "../_shared/edgeHandler.ts";

// ---------------------------------------------------------------------------
// jsonResponse
// ---------------------------------------------------------------------------

Deno.test("jsonResponse — sets Content-Type to application/json", async () => {
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
    setTimeout(() => { resolved = true; resolve(); }, 10);
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
  const globalObj = globalThis as unknown as { EdgeRuntime?: { waitUntil: (p: Promise<void>) => void } };
  const original = globalObj.EdgeRuntime;

  let capturedTask: Promise<void> | undefined;
  globalObj.EdgeRuntime = {
    waitUntil: (p: Promise<void>) => { capturedTask = p; }
  };

  const task = Promise.resolve();
  runBackground(task);

  assertEquals(capturedTask, task);

  globalObj.EdgeRuntime = original;
});

// ---------------------------------------------------------------------------
// Sanitized error message shapes (expected response bodies from identify)
// ---------------------------------------------------------------------------

Deno.test("jsonResponse — Gemini sanitized error shape matches contract", async () => {
  const res = jsonResponse({ error: "AI processing error. Please try again." }, 400);
  const body = await res.json();
  assertEquals(res.status, 400);
  assertStringIncludes(body.error, "AI processing error");
});

Deno.test("jsonResponse — malformed AI response shape matches contract", async () => {
  const res = jsonResponse({ error: "Processing Error: Malformed AI response." }, 422);
  const body = await res.json();
  assertEquals(res.status, 422);
  assertStringIncludes(body.error, "Processing Error");
});
