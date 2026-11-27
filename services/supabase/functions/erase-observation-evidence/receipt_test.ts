import { assertEquals, assertRejects } from "@std/assert";
import { evidenceWorkerReceipt, evidenceWorkerResponse } from "./receipt.ts";

const counts = {
  retired: 0,
  video_retired: 0,
  composition_retired: 0,
  retirement_failures: 0,
  claimed: 0,
  marked: 0,
  acknowledged: 0,
};
const dispatch = "00000000-0000-4000-8000-00000000ee01";
function request(value?: string) {
  return new Request("https://example.invalid", {
    method: "POST",
    headers: value === undefined ? {} : { "X-Merian-Evidence-Dispatch": value },
  });
}

Deno.test("current dispatch reaches SQL work and receives exact terminal correlation", async () => {
  let seen: string | undefined;
  const response = await evidenceWorkerReceipt(request(dispatch), (value) => {
    seen = value;
    return Promise.resolve(counts);
  });
  assertEquals(seen, dispatch);
  assertEquals(response.status, 200);
  assertEquals(response.headers.get("Cache-Control"), "no-store");
  assertEquals(await response.json(), {
    schema_version: 4,
    dispatch_id: dispatch,
    ...counts,
  });
});

Deno.test("missing or invalid dispatch never falls back or starts worker operations", async () => {
  for (
    const value of [
      undefined,
      "",
      "invalid",
      dispatch.toUpperCase(),
      dispatch.replace("4000", "1000"),
      dispatch.replace("8000", "7000"),
      `${dispatch}, ${dispatch}`,
      "a".repeat(4096),
    ]
  ) {
    let calls = 0;
    const response = await evidenceWorkerReceipt(request(value), () => {
      calls++;
      return Promise.resolve(counts);
    });
    assertEquals(calls, 0);
    assertEquals(response.status, 400);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    assertEquals((await response.json()).dispatch_id, undefined);
  }
});

Deno.test("work failure cannot emit a correlated terminal receipt", async () => {
  await assertRejects(
    () =>
      evidenceWorkerReceipt(
        request(dispatch),
        () => Promise.reject(new Error("synthetic")),
      ),
    Error,
    "synthetic",
  );
});

Deno.test("worker failure boundary preserves safe 503 even when its logger throws", async () => {
  for (const loggerThrows of [false, true]) {
    const logs: unknown[] = [];
    let calls = 0;
    const response = await evidenceWorkerResponse(request(dispatch), () => {
      calls++;
      throw new Error("private worker payload");
    }, (event, details) => {
      logs.push({ event, ...details });
      if (loggerThrows) throw new Error("private logger payload");
    });
    assertEquals(calls, 1);
    assertEquals(logs, [{
      event: "private_evidence_worker_failed",
      stage: "worker",
      code: "worker_unavailable",
    }]);
    assertEquals(response.status, 503);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    const body = await response.json();
    assertEquals(body, {
      error: "Private media cleanup is unavailable.",
      code: "private_evidence_erasure_unavailable",
      request_id: response.headers.get("X-Request-ID"),
    });
    assertEquals(typeof body.request_id, "string");
    assertEquals(body.dispatch_id, undefined);
  }
});

Deno.test("worker boundary preserves success correlation and invalid dispatch without failure logging", async () => {
  const logs: unknown[] = [];
  let calls = 0;
  for (const valid of [false, true]) {
    const response = await evidenceWorkerResponse(
      request(valid ? dispatch : undefined),
      () => {
        calls++;
        return Promise.resolve(counts);
      },
      (...args) => logs.push(args),
    );
    assertEquals(response.status, valid ? 200 : 400);
    const body = await response.json();
    if (valid) {
      assertEquals(body, {
        schema_version: 4,
        dispatch_id: dispatch,
        ...counts,
      });
    } else assertEquals(body.dispatch_id, undefined);
  }
  assertEquals(calls, 1);
  assertEquals(logs, []);
});

Deno.test("worker production logger excludes request identities and thrown payloads", async () => {
  const logs: string[] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.join(" "));
  };
  try {
    const response = await evidenceWorkerResponse(
      request(dispatch),
      () => Promise.reject(new Error("private worker detail")),
    );
    assertEquals(response.status, 503);
    assertEquals(logs.length, 1);
    const row = JSON.parse(logs[0]);
    assertEquals(Object.keys(row).sort(), ["code", "event", "stage", "ts"]);
    assertEquals(row.event, "private_evidence_worker_failed");
    assertEquals(row.stage, "worker");
    assertEquals(row.code, "worker_unavailable");
  } finally {
    console.error = original;
  }
});
