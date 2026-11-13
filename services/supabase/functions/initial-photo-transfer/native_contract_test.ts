import { assertEquals, assertThrows } from "@std/assert";
import { parseTransferRequest } from "./contract.ts";
import candidate from "../_shared/initialAnalysis/fixtures/cpm-photo-candidate-v1.json" with {
  type: "json",
};

const nativeFixture = new URL(
  "../../../../apps/ios/TestSupport/InitialPhotoTransferFixtures.json",
  import.meta.url,
);

Deno.test("native transfer golden bytes share the closed issue/status contract", async () => {
  const fixture = JSON.parse(await Deno.readTextFile(nativeFixture));
  assertEquals(Object.keys(fixture).sort(), [
    "candidate_canonical",
    "status_canonical",
    "version",
  ]);
  assertEquals(fixture.version, 1);
  const statusText = fixture.status_canonical;
  const candidateText = fixture.candidate_canonical;
  assertEquals(candidateText, candidate.canonical);
  const status = JSON.parse(statusText);
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
