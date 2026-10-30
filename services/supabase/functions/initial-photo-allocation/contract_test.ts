import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import assignment from "../_shared/initialAnalysis/fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};
import {
  parseAllocationRequest,
  projectAllocationReceipt,
} from "./contract.ts";

import { allocated, create, status } from "./fixtures.ts";

Deno.test("photo allocation projects exact create and recovered assignment without private configuration", async () => {
  for (const body of [create(), status(), status(assignment.digest)]) {
    assertEquals(
      await projectAllocationReceipt(parseAllocationRequest(body), allocated()),
      {
        version: 1,
        variant: "client_prepared_photo",
        outcome: "allocated",
        authority: "none",
        scan_id: assignment.assignment.scan_id,
        package_id: assignment.assignment.package_id,
        candidate_digest: assignment.assignment.candidate_digest,
        content_digest: assignment.assignment.content_digest,
        assignment_digest: assignment.digest,
        created_at_ms: assignment.assignment.created_at_ms,
        expires_at_ms: assignment.assignment.expires_at_ms,
      },
    );
  }
});
Deno.test("photo allocation closed requests reject spoofing, noncanonical candidate and recovery drift", async () => {
  for (
    const body of [
      { ...create(), owner_id: assignment.assignment.scan_id },
      { ...create(), action: "retry" },
      { ...create(), saved_assignment_digest: null },
      { ...status(), saved_assignment_digest: "bad" },
      { ...create(), candidate_canonical: " " + create().candidate_canonical },
      { ...create(), candidate_canonical: "x".repeat(1048577) },
      { ...create(), version: 4 },
    ]
  ) assertThrows(() => parseAllocationRequest(body));
  for (
    const reply of [{ ...allocated(), assignment_digest: "0".repeat(64) }, {
      ...allocated(),
      upload_url: "https://invalid.example",
    }, {
      ...allocated(),
      assignment_canonical: assignment.canonical.replace(
        '"created_at_ms":',
        '"private":1,"created_at_ms":',
      ),
    }, null]
  ) {
    await assertRejects(() =>
      projectAllocationReceipt(parseAllocationRequest(create()), reply)
    );
  }
  await assertRejects(() =>
    projectAllocationReceipt(
      parseAllocationRequest(status("0".repeat(64))),
      allocated(),
    )
  );
});
Deno.test("photo terminal receipts retain original request association without release authority", async () => {
  for (const reason of ["not_found", "expired", "cancelled"]) {
    const receipt = await projectAllocationReceipt(
      parseAllocationRequest(status(assignment.digest)),
      {
        version: 1,
        variant: "client_prepared_photo",
        outcome: "terminal_held",
        authority: "none",
        scan_id: assignment.assignment.scan_id,
        reason,
      },
    );
    assertEquals(receipt, {
      version: 1,
      variant: "client_prepared_photo",
      outcome: "terminal_held",
      authority: "none",
      scan_id: assignment.assignment.scan_id,
      package_id: assignment.assignment.package_id,
      candidate_digest: assignment.assignment.candidate_digest,
      content_digest: assignment.assignment.content_digest,
      reason,
    });
  }
});
Deno.test("photo request and reply snapshots survive caller mutation across digest awaits", async () => {
  const body = create(),
    request = parseAllocationRequest(body),
    reply = allocated();
  body.candidate_canonical = "{}";
  const pending = projectAllocationReceipt(request, reply);
  reply.assignment_canonical = "{}";
  assertEquals(
    await pending,
    await projectAllocationReceipt(
      parseAllocationRequest(create()),
      allocated(),
    ),
  );
});
