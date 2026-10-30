import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  ALLOCATION_REPLY_LIMIT,
  parseAllocationRequest,
  projectAllocationReceipt,
} from "./contract.ts";
import { allocated, create, status } from "./fixtures.ts";
import golden from "./role-projection-v2-fixture.json" with { type: "json" };
import saved from "../_shared/initialAnalysis/fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};
import { initialCanonicalText } from "../_shared/initialAnalysis/canonical.ts";
import { initialCpmPhotoCandidateDigest } from "../_shared/initialAnalysis/cpmPhotoCandidate.ts";
import { initialCpmPhotoContentDigest } from "../_shared/initialAnalysis/cpmPhotoContent.ts";
import { initialCpmPhotoAssignmentDigest } from "../_shared/initialAnalysis/cpmPhotoAssignment.ts";

Deno.test("v2 projects the complete golden mapping while v1 remains byte-shape compatible", async () => {
  for (const body of [create(), status(), status(saved.digest)]) {
    assertEquals(
      await projectAllocationReceipt(
        parseAllocationRequest({ ...body, version: 2 }),
        allocated(),
      ),
      golden,
    );
    const legacy = await projectAllocationReceipt(
      parseAllocationRequest(body),
      allocated(),
    ) as Record<string, unknown>;
    assertEquals(legacy.version, 1);
    assertEquals("role_mapping" in legacy, false);
  }
});

Deno.test("v2 maximum six distinct destinations fit the unchanged reply bound with equal bytes", async () => {
  const c = JSON.parse(create().candidate_canonical);
  const content = JSON.parse(c.content_canonical);
  const second = structuredClone(content.photos[0]);
  second.ordinal = 1;
  const roles = ["source", "ai", "display"] as const;
  roles.forEach((role, i) => {
    second[role].reference_id = `00000000-0000-4000-8000-00000000010${i}`;
  });
  content.photos.push(second);
  c.content_canonical = initialCanonicalText(content);
  const a = structuredClone(saved.assignment);
  a.created_at_ms = 8639999998200000;
  a.expires_at_ms = 8640000000000000;
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
  const digest = await initialCpmPhotoAssignmentDigest(c, a);
  const reply = await projectAllocationReceipt(
    parseAllocationRequest({
      version: 2,
      action: "status",
      candidate_canonical: initialCanonicalText(c),
      saved_assignment_digest: digest,
    }),
    {
      ...allocated(),
      assignment_canonical: initialCanonicalText(a),
      assignment_digest: digest,
    },
  ) as typeof golden;
  assertEquals(reply.role_mapping.length, 6);
  assertEquals(new Set(reply.role_mapping.map((m) => m.object_id)).size, 6);
  assertEquals(reply.role_mapping.map((m) => m.role), [...roles, ...roles]);
  assertEquals(reply.role_mapping.map((m) => m.photo_ordinal), [
    0,
    0,
    0,
    1,
    1,
    1,
  ]);
  assert(
    new TextEncoder().encode(JSON.stringify(reply)).length <=
      ALLOCATION_REPLY_LIMIT,
  );
  assertEquals(ALLOCATION_REPLY_LIMIT, 2048);
  assertEquals(Object.keys(reply.role_mapping[0]).sort(), [
    "object_id",
    "photo_ordinal",
    "reference_id",
    "role",
  ]);
});

Deno.test("v3 maximum six distinct destinations and backend tuple fit the unchanged reply bound", async () => {
  const c = JSON.parse(create().candidate_canonical);
  const content = JSON.parse(c.content_canonical);
  const second = structuredClone(content.photos[0]);
  second.ordinal = 1;
  const roles = ["source", "ai", "display"] as const;
  roles.forEach((role, i) => {
    second[role].reference_id = `00000000-0000-4000-8000-00000000010${i}`;
  });
  content.photos.push(second);
  c.content_canonical = initialCanonicalText(content);
  const a = structuredClone(saved.assignment);
  a.created_at_ms = 8639999998200000;
  a.expires_at_ms = 8640000000000000;
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
  const digest = await initialCpmPhotoAssignmentDigest(c, a);
  const reply = await projectAllocationReceipt(
    parseAllocationRequest({
      version: 3,
      action: "status",
      candidate_canonical: initialCanonicalText(c),
      saved_assignment_digest: digest,
    }),
    {
      ...allocated(),
      version: 3,
      backend_generation: a.preparation.backend_generation,
      backend_configuration_digest: "f".repeat(64),
      assignment_canonical: initialCanonicalText(a),
      assignment_digest: digest,
    },
  ) as typeof golden;
  assertEquals(reply.role_mapping.length, 6);
  assertEquals(new Set(reply.role_mapping.map((m) => m.object_id)).size, 6);
  assertEquals(reply.role_mapping.map((m) => m.role), [...roles, ...roles]);
  assertEquals(reply.role_mapping.map((m) => m.photo_ordinal), [
    0,
    0,
    0,
    1,
    1,
    1,
  ]);
  assert(
    new TextEncoder().encode(JSON.stringify(reply)).length <=
      ALLOCATION_REPLY_LIMIT,
  );
  assertEquals(ALLOCATION_REPLY_LIMIT, 2048);
  assertEquals(Object.keys(reply.role_mapping[0]).sort(), [
    "object_id",
    "photo_ordinal",
    "reference_id",
    "role",
  ]);
});

Deno.test("v2 refuses caller roles and private assignment mutations before projection", async () => {
  for (
    const body of [
      { ...create(), version: 2, role_mapping: golden.role_mapping },
      { ...status(), version: 2, object_id: golden.role_mapping[0].object_id },
      { ...create(), version: true },
      { ...create(), version: 4 },
    ]
  ) {
    assertThrows(() => parseAllocationRequest(body));
  }
  for (
    const mutate of [
      (a: typeof saved.assignment) => {
        a.preparation.role_mapping.reverse();
      },
      (a: typeof saved.assignment) => {
        a.preparation.role_mapping[1].object_id =
          a.preparation.role_mapping[0].object_id;
      },
      (a: typeof saved.assignment) => {
        a.preparation.role_mapping[0].declaration.reference_id = a.scan_id;
      },
    ]
  ) {
    const a = structuredClone(saved.assignment);
    mutate(a);
    await assertRejects(() =>
      projectAllocationReceipt(
        parseAllocationRequest({ ...status(saved.digest), version: 2 }),
        { ...allocated(), assignment_canonical: initialCanonicalText(a) },
      )
    );
  }
});

Deno.test("v2 terminal holds never contain mappings or imply closure", async () => {
  for (const reason of ["not_found", "expired", "cancelled"]) {
    const reply = await projectAllocationReceipt(
      parseAllocationRequest({ ...status(saved.digest), version: 2 }),
      {
        version: 1,
        variant: "client_prepared_photo",
        outcome: "terminal_held",
        authority: "none",
        scan_id: saved.assignment.scan_id,
        reason,
      },
    ) as Record<string, unknown>;
    assertEquals(reply.version, 2);
    assertEquals(reply.authority, "none");
    assertEquals(reply.reason, reason);
    assertEquals("role_mapping" in reply, false);
  }
});
