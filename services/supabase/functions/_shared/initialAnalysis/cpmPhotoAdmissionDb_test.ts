import { assertEquals, assertRejects } from "@std/assert";
import { createCpmPhotoAdmissionDb } from "./cpmPhotoAdmissionDb.ts";
import { verifyAndAdmitInitialCpmPhoto } from "./cpmPhotoAdmission.ts";
import { initialCanonicalText } from "./canonical.ts";
import { initialCpmPhotoCandidateDigest } from "./cpmPhotoCandidate.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";
import { fixture } from "./cpmPhotoAdmissionTestFixtures.ts";

async function environment(run: () => Promise<void>) {
  const names = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
  const saved = names.map((name) => Deno.env.get(name));
  try {
    Deno.env.set(names[0], "https://trusted.invalid");
    Deno.env.set(names[1], "sb_secret_" + "x".repeat(40));
    await run();
  } finally {
    names.forEach((name, i) =>
      saved[i] === undefined
        ? Deno.env.delete(name)
        : Deno.env.set(name, saved[i]!)
    );
  }
}
function response(f: Awaited<ReturnType<typeof fixture>>, admitted = false) {
  return {
    version: 1,
    variant: "client_prepared_photo",
    authority: "none",
    outcome: admitted ? "admitted" : "unadmitted",
    owner_id: f.identity.owner_id,
    scan_id: f.identity.scan_id,
    candidate_digest: f.snapshot.candidate_digest,
    assignment_digest: f.identity.assignment_digest,
    admission_receipt_id: admitted
      ? "00000000-0000-4000-8000-000000000777"
      : null,
    admission_receipt_digest: admitted ? "d".repeat(64) : null,
  };
}
const reply = (v: unknown, status = 200) =>
  Promise.resolve(new Response(JSON.stringify(v), { status }));
const signal = () => new AbortController().signal;

Deno.test("CPM fixed bridge reconciles lost commit response without repeating verification or funding", () =>
  environment(async () => {
    const f = await fixture();
    const calls: string[] = [];
    let committed = false, verifies = 0;
    const db = createCpmPhotoAdmissionDb("a".repeat(64), (url, init) => {
      const path = new URL(String(url)).pathname;
      calls.push(path);
      assertEquals(new URL(String(url)).origin, "https://trusted.invalid");
      assertEquals(init?.redirect, "error");
      assertEquals(init?.credentials, "omit");
      const body = JSON.parse(String(init?.body));
      assertEquals(body.p_candidate, f.identity.candidate_canonical);
      assertEquals(body.p_assignment, f.identity.assignment_canonical);
      if (path.endsWith("/read_initial_cpm_photo_admission")) {
        return reply(response(f, committed));
      }
      if (path.endsWith("/begin_initial_cpm_photo_admission")) {
        return reply(f.begun);
      }
      assertEquals(path, "/rest/v1/rpc/admit_initial_cpm_photo");
      assertEquals(body.p_ip_hash, "a".repeat(64));
      assertEquals(JSON.parse(body.p_verification), f.verified);
      committed = true;
      return Promise.reject(new Error("synthetic lost acknowledgement"));
    });
    const bridge = {
      ...db,
      verify: () => {
        verifies++;
        return Promise.resolve(f.verified);
      },
    };
    assertEquals(
      await verifyAndAdmitInitialCpmPhoto(bridge, f.identity, signal()),
      { version: 1, outcome: "admitted", authority: "none" },
    );
    assertEquals(
      await verifyAndAdmitInitialCpmPhoto(bridge, f.identity, signal()),
      { version: 1, outcome: "admitted", authority: "none" },
    );
    assertEquals(verifies, 1);
    assertEquals(calls.map((x) => x.split("/").at(-1)), [
      "read_initial_cpm_photo_admission",
      "begin_initial_cpm_photo_admission",
      "admit_initial_cpm_photo",
      "read_initial_cpm_photo_admission",
      "read_initial_cpm_photo_admission",
    ]);
  }));

Deno.test("CPM recovery rejects unknown and contradictory responses instead of reporting absence", () =>
  environment(async () => {
    const f = await fixture();
    const cases = [
      null,
      false,
      {},
      { ...response(f), owner_id: "00000000-0000-4000-8000-000000000888" },
      { ...response(f), authority: "execute" },
      { ...response(f), extra: true },
      { ...response(f, true), admission_receipt_digest: null },
      {
        ...response(f),
        admission_receipt_id: response(f, true).admission_receipt_id,
      },
      { ...response(f), assignment_digest: "f".repeat(64) },
    ];
    for (const value of cases) {
      let calls = 0;
      const db = createCpmPhotoAdmissionDb("a".repeat(64), () => {
        calls++;
        return reply(value);
      });
      await assertRejects(() => db.recover(f.identity, signal()));
      assertEquals(calls, 1);
    }
    for (const status of [204, 400, 403, 409, 500]) {
      const db = createCpmPhotoAdmissionDb(
        "a".repeat(64),
        () =>
          status === 204
            ? Promise.resolve(new Response(null, { status }))
            : reply(response(f), status),
      );
      await assertRejects(() => db.recover(f.identity, signal()));
    }
  }));

