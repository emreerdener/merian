import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";
import { initialCpmPhotoCandidateDigest } from "./cpmPhotoCandidate.ts";
import { encodeBase64 } from "../encoding.ts";
import projectionVector from "./fixtures/cpm-admission-submission-v1.json" with {
  type: "json",
};
import { initialCpmPhotoAssignmentDigest } from "./cpmPhotoAssignment.ts";
import { initialDeadline } from "./transport.ts";
import { fixture, hash, timestamp } from "./cpmPhotoAdmissionTestFixtures.ts";

Deno.test("CPM admission consumes complete bound evidence once and reconciles committed receipt", async () => {
  const f = await fixture();
  assertEquals(await f.run(), {
    version: 1,
    outcome: "admitted",
    authority: "none",
  });
  assertEquals(f.calls, ["recover", "begin", "verify", "admit", "recover"]);
});
Deno.test("CPM retained admission reconciliation performs no fresh work", async () => {
  const f = await fixture();
  f.commit();
  assertEquals((await f.run()).outcome, "admitted");
  assertEquals(f.calls, ["recover"]);
});
Deno.test("CPM initial unknown reconciliation cannot authorize start", async () => {
  const f = await fixture();
  f.bridge.recover = () => {
    f.calls.push("recover");
    throw new Error("unknown");
  };
  assertEquals((await f.run()).outcome, "held");
  assertEquals(f.calls, ["recover"]);
});
Deno.test("CPM unknown or held start never invokes verifier", async (t) => {
  for (const kind of ["unknown", "held", "malformed"]) {
    await t.step(kind, async () => {
      const f = await fixture();
      f.bridge.begin = () => {
        f.calls.push("begin");
        if (kind === "unknown") {
          throw new Error("lost start acknowledgement");
        }
        return Promise.resolve(
          kind === "held"
            ? { version: 1, outcome: "held", authority: "none" }
            : {},
        );
      };
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.calls, ["recover", "begin", "recover"]);
    });
  }
});
Deno.test("CPM lost admission acknowledgement reconciles without repeat verification or funding", async () => {
  const f = await fixture();
  f.bridge.admit = () => {
    f.calls.push("admit");
    f.commit();
    throw new Error("lost acknowledgement");
  };
  assertEquals((await f.run()).outcome, "admitted");
  assertEquals(f.calls, ["recover", "begin", "verify", "admit", "recover"]);
});
Deno.test("CPM unknown verification and uncommitted admission remain held", async (t) => {
  for (const phase of ["verify", "admit"] as const) {
    await t.step(phase, async () => {
      const f = await fixture();
      f.bridge[phase] = () => {
        f.calls.push(phase);
        throw new Error("unknown");
      };
      assertEquals((await f.run()).outcome, "held");
      assertEquals(
        f.calls.filter((c) => c === phase).length,
        1,
      );
      assertEquals(f.calls.filter((c) => c === "verify").length, 1);
      assertEquals(f.calls.at(-1), "recover");
    });
  }
});
Deno.test("CPM rejects partial reordered substituted or nonstructural verifier evidence", async (t) => {
  const mutations: Record<
    string,
    (f: Awaited<ReturnType<typeof fixture>>) => void
  > = {
    partial: (f) => {
      f.verified.objects.pop();
    },
    duplicate: (f) => {
      f.verified.objects[1] = f.verified.objects[0];
    },
    order: (f) => {
      f.verified.objects.reverse();
    },
    hash: (f) => {
      f.verified.objects[0].sha256 = "b".repeat(64);
    },
    length: (f) => {
      f.verified.objects[0].byte_count++;
    },
    type: (f) => {
      f.verified.objects[0].content_type = "image/png";
    },
    framing: (f) => {
      f.verified.objects[0].structural_acceptance = false;
    },
    build: (f) => {
      f.verified.verifier_build_digest = "c".repeat(64);
    },
    attempt: (f) => {
      f.verified.attempt_id = f.identity.owner_id;
    },
    snapshot: (f) => {
      f.verified.snapshot_digest = "d".repeat(64);
    },
  };
  for (const [name, mutate] of Object.entries(mutations)) {
    await t.step(name, async () => {
      const f = await fixture();
      mutate(f);
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.calls, ["recover", "begin", "verify", "recover"]);
    });
  }
});
Deno.test("CPM rejects a digest-consistent snapshot from another owner or reordered cohort", async (t) => {
  for (const order of [false, true]) {
    await t.step(String(order), async () => {
      const f = await fixture();
      if (order) f.snapshot.members.reverse();
      else f.snapshot.owner_id = f.identity.scan_id;
      f.begun.snapshot_canonical = initialCanonicalText(f.snapshot);
      f.begun.snapshot_digest = await hash(
        "merian.initial-analysis.cpm-verification-start.v1",
        f.begun.snapshot_canonical,
      );
      assertEquals((await f.run()).outcome, "held");
      assertEquals(f.calls, ["recover", "begin", "recover"]);
    });
  }
});
Deno.test("CPM abort during verifier prevents late admission", async () => {
  const f = await fixture(), controller = new AbortController();
  let complete!: (value: unknown) => void;
  let entered!: () => void;
  const ready = new Promise<void>((resolve) => {
    entered = resolve;
  });
  f.bridge.verify = () => {
    f.calls.push("verify");
    entered();
    return new Promise((resolve) => {
      complete = resolve;
    });
  };
  const running = f.run(controller.signal);
  await ready;
  controller.abort();
  await running.catch(() => undefined);
  complete(f.verified);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(f.calls.includes("admit"), false);
  assertEquals(f.calls.filter((c) => c === "verify").length, 1);
});
Deno.test("CPM snapshots caller identity before the first await", async () => {
  const f = await fixture(), saved = { ...f.identity };
  const running = f.run();
  f.identity.owner_id = f.identity.scan_id;
  // The injected receiver compares with original immutable values as well.
  f.bridge.admit = (e) => {
    assertEquals(e.owner_id, saved.owner_id);
    f.commit();
    return Promise.resolve();
  };
  assertEquals((await running).outcome, "admitted");
});
Deno.test("CPM invalid saved assignment rejects before recovery or start", async () => {
  const f = await fixture();
  f.identity.assignment_digest = "0".repeat(64);
  await assertRejects(() => f.run());
  assertEquals(f.calls, []);
});

