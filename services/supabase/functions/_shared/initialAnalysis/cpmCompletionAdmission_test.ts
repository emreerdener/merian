import { createCpmPhotoAdmissionDb } from "./cpmPhotoAdmissionDb.ts";
import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { decodeCpmCompletionAdmission } from "./cpmCompletionAdmission.ts";
import { cpmCompletionAdmissionFixture as fixture } from "./fixtures/cpmCompletionAdmission.ts";

Deno.test("CPM acknowledgement preserves exact original admission after eligibility expiry", async () => {
  const f = await fixture();
  const value = await decodeCpmCompletionAdmission(f.reply, f.binding);
  assertEquals(value.admission, f.admission);
  assertEquals(value.admission_canonical, f.reply.admission_canonical);
  assertEquals(value.canonical, initialCanonicalText(f.reply));
});
Deno.test("CPM acknowledgement rejects foreign bindings and closed-shape drift", async (t) => {
  const f = await fixture();
  for (const key of Object.keys(f.reply)) {
    await t.step(key, async () => {
      const changed: Record<string, unknown> = { ...f.reply };
      changed[key] = typeof changed[key] === "number" ? 2 : "changed";
      await assertRejects(() =>
        decodeCpmCompletionAdmission(changed, f.binding)
      );
    });
  }
  for (
    const extra of [{ result_evidence_id: f.binding.scan_id }, {
      outcome: "unadmitted",
    }, { retry: true }]
  ) {
    await assertRejects(() =>
      decodeCpmCompletionAdmission({ ...f.reply, ...extra }, f.binding)
    );
  }
  for (
    const key of [
      "owner_id",
      "scan_id",
      "assignment_digest",
      "backend_generation",
      "backend_configuration_digest",
    ] as const
  ) {
    await t.step("valid foreign " + key, async () => {
      const changed = {
        ...f.reply,
        [key]: key.endsWith("digest")
          ? "0".repeat(64)
          : "00000000-0000-4000-8000-000000000999",
      };
      await assertRejects(() =>
        decodeCpmCompletionAdmission(changed, f.binding)
      );
    });
  }
  for (
    const key of [
      "owner_id",
      "scan_id",
      "input_schema_version",
      "submission_digest",
      "route",
      "ordered_description_digest",
      "ordered_description_count",
    ] as const
  ) {
    await t.step("admission " + key, async () => {
      const changed = {
        ...f.admission,
        [key]: typeof f.admission[key] === "number" ? 99 : "changed",
      };
      await assertRejects(() =>
        decodeCpmCompletionAdmission({
          ...f.reply,
          admission_canonical: initialCanonicalText(changed),
        }, f.binding)
      );
    });
  }
});
Deno.test("CPM acknowledgement rejects corrupt saved assignment, noncanonical and oversized documents", async () => {
  const f = await fixture();
  for (
    const binding of [
      { ...f.binding, assignment_digest: "0".repeat(64) },
      {
        ...f.binding,
        candidate_canonical: f.binding.candidate_canonical + " ",
      },
      {
        ...f.binding,
        assignment_canonical: f.binding.assignment_canonical + " ",
      },
      { ...f.binding, candidate_canonical: "x".repeat(1048577) },
      { ...f.binding, assignment_canonical: "x".repeat(65537) },
    ]
  ) {
    await assertRejects(() => decodeCpmCompletionAdmission(f.reply, binding));
  }
  for (
    const admission_canonical of [
      f.reply.admission_canonical + " ",
      "x".repeat(4097),
    ]
  ) {
    await assertRejects(() =>
      decodeCpmCompletionAdmission(
        { ...f.reply, admission_canonical },
        f.binding,
      )
    );
  }
  await assertRejects(() =>
    decodeCpmCompletionAdmission(
      { ...f.reply, extra: "x".repeat(8193) },
      f.binding,
    )
  );
});
Deno.test("CPM acknowledgement snapshots both inputs before asynchronous validation", async () => {
  const f = await fixture();
  const original = f.reply.admission_canonical;
  const pending = decodeCpmCompletionAdmission(f.reply, f.binding);
  f.reply.admission_canonical = "changed";
  f.binding.owner_id = "changed";
  f.binding.assignment_canonical = "changed";
  assertEquals((await pending).admission_canonical, original);
});

