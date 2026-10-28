import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialCpmPhotoCandidateDigest } from "./cpmPhotoCandidate.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";
import {
  initialCpmPhotoAssignmentDigest,
  validateInitialCpmPhotoAssignment,
} from "./cpmPhotoAssignment.ts";
import { validateInitialCpmPhotoRecovery } from "./cpmPhotoRecovery.ts";
import candidateFixture from "./fixtures/cpm-photo-candidate-v1.json" with {
  type: "json",
};
import fixture from "./fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};

const candidate = () => structuredClone(candidateFixture.candidate);
const assignment = () => structuredClone(fixture.assignment);
const reply = () => ({
  version: 1,
  variant: "client_prepared_photo",
  outcome: "allocated",
  authority: "none",
  assignment_canonical: fixture.canonical,
  assignment_digest: fixture.digest,
});
const terminal = () => ({
  version: 1,
  variant: "client_prepared_photo",
  outcome: "terminal_held",
  authority: "none",
  scan_id: fixture.assignment.scan_id,
  reason: "expired",
});
const rejectAssignment = (a: unknown) =>
  assertRejects(
    () => validateInitialCpmPhotoAssignment(candidate(), a),
    Error,
    "initial_analysis_input_invalid",
  );
const rejectRecovery = (r: unknown, saved: string | null = fixture.canonical) =>
  assertRejects(
    () => validateInitialCpmPhotoRecovery(candidate(), r, saved),
    Error,
    "initial_analysis_input_invalid",
  );

Deno.test("CPM saved assignment and recovery match independent canonical/digest fixture", async () => {
  assertEquals(
    await validateInitialCpmPhotoAssignment(candidate(), assignment()),
    fixture.canonical,
  );
  assertEquals(
    await initialCpmPhotoAssignmentDigest(candidate(), assignment()),
    fixture.digest,
  );
  for (const saved of [null, fixture.canonical]) {
    assertEquals(
      await validateInitialCpmPhotoRecovery(candidate(), reply(), saved),
      initialCanonicalText(reply()),
    );
    assertEquals(
      await validateInitialCpmPhotoRecovery(candidate(), terminal(), saved),
      initialCanonicalText(terminal()),
    );
  }
});

Deno.test("CPM assignment snapshots both mutable inputs before digest awaits", async () => {
  const c = candidate(), a = assignment();
  const pending = initialCpmPhotoAssignmentDigest(c, a);
  c.content_canonical = "{}";
  a.preparation.role_mapping[0].object_id =
    a.preparation.role_mapping[1].object_id;
  a.configuration.output_language = "fr";
  assertEquals(await pending, fixture.digest);
  const response = reply(), c2 = candidate();
  const recovery = validateInitialCpmPhotoRecovery(
    c2,
    response,
    fixture.canonical,
  );
  response.assignment_canonical = "{}";
  c2.admission.expected_processor_permission = "openai";
  assertEquals(await recovery, initialCanonicalText(reply()));
});

Deno.test("CPM assignment rejects identity, role, clock and authority drift", async (t) => {
  const edits: [string, (a: ReturnType<typeof assignment>) => unknown][] = [
    ["version", (a) => ({ ...a, version: 2 })],
    ["legacy variant", (a) => ({ ...a, variant: "media_sources" })],
    ["candidate digest", (a) => ({ ...a, candidate_digest: "0".repeat(64) })],
    ["content digest", (a) => ({ ...a, content_digest: "0".repeat(64) })],
    ["scan", (a) => ({ ...a, scan_id: a.package_id })],
    ["package", (a) => ({ ...a, package_id: a.scan_id })],
    ["shortened clock", (a) => ({ ...a, expires_at_ms: a.expires_at_ms - 1 })],
    ["extended clock", (a) => ({ ...a, expires_at_ms: a.expires_at_ms + 1 })],
    [
      "fractional clock",
      (a) => ({ ...a, created_at_ms: a.created_at_ms + 0.5 }),
    ],
    ["private owner", (a) => ({ ...a, owner_id: a.scan_id })],
    [
      "upload grant",
      (a) => ({ ...a, upload_url: "https://example.invalid/forbidden" }),
    ],
    ["missing member", (a) => {
      a.preparation.role_mapping.pop();
      return a;
    }],
    ["duplicate destination", (a) => {
      a.preparation.role_mapping[1].object_id =
        a.preparation.role_mapping[0].object_id;
      return a;
    }],
    ["role order", (a) => {
      a.preparation.role_mapping.reverse();
      return a;
    }],
    ["photo ordinal", (a) => {
      a.preparation.role_mapping[0].photo_ordinal = 1;
      return a;
    }],
    ["logical reference", (a) => {
      a.preparation.role_mapping[0].declaration.reference_id = a.package_id;
      return a;
    }],
    ["hash", (a) => {
      a.preparation.role_mapping[0].declaration.sha256 = "0".repeat(64);
      return a;
    }],
    ["size", (a) => {
      a.preparation.role_mapping[0].declaration.byte_count++;
      return a;
    }],
    ["declared type", (a) => {
      a.preparation.role_mapping[0].declaration.declared_content_type =
        "image/png";
      return a;
    }],
    ["composition", (a) => {
      a.preparation.composition_policy = "legacy";
      return a;
    }],
    ["resource profile", (a) => {
      a.preparation.resource_profile = "unbounded";
      return a;
    }],
    ["processor expectation", (a) => {
      a.configuration.processor_permission = "openai";
      return a;
    }],
    ["provider binding", (a) => {
      a.configuration.provider = "openai";
      return a;
    }],
    ["accepted client", (a) => {
      a.configuration.accepted_client_protocol = 2;
      return a;
    }],
    ["required client", (a) => {
      a.configuration.minimum_client_protocol = 4;
      return a;
    }],
    ["required capability", (a) => {
      a.configuration.minimum_identification_protocol = 7;
      return a;
    }],
    ["plan tier", (a) => {
      a.configuration.effective_tier = "free";
      return a;
    }],
    ["effective model", (a) => {
      a.configuration.effective_model = "changed";
      return a;
    }],
    ["route profile", (a) => {
      a.configuration.route = "identify-multimodal";
      return a;
    }],
    ["text route", (a) => {
      a.configuration.route = "identify-describe";
      return a;
    }],
    [
      "absent language",
      (a) => ({
        ...a,
        configuration: { ...a.configuration, output_language: null },
      }),
    ],
  ];
  for (const [name, edit] of edits) {
    await t.step(name, async () => {
      await rejectAssignment(edit(assignment()));
    });
  }
});