Deno.test("CPM expired assignment still reconciles but never starts fresh work", async (t) => {
  for (const saved of [false, true]) {
    await t.step(String(saved), async () => {
      const f = await fixture();
      const a = JSON.parse(f.identity.assignment_canonical);
      a.created_at_ms -= 3_600_000;
      a.expires_at_ms -= 3_600_000;
      f.identity.assignment_canonical = initialCanonicalText(a);
      f.identity.assignment_digest = await initialCpmPhotoAssignmentDigest(
        JSON.parse(f.identity.candidate_canonical),
        a,
      );
      if (saved) f.commit();
      assertEquals((await f.run()).outcome, saved ? "admitted" : "held");
      assertEquals(f.calls, ["recover"]);
    });
  }
});

Deno.test("CPM digest-consistent snapshot cannot renew capability clock", async () => {
  const f = await fixture();
  f.snapshot.members[0].attempt.capability_expires_at = timestamp(
    Date.now() + 700_000,
  );
  f.begun.snapshot_canonical = initialCanonicalText(f.snapshot);
  f.begun.snapshot_digest = await hash(
    "merian.initial-analysis.cpm-verification-start.v1",
    f.begun.snapshot_canonical,
  );
  assertEquals((await f.run()).outcome, "held");
  assertEquals(f.calls, ["recover", "begin", "recover"]);
});

Deno.test("CPM late begin acknowledgement after abort never invokes verifier", async () => {
  const f = await fixture(), controller = new AbortController();
  let complete!: (value: unknown) => void, entered!: () => void;
  const ready = new Promise<void>((resolve) => {
    entered = resolve;
  });
  f.bridge.begin = () => {
    f.calls.push("begin");
    entered();
    return new Promise((resolve) => {
      complete = resolve;
    });
  };
  const running = f.run(controller.signal);
  await ready;
  controller.abort();
  await running.catch(() => undefined);
  complete(f.begun);
  await new Promise((resolve) => setTimeout(resolve, 0));
  assertEquals(f.calls.includes("verify"), false);
  assertEquals(f.calls.includes("admit"), false);
});

