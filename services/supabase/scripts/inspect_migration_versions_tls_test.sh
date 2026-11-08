#!/usr/bin/env bash
set -euo pipefail

tls_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tls_root="$(cd -- "$tls_script_dir/../../.." && pwd)"
tls_fixture="$(mktemp -d "${TMPDIR:-/tmp}/merian-inspection-tls.XXXXXX")"
trap 'rm -rf -- "$tls_fixture"' EXIT
cd "$tls_root"

# Ephemeral synthetic key only; never reads or changes a hosted credential.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=inspection.synthetic.test' \
  -addext 'subjectAltName=DNS:inspection.synthetic.test' \
  -keyout "$tls_fixture/key.pem" -out "$tls_fixture/cert.pem" \
  >/dev/null 2>&1

cat > "$tls_fixture/check.ts" <<'TS'
import { assertEquals } from "@std/assert";
import tls from "node:tls";

const { inspectionTls } = await import(Deno.args[0]);
const key = await Deno.readTextFile(Deno.args[1]);
const certificate = await Deno.readTextFile(Deno.args[2]);
const unrelatedCA = await Deno.readTextFile(Deno.args[3]);
for (const [label, ca, hostname, accepted] of [
  ["trusted CA and matching hostname", certificate, "inspection.synthetic.test", true],
  ["untrusted CA", unrelatedCA, "inspection.synthetic.test", false],
  ["wrong hostname", certificate, "wrong.synthetic.test", false],
] as const) {
  const sockets = new Set<tls.TLSSocket>();
  const server = tls.createServer({ key, cert: certificate }, (socket) => {
    sockets.add(socket);
    socket.on("error", () => {});
    socket.on("close", () => sockets.delete(socket));
  });
  server.on("tlsClientError", () => {});
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const port = (server.address() as { port: number }).port;
  let client: tls.TLSSocket | undefined;
  try {
    const result = await new Promise<string>((resolve) => {
      const timer = setTimeout(() => resolve("timeout"), 5000);
      const finish = (value: string) => { clearTimeout(timer); resolve(value); };
      client = tls.connect({ host: "127.0.0.1", port, servername: hostname, ...inspectionTls(ca) });
      client.once("secureConnect", () => finish(client?.authorized ? "accepted" : "unauthorized"));
      client.once("error", (error: Error & { code?: string }) => finish(error.code ?? "unknown_error"));
    });
    if (accepted) assertEquals(result, "accepted", label);
    else if (hostname === "wrong.synthetic.test") assertEquals(result, "ERR_TLS_CERT_ALTNAME_INVALID", label);
    else assertEquals(["DEPTH_ZERO_SELF_SIGNED_CERT", "SELF_SIGNED_CERT_IN_CHAIN"].includes(result), true, label);
  } finally {
    client?.destroy();
    for (const socket of sockets) socket.destroy();
    await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
  console.log(`PASS: ${label}`);
}
TS

deno run --check --frozen --no-prompt \
  --config services/supabase/functions/deno.json \
  --allow-net=127.0.0.1 --allow-env=PG* \
  --allow-read="$tls_fixture,$tls_script_dir" \
  "$tls_fixture/check.ts" \
  "file://$tls_script_dir/inspect_migration_versions.ts" \
  "$tls_fixture/key.pem" "$tls_fixture/cert.pem" \
  "$tls_script_dir/certificates/supabase-prod-ca-2021.crt"
