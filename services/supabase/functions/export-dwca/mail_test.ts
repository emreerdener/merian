import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sendExportEmail } from "./mail.ts";
import { ExportWorkerError } from "./types.ts";

Deno.test("export email uses a job-scoped Resend idempotency key", async () => {
  const captured: { request: Request | null } = { request: null };
  const emailId = await sendExportEmail(
    "user@example.invalid",
    "https://r2.example.invalid/archive.zip?a=1&b=2",
    "00000000-0000-4000-8000-000000000301",
    {
      apiKey: "re_test",
      from: "Naturebook <exports@example.invalid>",
      fetcher: (input, init) => {
        captured.request = new Request(input, init);
        return Promise.resolve(
          new Response(JSON.stringify({ id: "email-1" })),
        );
      },
    },
  );

  assertEquals(emailId, "email-1");
  if (!captured.request) throw new Error("Expected a Resend request.");
  assertEquals(
    captured.request.headers.get("Idempotency-Key"),
    "dwca-export/00000000-0000-4000-8000-000000000301",
  );
  const body = await captured.request.json();
  assertEquals(body.to, ["user@example.invalid"]);
  assertEquals(
    String(body.html).includes(
      "https://r2.example.invalid/archive.zip?a=1&amp;b=2",
    ),
    true,
  );
});

Deno.test("export email fails closed without RESEND_API_KEY", async () => {
  const error = await assertRejects(
    () =>
      sendExportEmail(
        "user@example.invalid",
        "https://r2.example.invalid/archive.zip",
        "00000000-0000-4000-8000-000000000302",
        { apiKey: "" },
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "delivery_failed");
});

Deno.test("transient Resend errors keep the job retryable", async () => {
  const error = await assertRejects(
    () =>
      sendExportEmail(
        "user@example.invalid",
        "https://r2.example.invalid/archive.zip",
        "00000000-0000-4000-8000-000000000303",
        {
          apiKey: "re_test",
          from: "Naturebook <exports@example.invalid>",
          fetcher: () =>
            Promise.resolve(
              new Response(JSON.stringify({ message: "unavailable" }), {
                status: 503,
              }),
            ),
        },
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "delivery_failed");
  assertEquals(error.safeToFailJob, false);
});

Deno.test("ambiguous Resend timeout responses keep the job retryable", async () => {
  const error = await assertRejects(
    () =>
      sendExportEmail(
        "user@example.invalid",
        "https://r2.example.invalid/archive.zip",
        "00000000-0000-4000-8000-000000000307",
        {
          apiKey: "re_test",
          from: "Naturebook <exports@example.invalid>",
          fetcher: () =>
            Promise.resolve(
              new Response(null, {
                status: 408,
              }),
            ),
        },
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "delivery_failed");
  assertEquals(error.safeToFailJob, false);
});

Deno.test("Resend network failures keep the job retryable", async () => {
  const error = await assertRejects(
    () =>
      sendExportEmail(
        "user@example.invalid",
        "https://r2.example.invalid/archive.zip",
        "00000000-0000-4000-8000-000000000304",
        {
          apiKey: "re_test",
          from: "Naturebook <exports@example.invalid>",
          fetcher: () => Promise.reject(new TypeError("network unavailable")),
        },
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "delivery_failed");
  assertEquals(error.safeToFailJob, false);
});

Deno.test("ambiguous successful Resend responses keep the job retryable", async () => {
  const error = await assertRejects(
    () =>
      sendExportEmail(
        "user@example.invalid",
        "https://r2.example.invalid/archive.zip",
        "00000000-0000-4000-8000-000000000305",
        {
          apiKey: "re_test",
          from: "Naturebook <exports@example.invalid>",
          fetcher: () =>
            Promise.resolve(
              new Response(JSON.stringify({ accepted: true }), {
                status: 202,
              }),
            ),
        },
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "delivery_failed");
  assertEquals(error.safeToFailJob, false);
});

Deno.test("oversized successful Resend responses remain ambiguous and bounded", async () => {
  const error = await assertRejects(
    () =>
      sendExportEmail(
        "user@example.invalid",
        "https://r2.example.invalid/archive.zip",
        "00000000-0000-4000-8000-000000000306",
        {
          apiKey: "re_test",
          from: "Naturebook <exports@example.invalid>",
          fetcher: () =>
            Promise.resolve(
              new Response("x".repeat(20 * 1024), { status: 202 }),
            ),
        },
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "delivery_failed");
  assertEquals(error.safeToFailJob, false);
});