Deno.test("CPM short parent budget preserves recovery reserve without beginning", async () => {
  const f = await fixture();
  const result = await initialDeadline(
    new AbortController().signal,
    4_000,
    f.run,
  );
  assertEquals(result.outcome, "held");
  assertEquals(f.calls, ["recover"]);
});

Deno.test("CPM original admission window must also fit the recovery reserve", async () => {
  const f = await fixture(), now = Date.now;
  const expires = JSON.parse(f.identity.assignment_canonical).expires_at_ms;
  f.bridge.recover = () => {
    f.calls.push("recover");
    Date.now = () => expires - 4_999;
    return Promise.resolve(false);
  };
  try {
    assertEquals((await f.run()).outcome, "held");
    assertEquals(f.calls, ["recover"]);
  } finally {
    Date.now = now;
  }
});

Deno.test("CPM managed work deadline discards late begin and verification replies", async (t) => {
  for (const phase of ["begin", "verify"] as const) {
    await t.step(phase, async () => {
      const f = await fixture();
      let complete!: (value: unknown) => void;
      f.bridge[phase] = (_identity, signal) => {
        f.calls.push(phase);
        // No caller abort: the nested work deadline must fire on its own.
        assertEquals(signal.aborted, false);
        return new Promise((resolve) => {
          complete = resolve;
        });
      };
      const result = await initialDeadline(
        new AbortController().signal,
        5_300,
        f.run,
      );
      assertEquals(result.outcome, "held");
      assertEquals(typeof complete, "function");
      complete(phase === "begin" ? f.begun : f.verified);
      await new Promise((resolve) => setTimeout(resolve, 0));
      assertEquals(
        f.calls,
        phase === "begin"
          ? ["recover", "begin", "recover"]
          : ["recover", "begin", "verify", "recover"],
      );
    });
  }
});

Deno.test("CPM admission at work deadline is reconciled inside remaining parent reserve", async () => {
  const f = await fixture();
  const descriptor = Object.getOwnPropertyDescriptor(performance, "now");
  const now = performance.now.bind(performance);
  let advance = 0;
  Object.defineProperty(performance, "now", {
    configurable: true,
    value: () => now() + advance,
  });
  try {
    f.bridge.admit = () => {
      f.calls.push("admit");
      f.commit();
      advance = 1_100; // Work budget <= 1s, parent budget 6s.
      return Promise.resolve();
    };
    const result = await initialDeadline(
      new AbortController().signal,
      6_000,
      f.run,
    );
    assertEquals(result.outcome, "admitted");
    assertEquals(f.calls, ["recover", "begin", "verify", "admit", "recover"]);
  } finally {
    if (descriptor) Object.defineProperty(performance, "now", descriptor);
    else Reflect.deleteProperty(performance, "now");
  }
});

Deno.test("CPM second invocation after unknown verification cannot start verifier again", async () => {
  const f = await fixture();
  let started = false;
  f.bridge.begin = () => {
    f.calls.push("begin");
    if (started) {
      return Promise.resolve({
        version: 1,
        outcome: "held",
        authority: "none",
      });
    }
    started = true;
    return Promise.resolve(f.begun);
  };
  f.bridge.verify = () => {
    f.calls.push("verify");
    return Promise.reject(new Error("lost_verification_outcome"));
  };
  assertEquals((await f.run()).outcome, "held");
  assertEquals((await f.run()).outcome, "held");
  assertEquals(f.calls, [
    "recover",
    "begin",
    "verify",
    "recover",
    "recover",
    "begin",
    "recover",
  ]);
});

