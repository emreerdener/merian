import { readInitialRecoveryHttp } from "../functions/check-scan-status/initialRecovery.ts";
import { createInitialSavedAdmissionAcquisition } from "../functions/_shared/initialAnalysis/resultStore.ts";
import { assertEquals } from "@std/assert";
import { decodeCpmCompletionAdmission } from "../functions/_shared/initialAnalysis/cpmCompletionAdmission.ts";
import { createCpmPhotoAdmissionDb } from "../functions/_shared/initialAnalysis/cpmPhotoAdmissionDb.ts";
const input = JSON.parse(await new Response(Deno.stdin.readable).text());
const result = await decodeCpmCompletionAdmission(input.reply, input.binding);
assertEquals(result.admission, input.expected);
// Fixed in-memory transport adapter only; never contact this synthetic host.
Deno.env.set("SUPABASE_URL", "https://trusted.invalid");
Deno.env.set("SUPABASE_SERVER_API_KEY", "sb_secret_" + "x".repeat(40));
let calls = 0;
const db = createCpmPhotoAdmissionDb("a".repeat(64), (url, init) => {
  calls++;
  assertEquals(
    String(url),
    "https://trusted.invalid/rest/v1/rpc/read_initial_cpm_completion_admission_v1",
  );
  assertEquals(JSON.parse(String(init?.body)), {
    p_owner: input.binding.owner_id,
    p_scan: input.binding.scan_id,
    p_candidate: input.binding.candidate_canonical,
    p_assignment: input.binding.assignment_canonical,
    p_assignment_digest: input.binding.assignment_digest,
    p_backend_generation: input.binding.backend_generation,
    p_backend_configuration_digest: input.binding.backend_configuration_digest,
  });
  return Promise.resolve(new Response(JSON.stringify(input.reply)));
});
assertEquals(
  await db.readCompletionAdmission(input.binding, new AbortController().signal),
  result,
);
assertEquals(calls, 1);
const assignment = JSON.parse(input.binding.assignment_canonical);
const saved = {
  owner_id: input.binding.owner_id,
  scan_id: input.binding.scan_id,
  candidate_canonical: input.binding.candidate_canonical,
  candidate_digest: assignment.candidate_digest,
  content_digest: assignment.content_digest,
  assignment_digest: input.binding.assignment_digest,
  backend_generation: input.binding.backend_generation,
  backend_configuration_digest: input.binding.backend_configuration_digest,
};
let savedCalls = 0;
const savedReader = await createInitialSavedAdmissionAcquisition({
  original: saved,
  authenticatedOwnerID: saved.owner_id,
  origin: "https://trusted.invalid",
  serverApiKey: "sb_secret_" + "x".repeat(40),
  fetcher: (url, init) => {
    savedCalls++;
    assertEquals(
      String(url),
      "https://trusted.invalid/rest/v1/rpc/read_initial_cpm_saved_admission_v1",
    );
    assertEquals(JSON.parse(String(init?.body)), {
      p_owner: saved.owner_id,
      p_scan: saved.scan_id,
      p_candidate: saved.candidate_canonical,
      p_candidate_digest: saved.candidate_digest,
      p_content_digest: saved.content_digest,
      p_assignment_digest: saved.assignment_digest,
      p_backend_generation: saved.backend_generation,
      p_backend_configuration_digest: saved.backend_configuration_digest,
    });
    return Promise.resolve(Response.json(input.saved_reply));
  },
});
assertEquals(await savedReader.read(new AbortController().signal), result);
assertEquals(savedCalls, 1);
let httpCalls = 0;
const response = await readInitialRecoveryHttp(
  new Request("https://trusted.invalid/check-scan-status", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-merian-initial-recovery": "admission-v1",
    },
    body: JSON.stringify({
      initial_recovery: { version: 1, phase: "admission", original: saved },
    }),
  }),
  saved.owner_id,
  {
    origin: "https://trusted.invalid",
    serverApiKey: "sb_secret_" + "x".repeat(40),
    fetcher: (url, init) => {
      httpCalls++;
      assertEquals(
        String(url),
        "https://trusted.invalid/rest/v1/rpc/read_initial_cpm_saved_admission_v1",
      );
      assertEquals(JSON.parse(String(init?.body)), {
        p_owner: saved.owner_id,
        p_scan: saved.scan_id,
        p_candidate: saved.candidate_canonical,
        p_candidate_digest: saved.candidate_digest,
        p_content_digest: saved.content_digest,
        p_assignment_digest: saved.assignment_digest,
        p_backend_generation: saved.backend_generation,
        p_backend_configuration_digest: saved.backend_configuration_digest,
      });
      return Promise.resolve(Response.json(input.saved_reply));
    },
  },
);
assertEquals(response.status, 200);
assertEquals(response.headers.get("cache-control"), "no-store");
assertEquals(await response.text(), result.canonical);
assertEquals(httpCalls, 1);
console.log(JSON.stringify({ passed: true }));