Deno.test("CPM transport snapshots identity and destination before asynchronous work", () =>
  environment(async () => {
    const f = await fixture();
    const identity = { ...f.identity };
    const db = createCpmPhotoAdmissionDb("a".repeat(64), (url, init) => {
      assertEquals(new URL(String(url)).origin, "https://trusted.invalid");
      assertEquals(JSON.parse(String(init?.body)).p_owner, f.identity.owner_id);
      return reply(response(f));
    });
    const pending = db.recover(identity, signal());
    identity.owner_id = "00000000-0000-4000-8000-000000000888";
    Deno.env.set("SUPABASE_URL", "https://other.invalid");
    assertEquals(await pending, false);
  }));

Deno.test("CPM held start and failed recovery never invoke verifier or admission", () =>
  environment(async () => {
    const f = await fixture();
    for (const unknown of [false, true]) {
      const calls: string[] = [];
      const db = createCpmPhotoAdmissionDb("a".repeat(64), (url) => {
        const path = new URL(String(url)).pathname;
        calls.push(path);
        return path.endsWith("/read_initial_cpm_photo_admission")
          ? reply(unknown ? {} : response(f))
          : reply({ version: 1, outcome: "held", authority: "none" });
      });
      let verifies = 0;
      const bridge = {
        ...db,
        verify: () => {
          verifies++;
          return Promise.resolve(f.verified);
        },
      };
      assertEquals(
        await verifyAndAdmitInitialCpmPhoto(bridge, f.identity, signal()),
        { version: 1, outcome: "held", authority: "none" },
      );
      assertEquals(verifies, 0);
      assertEquals(
        calls.some((x) => x.endsWith("/admit_initial_cpm_photo")),
        false,
      );
    }
  }));

Deno.test("CPM transport cancels oversized and stalled bodies without accepting absence", () =>
  environment(async () => {
    const f = await fixture();
    for (const mode of ["oversized", "stalled"] as const) {
      let cancelled = false, calls = 0;
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          if (mode === "oversized") controller.enqueue(new Uint8Array(262145));
        },
        cancel() {
          cancelled = true;
        },
      });
      const db = createCpmPhotoAdmissionDb("a".repeat(64), () => {
        calls++;
        return Promise.resolve(new Response(stream));
      });
      const started = performance.now();
      await assertRejects(() => db.recover(f.identity, signal()));
      const elapsed = performance.now() - started;
      assertEquals(cancelled, true);
      assertEquals(stream.locked, false);
      assertEquals(calls, 1);
      assertEquals(elapsed < 6500, true);
      if (mode === "stalled") assertEquals(elapsed >= 4500, true);
    }
  }));

Deno.test("CPM cancellation discards a late fetch response without retry", () =>
  environment(async () => {
    const f = await fixture();
    let complete!: (response: Response) => void;
    let entered!: () => void;
    const called = new Promise<void>((resolve) => entered = resolve);
    let cancelled = false, calls = 0;
    const db = createCpmPhotoAdmissionDb("a".repeat(64), () => {
      calls++;
      entered();
      return new Promise<Response>((resolve) => complete = resolve);
    });
    const controller = new AbortController();
    const pending = db.recover(f.identity, controller.signal);
    await called;
    controller.abort();
    await assertRejects(() => pending);
    const stream = new ReadableStream<Uint8Array>({
      cancel() {
        cancelled = true;
      },
    });
    complete(new Response(stream));
    await new Promise((resolve) => setTimeout(resolve, 0));
    assertEquals(cancelled, true);
    assertEquals(calls, 1);
  }));

Deno.test("CPM transport accepts exact maximum context text above legacy body limits", () =>
  environment(async () => {
    const f = await fixture(async (candidate, assignment) => {
      const content = JSON.parse(candidate.content_canonical);
      const bytes = new TextEncoder().encode("🦋".repeat(8192));
      content.contexts = [{
        text_utf8_base64: btoa(String.fromCharCode(...bytes)),
      }];
      candidate.content_canonical = initialCanonicalText(content);
      assignment.content_digest = await initialCpmPhotoContentDigest(content);
      assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
        candidate,
      );
    });
    let count = 0;
    const db = createCpmPhotoAdmissionDb("a".repeat(64), (_url, init) => {
      count++;
      const body = String(init?.body);
      assertEquals(new TextEncoder().encode(body).length > 32768, true);
      assertEquals(
        JSON.parse(body).p_candidate,
        f.identity.candidate_canonical,
      );
      return reply(response(f));
    });
    assertEquals(await db.recover(f.identity, signal()), false);
    assertEquals(count, 1);
  }));

