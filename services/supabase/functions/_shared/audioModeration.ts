const TRANSCRIPTION_MODEL = "gpt-4o-mini-transcribe";
const MODERATION_MODEL = "omni-moderation-latest";
const MAX_AUDIO_BYTES = 12 * 1024 * 1024;

export interface AudioModerationDecision {
  approved: boolean;
  model: string;
}

async function fetchBoundedAudio(url: string): Promise<Blob> {
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(url);
  } catch {
    throw new Error("Audio moderation URL is invalid.");
  }
  if (
    parsedUrl.protocol !== "https:" || parsedUrl.hostname !== "media.merian.app"
  ) {
    throw new Error("Audio moderation URL is not an approved Merian media URL.");
  }
  const response = await fetch(parsedUrl);
  if (!response.ok) {
    throw new Error(`Audio fetch failed with status ${response.status}.`);
  }
  const readResult = await readResponseArrayBufferWithinBudget(
    response,
    MAX_AUDIO_BYTES,
    "Audio exceeds the moderation byte limit.",
  );
  const bytes = readResult.buffer;
  if (readResult.error || !bytes || bytes.byteLength === 0) {
    throw new Error("Audio is empty or exceeds the moderation byte limit.");
  }
  return new Blob([bytes], {
    type: response.headers.get("content-type") ?? "audio/wav",
  });
}

async function transcribeAudio(audio: Blob, apiKey: string): Promise<string> {
  const form = new FormData();
  form.append("model", TRANSCRIPTION_MODEL);
  form.append("file", audio, "scan-audio.wav");
  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });
  if (!response.ok) {
    throw new Error(`Audio transcription failed with status ${response.status}.`);
  }
  const payload = await response.json() as { text?: unknown };
  return typeof payload.text === "string" ? payload.text.trim() : "";
}

async function transcriptIsFlagged(
  transcript: string,
  apiKey: string,
): Promise<boolean> {
  if (transcript.length === 0) return false;
  const response = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: MODERATION_MODEL, input: transcript }),
  });
  if (!response.ok) {
    throw new Error(`Transcript moderation failed with status ${response.status}.`);
  }
  const payload = await response.json() as {
    results?: Array<{ flagged?: unknown }>;
  };
  if (!Array.isArray(payload.results) || payload.results.length !== 1) {
    throw new Error("Transcript moderation returned an invalid response.");
  }
  return payload.results[0]?.flagged === true;
}

export async function moderateExploreAudioUrl(
  url: string,
): Promise<AudioModerationDecision> {
  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
  if (!apiKey) throw new Error("OPENAI_API_KEY is not configured.");
  const audio = await fetchBoundedAudio(url);
  const transcript = await transcribeAudio(audio, apiKey);
  return {
    approved: !(await transcriptIsFlagged(transcript, apiKey)),
    model: `${TRANSCRIPTION_MODEL}+${MODERATION_MODEL}`,
  };
}
import { readResponseArrayBufferWithinBudget } from "./mediaBudgets.ts";