async function environment(run: () => Promise<void>) {
  const names = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"],
    saved = names.map((n) => Deno.env.get(n));
  try {
    Deno.env.set(names[0], "https://trusted.invalid");
    Deno.env.set(names[1], "sb_secret_" + "x".repeat(40));
    await run();
  } finally {
    names.forEach((n, i) =>
      saved[i] === undefined ? Deno.env.delete(n) : Deno.env.set(n, saved[i]!)
    );
  }
}
Deno.test("CPM original acknowledgement uses one bounded read without admission or retry", () =>
  environment(async () => {
    const f = await fixture();
    let calls = 0;
    const db = createCpmPhotoAdmissionDb("a".repeat(64), (url, init) => {
      calls++;
      assertEquals(
        String(url),
        "https://trusted.invalid/rest/v1/rpc/read_initial_cpm_completion_admission_v1",
      );
      assertEquals(init?.redirect, "error");
      assertEquals(init?.cache, "no-store");
      assertEquals(init?.credentials, "omit");
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: f.binding.owner_id,
        p_scan: f.binding.scan_id,
        p_candidate: f.binding.candidate_canonical,
        p_assignment: f.binding.assignment_canonical,
        p_assignment_digest: f.binding.assignment_digest,
        p_backend_generation: f.binding.backend_generation,
        p_backend_configuration_digest: f.binding.backend_configuration_digest,
      });
      return Promise.resolve(new Response(JSON.stringify(f.reply)));
    });
    assertEquals(
      (await db.readCompletionAdmission(
        f.binding,
        new AbortController().signal,
      )).admission,
      f.admission,
    );
    assertEquals(calls, 1);
  }));
Deno.test("CPM acknowledgement transport rejects uncertain, oversized and cancelled reads without retry", () =>
  environment(async () => {
    const f = await fixture();
    for (
      const response of [
        () => Promise.reject(new Error("lost reply")),
        () => Promise.resolve(new Response("unavailable", { status: 503 })),
        () => Promise.resolve(new Response("x".repeat(8193))),
        () =>
          Promise.resolve(
            new Response(JSON.stringify({ ...f.reply, retry: true })),
          ),
      ]
    ) {
      let calls = 0;
      const db = createCpmPhotoAdmissionDb("a".repeat(64), () => {
        calls++;
        return response();
      });
      await assertRejects(() =>
        db.readCompletionAdmission(f.binding, new AbortController().signal)
      );
      assertEquals(calls, 1);
    }
    let calls = 0;
    const db = createCpmPhotoAdmissionDb("a".repeat(64), () => {
      calls++;
      return Promise.resolve(new Response("{}"));
    });
    const controller = new AbortController();
    controller.abort();
    await assertRejects(() =>
      db.readCompletionAdmission(f.binding, controller.signal)
    );
    assertEquals(calls, 0);
    let cancelled = false;
    let started!: () => void;
    const ready = new Promise<void>((resolve) => {
      started = resolve;
    });
    const waiting = createCpmPhotoAdmissionDb(
      "a".repeat(64),
      () =>
        Promise.resolve(
          new Response(
            new ReadableStream({
              start(c) {
                c.enqueue(new TextEncoder().encode("{"));
                started();
              },
              cancel() {
                cancelled = true;
              },
            }),
          ),
        ),
    );
    const late = new AbortController();
    const pending = waiting.readCompletionAdmission(f.binding, late.signal);
    await Promise.race([ready, pending]);
    late.abort();
    await assertRejects(() => pending);
    assertEquals(cancelled, true);
  }));