Deno.test("CPM admission preserves exact encoded contexts and whole submitted content", async (t) => {
  for (
    const texts of [[], [""], [
      "a\u0000b",
      "\ufeffstart",
      "e\u0301",
      "é",
      " \n ",
    ], ["second", "first", ""]]
  ) {
    await t.step(
      String(texts.length) + ":" + (texts[0]?.length ?? 0),
      async () => {
        const contexts = texts.map((text) => ({
          text_utf8_base64: encodeBase64(new TextEncoder().encode(text)),
        }));
        const f = await fixture(async (candidate, assignment) => {
          const content = JSON.parse(candidate.content_canonical);
          content.contexts = contexts;
          candidate.content_canonical = initialCanonicalText(content);
          assignment.content_digest = await initialCpmPhotoContentDigest(
            content,
          );
          assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
            candidate,
          );
        });
        let received = "";
        const admit = f.bridge.admit;
        f.bridge.admit = async (evidence, signal) => {
          received = evidence.descriptions_canonical;
          assertEquals(
            evidence.submission_canonical,
            JSON.parse(f.identity.candidate_canonical).content_canonical,
          );
          assertEquals(
            evidence.descriptions_digest,
            await hash(
              "merian.initial-analysis.cpm-photo-contexts.v1",
              initialCanonicalText(contexts),
            ),
          );
          // JSONB receives ASCII base64, never a literal NUL or normalized Unicode.
          assertEquals(received.includes("\u0000"), false);
          await admit(evidence, signal);
        };
        assertEquals((await f.run()).outcome, "admitted");
        assertEquals(received, initialCanonicalText(contexts));
        assertEquals(JSON.parse(received), contexts);
      },
    );
  }
});

Deno.test("CPM encoded-context digest distinguishes empty, reordered and normalized text", async () => {
  const outputs = new Set<string>();
  for (
    const texts of [
      [],
      [""],
      ["a", "b"],
      ["b", "a"],
      ["é"],
      ["e\u0301"],
      ["a\u0000b"],
      ["ab"],
      ["\ufeffa"],
      ["a"],
    ]
  ) {
    const f = await fixture(async (candidate, assignment) => {
      const content = JSON.parse(candidate.content_canonical);
      content.contexts = texts.map((text) => ({
        text_utf8_base64: encodeBase64(new TextEncoder().encode(text)),
      }));
      candidate.content_canonical = initialCanonicalText(content);
      assignment.content_digest = await initialCpmPhotoContentDigest(content);
      assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
        candidate,
      );
    });
    const admit = f.bridge.admit;
    f.bridge.admit = async (evidence, signal) => {
      outputs.add(evidence.descriptions_digest);
      await admit(evidence, signal);
    };
    assertEquals((await f.run()).outcome, "admitted");
  }
  assertEquals(outputs.size, 10);
});

Deno.test("CPM actual admission bridge receives the independent SQL projection vector", async () => {
  const f = await fixture();
  const admit = f.bridge.admit;
  f.bridge.admit = async (evidence, signal) => {
    const projection = Object.fromEntries(
      Object.keys(projectionVector.projection).map((
        key,
      ) => [key, evidence[key as keyof typeof evidence]]),
    );
    assertEquals<unknown>(projection, projectionVector.projection);
    await admit(evidence, signal);
  };
  assertEquals((await f.run()).outcome, "admitted");
});

Deno.test("CPM admission retains accepted context bytes above the verifier-evidence cap", async () => {
  const contexts = Array.from({ length: 4 }, () => ({
    text_utf8_base64: encodeBase64(new TextEncoder().encode("🦋".repeat(4000))),
  }));
  const f = await fixture(async (candidate, assignment) => {
    const content = JSON.parse(candidate.content_canonical);
    content.contexts = contexts;
    candidate.content_canonical = initialCanonicalText(content);
    assignment.content_digest = await initialCpmPhotoContentDigest(content);
    assignment.candidate_digest = await initialCpmPhotoCandidateDigest(
      candidate,
    );
  });
  const admit = f.bridge.admit;
  f.bridge.admit = async (evidence, signal) => {
    assertEquals(evidence.descriptions_canonical.length > 65536, true);
    assertEquals(JSON.parse(evidence.descriptions_canonical), contexts);
    await admit(evidence, signal);
  };
  assertEquals((await f.run()).outcome, "admitted");
});
