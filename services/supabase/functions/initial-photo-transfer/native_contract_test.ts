import { assertEquals, assertThrows } from "@std/assert";
import { parseTransferRequest } from "./contract.ts";
import candidate from "../_shared/initialAnalysis/fixtures/cpm-photo-candidate-v1.json" with {
  type: "json",
};

const nativeTests = new URL(
  "../../../../apps/ios/MerianTests/Core/Network/Transport/",
  import.meta.url,
);

Deno.test("native transfer golden bytes share the closed issue/status contract", async () => {
  const statusSource = await Deno.readTextFile(
    new URL("InitialPhotoTransferRequestTests.swift", nativeTests),
  );
  const candidateSource = await Deno.readTextFile(
    new URL("InitialPhotoAllocationRoleReplyTests.swift", nativeTests),
  );
  const statusText = statusSource.match(/static let statusGolden = #"(.*)"#/)
    ?.[1];
  const candidateText = candidateSource.match(/static let candidate = #"(.*)"#/)
    ?.[1];
  assertEquals(candidateText, candidate.canonical);
  const status = JSON.parse(statusText!);
  const parsed = parseTransferRequest(status);
  assertEquals(parsed.action, "status");
  assertEquals(parsed.allocation, null);
  for (let role = 0; role < 3; role++) {
    const object_id = `00000000-0000-4000-8000-00000000020${role}`;
    const issue = {
      ...status,
      action: "issue",
      object_id,
      candidate_canonical: candidateText,
    };
    const request = parseTransferRequest(issue);
    assertEquals(request.object, object_id);
    assertEquals(request.allocation?.candidateCanonical, candidateText);
    assertThrows(() =>
      parseTransferRequest({ ...issue, owner: status.scan_id })
    );
    assertThrows(() =>
      parseTransferRequest({ ...status, candidate_canonical: candidateText })
    );
  }
});
