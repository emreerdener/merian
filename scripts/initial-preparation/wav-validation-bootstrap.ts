// Local synthetic profile only. No initial-admission or provider caller.
import {
  processWavBuffer,
  WavProcessingBudgetError,
} from "../../services/supabase/functions/_shared/audioProcessing.ts";
import {
  InitialWavStructureError,
  inspectInitialWavStructure,
} from "../../services/supabase/functions/_shared/initialAnalysis/wavValidation.ts";

export class WavPreparationRejection extends Error {
  constructor(readonly stage: "validation" | "transform") {
    super(stage);
  }
}

/** The transform is a trusted static dependency; JSON never selects a function.
 * A test spy proves invalid structure cannot reach it. */
export function validateAndTransformWav(
  source: Uint8Array<ArrayBuffer>,
  preserveSourceWhenTrimmedTooShort: boolean,
  transform: typeof processWavBuffer,
) {
  if (typeof preserveSourceWhenTrimmedTooShort !== "boolean") {
    throw new TypeError("fallback option must be boolean");
  }
  if (
    !(source instanceof Uint8Array) ||
    !(source.buffer instanceof ArrayBuffer) ||
    source.byteLength > 2_700_000
  ) throw new WavPreparationRejection("validation");
  const owned = new Uint8Array(source);
  try {
    inspectInitialWavStructure(owned);
  } catch (error) {
    if (error instanceof InitialWavStructureError) {
      throw new WavPreparationRejection("validation");
    }
    throw error;
  }
  try {
    const result = transform(
      owned.buffer,
      16_000,
      Object.freeze({ preserveSourceWhenTrimmedTooShort }),
    );
    return { source: owned, result };
  } catch (error) {
    if (
      error instanceof WavProcessingBudgetError ||
      (error instanceof Error && error.constructor === Error &&
        error.message ===
          "Audio too short to identify. Please record a longer clip.")
    ) throw new WavPreparationRejection("transform");
    throw error;
  }
}

async function main() {
  const buffer = new Uint8Array(262_145);
  let used = 0;
  for (;;) {
    const count = await Deno.stdin.read(buffer.subarray(used));
    if (count === null) break;
    used += count;
    if (used >= buffer.length) throw new Error("protocol");
  }
  const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true })
    .decode(
      buffer.subarray(0, used),
    );
  const input = JSON.parse(text);
  if (
    input === null || typeof input !== "object" || Array.isArray(input) ||
    Object.keys(input).sort().join(",") !==
      "base64,operation,preserve_source_when_trimmed_too_short,version" ||
    input.version !== 2 || input.operation !== "validated_wav16k" ||
    typeof input.base64 !== "string" || input.base64.length > 256_000 ||
    typeof input.preserve_source_when_trimmed_too_short !== "boolean"
  ) throw new Error("protocol");
  // Exact canonical spelling rejects duplicate keys, alternate number/string
  // spellings, whitespace and field order before any byte preparation.
  if (
    text !== JSON.stringify({
      version: 2,
      operation: "validated_wav16k",
      base64: input.base64,
      preserve_source_when_trimmed_too_short:
        input.preserve_source_when_trimmed_too_short,
    })
  ) throw new Error("protocol");
  const decoded = atob(input.base64);
  if (btoa(decoded) !== input.base64) throw new Error("protocol");
  const raw = Uint8Array.from(decoded, (c) => c.charCodeAt(0));
  const { source, result } = validateAndTransformWav(
    raw,
    input.preserve_source_when_trimmed_too_short,
    processWavBuffer,
  );
  const output = Uint8Array.from(
    atob(result.base64Audio),
    (c) => c.charCodeAt(0),
  );
  const digest = async (bytes: Uint8Array<ArrayBuffer>) =>
    Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
      (n) => n.toString(16).padStart(2, "0"),
    ).join("");
  console.log(JSON.stringify({
    version: 2,
    operation: "validated_wav16k",
    preserve_source_when_trimmed_too_short:
      input.preserve_source_when_trimmed_too_short,
    input_bytes: source.length,
    input_sha256: await digest(source),
    output_bytes: output.length,
    output_sha256: await digest(output),
    base64: result.base64Audio,
    complete: true,
  }));
}

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    if (error instanceof WavPreparationRejection) {
      console.error(JSON.stringify({
        version: 2,
        status: "rejected",
        stage: error.stage,
        transform_started: error.stage === "transform",
      }));
      Deno.exit(error.stage === "validation" ? 2 : 3);
    }
    // Protocol and unexpected failures never expose source or exception details.
    Deno.exit(1);
  }
}
