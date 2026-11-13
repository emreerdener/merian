/** Local harness child. Synthetic input stays on stdin; output is counts/timing only. */
import { safeJpeg } from "../functions/_shared/analysisHistory/testing/publicPhotoFixtures.ts";
import { createCpmPhotoAdmissionRuntime } from "../functions/_shared/initialAnalysis/cpmPhotoAdmissionRuntime.ts";
import { fetchWithDeadline } from "../functions/_shared/outbound.ts";

if (Deno.args[0] === "fixture") {
  console.log(JSON.stringify(Array.from(safeJpeg())));
} else if (Deno.args[0] === "fixture-roster") {
  const roster = Array.from({ length: 6 }, (_, index) => {
    const jpeg = safeJpeg();
    if (jpeg[2] !== 0xff || jpeg[3] !== 0xdb || jpeg[7] !== 1) {
      throw new Error("fixture quantization table changed");
    }
    jpeg[7] = index + 1;
    return Array.from(jpeg);
  });
  console.log(JSON.stringify(roster));
} else {
  const input = JSON.parse(await new Response(Deno.stdin.readable).text());
  const base = new URL(input.base);
  if (base.hostname !== "127.0.0.1" || base.protocol !== "http:") {
    throw new Error("local only");
  }
  Deno.env.set("SUPABASE_URL", base.origin);
  Deno.env.set("SUPABASE_SERVER_API_KEY", "sb_secret_" + "x".repeat(40));
  let reads = 0;
  const runtime = await createCpmPhotoAdmissionRuntime(
    [input.policy],
    "a".repeat(64),
    {
      sign: (_profile, request) => Promise.resolve(request),
      fetch: (request, init) => {
        const original = request as Request;
        if (original.url !== input.paths[reads]) {
          throw new Error("unexpected storage target");
        }
        reads++;
        return fetchWithDeadline(new URL("/media", base), {
          ...init,
          signal: original.signal,
          redirect: "error",
        }, { timeoutMs: 5_000 });
      },
    },
  );
  const started = performance.now();
  const result = await runtime.admit(
    input.identity,
    new AbortController().signal,
  );
  const elapsed = performance.now() - started;
  if (result.outcome !== "admitted" || reads !== input.paths.length) {
    throw new Error("physical admission failed");
  }
  const recovered = await runtime.admit(
    input.identity,
    new AbortController().signal,
  );
  if (recovered.outcome !== "admitted" || reads !== input.paths.length) {
    throw new Error("recovery repeated reads");
  }
  console.log(
    JSON.stringify({ passed: true, media_reads: reads, admission_ms: elapsed }),
  );
}
