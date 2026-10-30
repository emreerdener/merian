import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  parseAllocationRequest,
  projectAllocationReceipt,
} from "./contract.ts";
import { allocated, create, status } from "./fixtures.ts";
import golden from "./role-projection-v2-fixture.json" with { type: "json" };
import assignment from "../_shared/initialAnalysis/fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};
import { validateInitialCpmPhotoBoundRecovery } from "../_shared/initialAnalysis/cpmPhotoBoundRecovery.ts";

export const bound = () => ({
  ...allocated(),
  version: 3,
  backend_generation: assignment.assignment.preparation.backend_generation,
  backend_configuration_digest: "c".repeat(64),
});

Deno.test("v3 binds create and status to the original assignment with no configuration contents", async () => {
  for (const body of [create(), status(), status(assignment.digest)]) {
    const reply = await projectAllocationReceipt(
      parseAllocationRequest({ ...body, version: 3 }),
      bound(),
    );
    assertEquals(reply, {
      ...golden,
      version: 3,
      backend_generation: bound().backend_generation,
      backend_configuration_digest: bound().backend_configuration_digest,
    });
    assertEquals(
      new TextEncoder().encode(JSON.stringify(reply)).length <= 2048,
      true,
    );
    for (const version of [1, 2]) {
      await assertRejects(() =>
        projectAllocationReceipt(
          parseAllocationRequest({ ...body, version }),
          bound(),
        )
      );
    }
  }
});

Deno.test("v3 rejects absent, malformed, foreign-generation and caller-selected backend metadata", async () => {
  const request = parseAllocationRequest({ ...create(), version: 3 });
  for (
    const reply of [
      allocated(),
      {
        ...bound(),
        backend_generation: "00000000-0000-4000-8000-999999999999",
      },
      { ...bound(), backend_configuration_digest: "C".repeat(64) },
      { ...bound(), backend_configuration_digest: null },
      { ...bound(), assignment_digest: "0".repeat(64) },
      { ...bound(), endpoint: "https://invalid.example" },
    ]
  ) {
    await assertRejects(() => projectAllocationReceipt(request, reply));
  }
  for (
    const body of [{
      ...create(),
      version: 3,
      backend_generation: bound().backend_generation,
    }, {
      ...status(),
      version: 3,
      backend_configuration_digest: bound().backend_configuration_digest,
    }]
  ) {
    assertThrows(() => parseAllocationRequest(body));
  }
});

Deno.test("v3 holds expose no tuple and cannot smuggle authority or allocation fields", async () => {
  const request = parseAllocationRequest({
    ...status(assignment.digest),
    version: 3,
  });
  for (const reason of ["not_found", "expired", "cancelled"]) {
    const held = {
      version: 1,
      variant: "client_prepared_photo",
      outcome: "terminal_held",
      authority: "none",
      scan_id: golden.scan_id,
      reason,
    };
    const reply = await projectAllocationReceipt(request, held) as Record<
      string,
      unknown
    >;
    assertEquals(reply.version, 3);
    assertEquals("backend_generation" in reply, false);
    assertEquals("role_mapping" in reply, false);
    for (
      const altered of [
        { ...held, backend_generation: bound().backend_generation },
        { ...held, authority: "upload" },
        { ...held, version: 3 },
      ]
    ) {
      await assertRejects(() => projectAllocationReceipt(request, altered));
    }
  }
});

Deno.test("v3 freezes tuple before digest awaits and retains exact saved assignment validation", async () => {
  const reply = bound();
  const pending = projectAllocationReceipt(
    parseAllocationRequest({ ...create(), version: 3 }),
    reply,
  );
  reply.backend_configuration_digest = "e".repeat(64);
  assertEquals(
    (await pending as Record<string, unknown>).backend_configuration_digest,
    "c".repeat(64),
  );
  await assertRejects(() =>
    validateInitialCpmPhotoBoundRecovery(
      JSON.parse(create().candidate_canonical),
      bound(),
      "{}",
    )
  );
});
