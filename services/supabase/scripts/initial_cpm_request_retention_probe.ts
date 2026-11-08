/** Local physical result-to-completion fixture only. Every source must map to
 * the exact assigned role; all bytes and current-state reads stay on loopback. */
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import { verifyInitialCpmRetention } from "../functions/_shared/initialAnalysis/cpmPhotoRetention.ts";
import { readInitialStream } from "../functions/_shared/initialAnalysis/transport.ts";
import { fetchWithDeadline } from "../functions/_shared/outbound.ts";
const caller = AbortSignal.timeout(45000);
const input = JSON.parse(
  new TextDecoder().decode(
    await readInitialStream(Deno.stdin.readable, 262144, caller),
  ),
);
const base = new URL(input.base);
if (
  base.protocol !== "http:" || base.hostname !== "127.0.0.1" ||
  base.href !== base.origin + "/" || !base.port
) throw new Error("local only");
const original = input.terminal;
let reads = 0, currentChecks = 0;
const proof = await verifyInitialCpmRetention(
  {
    load: () =>
      Promise.resolve({
        retention_policy_digest: original.binding.retention_policy_digest,
        retention_build_digest: original.binding.retention_build_digest,
        photo: input.policy,
      }),
    requireCurrent: async (_snapshot, signal) => {
      const r = await fetchWithDeadline(new URL("/current", base), {
        method: "GET",
        signal,
        redirect: "error",
      }, { timeoutMs: 5000 });
      const bytes = await readInitialStream(r.body, 262144, signal);
      if (
        r.status !== 200 ||
        initialCanonicalText(JSON.parse(new TextDecoder().decode(bytes))) !==
          initialCanonicalText(original)
      ) throw new Error("stale original");
      currentChecks++;
    },
    storage: {
      sign: (_profile, request) => Promise.resolve(request),
      fetch: (resource, init) => {
        const request = resource as Request;
        if (
          request.method !== "GET" || request.url !== input.paths[reads]
        ) throw new Error("wrong original object");
        return fetchWithDeadline(new URL("/objects/" + reads++, base), {
          ...init,
          redirect: "error",
        }, { timeoutMs: 5000 });
      },
    },
  },
  original,
  caller,
);
if (reads !== input.paths.length || reads !== 6) {
  throw new Error("incomplete retained roster");
}
console.log(JSON.stringify({ proof, reads, currentChecks }));