Deno.test("CPM transport accepts two photos and maximum aggregate contexts, rejects excess before I/O", () =>
  environment(async () => {
    const f = await fixture(async (candidate, assignment) => {
      const content = JSON.parse(candidate.content_canonical);
      // Three UTF-8 bytes per UTF-16 unit:64 contexts x500 units =32000 units.
      const encoded = btoa(
        String.fromCharCode(...new TextEncoder().encode("\u0800".repeat(500))),
      );
      content.contexts = Array.from(
        { length: 64 },
        () => ({ text_utf8_base64: encoded }),
      );
      const second = structuredClone(content.photos[0]);
      second.ordinal = 1;
      for (const [index, role] of ["source", "ai", "display"].entries()) {
        second[role].reference_id =
          `00000000-0000-4000-8000-00000000070${index}`;
        assignment.preparation.role_mapping.push({
          photo_ordinal: 1,
          role,
          object_id: `00000000-0000-4000-8000-00000000060${index}`,
          declaration: second[role],
        });
      }
      content.photos.push(second);
      candidate.content_canonical = initialCanonicalText(content);
      assignment.content_digest = await initialCpmPhotoContentDigest(content);
      assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
        candidate,
      );
    });
    let calls = 0;
    const db = createCpmPhotoAdmissionDb("a".repeat(64), (_url, init) => {
      calls++;
      const raw = String(init?.body);
      assertEquals(new TextEncoder().encode(raw).length > 128000, true);
      assertEquals(JSON.parse(raw).p_candidate, f.identity.candidate_canonical);
      return reply(response(f));
    });
    assertEquals(await db.recover(f.identity, signal()), false);
    for (const excess of ["aggregate", "count"] as const) {
      const candidate = JSON.parse(f.identity.candidate_canonical);
      const content = JSON.parse(candidate.content_canonical);
      if (excess === "aggregate") {
        content.contexts[0].text_utf8_base64 = btoa(
          String.fromCharCode(
            ...new TextEncoder().encode("\u0800".repeat(501)),
          ),
        );
      } else content.contexts.push({ text_utf8_base64: "" });
      candidate.content_canonical = initialCanonicalText(content);
      await assertRejects(() =>
        db.recover({
          ...f.identity,
          candidate_canonical: initialCanonicalText(candidate),
        }, signal())
      );
    }
    assertEquals(calls, 1);
  }));

Deno.test("CPM current check binds the original start and grants no renewed authority", () =>
  environment(async () => {
    const f = await fixture();
    const start = {
      ...f.identity,
      attempt_id: f.begun.attempt_id,
      snapshot_canonical: f.begun.snapshot_canonical,
      snapshot_digest: f.begun.snapshot_digest,
    };
    const ack = {
      version: 1,
      outcome: "current",
      authority: "none",
      owner_id: start.owner_id,
      scan_id: start.scan_id,
      assignment_digest: start.assignment_digest,
      attempt_id: start.attempt_id,
      snapshot_digest: start.snapshot_digest,
    };
    let calls = 0;
    const db = createCpmPhotoAdmissionDb("a".repeat(64), (url, init) => {
      calls++;
      assertEquals(
        new URL(String(url)).pathname,
        "/rest/v1/rpc/assert_initial_cpm_photo_verification_current",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: start.owner_id,
        p_scan: start.scan_id,
        p_assignment_digest: start.assignment_digest,
        p_attempt: start.attempt_id,
        p_snapshot_digest: start.snapshot_digest,
      });
      return reply(ack);
    });
    await db.requireCurrent(start, signal());
    await assertRejects(() =>
      db.requireCurrent({ ...start, snapshot_digest: "0".repeat(64) }, signal())
    );
    assertEquals(calls, 1);
    for (
      const bad of [
        null,
        {},
        { ...ack, outcome: "started" },
        { ...ack, authority: "verify" },
        { ...ack, attempt_id: "00000000-0000-4000-8000-000000000888" },
        { ...ack, snapshot_digest: "0".repeat(64) },
        { ...ack, lease: "renewed" },
      ]
    ) {
      const denied = createCpmPhotoAdmissionDb(
        "a".repeat(64),
        () => reply(bad),
      );
      await assertRejects(() => denied.requireCurrent(start, signal()));
    }
  }));
