// Local synthetic qualification adapter; never a hosted/provider entrypoint.
import { processWavBuffer } from "../../services/supabase/functions/_shared/audioProcessing.ts";
const buffer = new Uint8Array(262145);
let used = 0;
for (;;) {
  const count = await Deno.stdin.read(buffer.subarray(used));
  if (count === null) break;
  used += count;
  if (used >= buffer.length) throw new Error("input_limit");
}
const input = JSON.parse(
  new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, used)),
);
if (
  Object.keys(input).sort().join(",") !== "base64,operation,version" ||
  input.version !== 1 || !["identity", "wav16k"].includes(input.operation) ||
  typeof input.base64 !== "string" || input.base64.length > 256000
) throw new Error("protocol");
const raw = Uint8Array.from(atob(input.base64), (c) => c.charCodeAt(0));
let output: Uint8Array;
if (input.operation === "identity") {
  if (raw.length > 4096) throw new Error("identity_limit");
  output = raw;
} else {
  // Feasibility envelope: exactly canonical 1-second, mono PCM16 at 32kHz.
  const header = new DataView(raw.buffer);
  const tag = (offset: number) =>
    new TextDecoder().decode(raw.subarray(offset, offset + 4));
  if (
    raw.length !== 64044 || tag(0) !== "RIFF" ||
    header.getUint32(4, true) !== 64036 || tag(8) !== "WAVE" ||
    tag(12) !== "fmt " || header.getUint32(16, true) !== 16 ||
    header.getUint16(20, true) !== 1 || header.getUint16(22, true) !== 1 ||
    header.getUint32(24, true) !== 32000 ||
    header.getUint32(28, true) !== 64000 || header.getUint16(32, true) !== 2 ||
    header.getUint16(34, true) !== 16 || tag(36) !== "data" ||
    header.getUint32(40, true) !== 64000
  ) throw new Error("wav_envelope");
  const result = processWavBuffer(raw.buffer, 16000, {
    preserveSourceWhenTrimmedTooShort: false,
  });
  output = Uint8Array.from(atob(result.base64Audio), (c) => c.charCodeAt(0));
}
const digest = async (b: Uint8Array) =>
  Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(b))),
    (n) => n.toString(16).padStart(2, "0"),
  ).join("");
let encoded = "";
for (const b of output) encoded += String.fromCharCode(b);
console.log(JSON.stringify({
  version: 1,
  operation: input.operation,
  input_bytes: raw.length,
  input_sha256: await digest(raw),
  output_bytes: output.length,
  output_sha256: await digest(output),
  base64: btoa(encoded),
  complete: true,
}));