Deno.test("CPM recovery preserves the first saved clock, config and destination generation", async () => {
  for (const kind of ["clock", "config", "destination", "generation"]) {
    const changed = assignment();
    if (kind === "clock") {
      changed.created_at_ms++;
      changed.expires_at_ms++;
    }
    if (kind === "config") changed.configuration.output_language = "fr";
    if (kind === "destination") {
      changed.preparation.role_mapping[0].object_id = changed.package_id;
    }
    if (kind === "generation") {
      changed.preparation.backend_generation = changed.package_id;
    }
    const canonical = await validateInitialCpmPhotoAssignment(
      candidate(),
      changed,
    );
    const response = {
      ...reply(),
      assignment_canonical: canonical,
      assignment_digest: await initialCpmPhotoAssignmentDigest(
        candidate(),
        changed,
      ),
    };
    await rejectRecovery(response);
    // Without a first acknowledgement only the server can prove original identity.
    assertEquals(
      await validateInitialCpmPhotoRecovery(candidate(), response, null),
      initialCanonicalText(response),
    );
  }
});

Deno.test("CPM recovery rejects unknown outcomes, altered wire and replacement permission", async () => {
  for (
    const response of [
      { ...reply(), authority: "upload" },
      { ...reply(), outcome: "admitted" },
      { ...reply(), assignment_digest: "0".repeat(64) },
      { ...reply(), assignment_canonical: fixture.canonical + "\n" },
      { ...terminal(), scan_id: fixture.assignment.package_id },
      { ...terminal(), reason: "retry" },
      { ...terminal(), replace_allowed: true },
      { ...reply(), owner_id: fixture.assignment.scan_id },
      null,
      [],
    ]
  ) await rejectRecovery(response);
  for (const reason of ["not_found", "expired", "cancelled"]) {
    const response = { ...terminal(), reason };
    assertEquals(
      await validateInitialCpmPhotoRecovery(candidate(), response, null),
      initialCanonicalText(response),
    );
  }
  await rejectRecovery(terminal(), "{}");
});

Deno.test("CPM preserves both photos and all six roles even with equal bytes", async () => {
  const c = candidate();
  const content = JSON.parse(c.content_canonical);
  const second = structuredClone(content.photos[0]);
  second.ordinal = 1;
  const roles = ["source", "ai", "display"] as const;
  roles.forEach((role, i) => {
    second[role].reference_id = `00000000-0000-4000-8000-00000000010${i}`;
  });
  content.photos.push(second);
  c.content_canonical = initialCanonicalText(content);
  const a = assignment();
  a.candidate_digest = await initialCpmPhotoCandidateDigest(c);
  a.content_digest = await initialCpmPhotoContentDigest(content);
  a.preparation.role_mapping.push(
    ...roles.map((role, i) => ({
      photo_ordinal: 1,
      role,
      object_id: `00000000-0000-4000-8000-00000000030${i}`,
      declaration: second[role],
    })),
  );
  assertEquals(
    await validateInitialCpmPhotoAssignment(c, a),
    initialCanonicalText(a),
  );
  a.preparation.role_mapping.splice(3, 3);
  await assertRejects(
    () => validateInitialCpmPhotoAssignment(c, a),
    Error,
    "initial_analysis_input_invalid",
  );
});
