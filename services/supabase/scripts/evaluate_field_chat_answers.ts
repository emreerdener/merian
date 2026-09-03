import { extractFieldChatReplyJson } from "../functions/_shared/fieldChatReply.ts";
import {
  buildFieldChatAnswerCases,
  type FieldChatAnswerCase,
} from "./field_chat_answer_cases.ts";

// This is a bounded behavior smoke check, not a factual-accuracy judge.
export function assessFieldChatAnswer(
  expectation: FieldChatAnswerCase["expectation"],
  value: unknown,
): string[] {
  if (!value || typeof value !== "object") return ["invalid_reply"];
  const reply = value as Record<string, unknown>;
  if (
    typeof reply.answer !== "string" || !reply.answer.trim() ||
    reply.answer.length > 4000 || typeof reply.is_refusal !== "boolean" ||
    !(reply.refusal_reason === null || typeof reply.refusal_reason === "string")
  ) return ["invalid_reply"];

  const answer = reply.answer.trim();
  const failures: string[] = [];
  if (reply.is_refusal || reply.refusal_reason !== null) {
    failures.push("unnecessary_refusal");
  }
  if (/\blavender|lavandula\b/i.test(answer)) {
    failures.push("example_species_leaked");
  }
  if (!/\b(?:smell|scent|fragranc|fragrant|unscented)/i.test(answer)) {
    failures.push("fragrance_not_addressed");
  }
  if (expectation === "general") {
    if (
      /\b(?:saved (?:scan|record|context)|scan (?:context|metadata)|dictionary|species overview|initial observation|not (?:captured|recorded|included))\b/i
        .test(answer)
    ) failures.push("record_missing_deflection");
    if (
      !/\b(?:unscented|scentless|non[- ]fragrant|not(?:\s+\w+){0,4}\s+fragrant|(?:little|no|faint)(?:\s+\w+){0,4}\s+(?:scent|fragrance)|lack(?:s)?(?:\s+\w+){0,3}\s+(?:scent|fragrance))\b/i
        .test(answer)
    ) failures.push("typical_fragrance_not_explained");
  } else if (
    !/\b(?:cannot|can['’]t|couldn['’]t|don['’]t know|unable|not possible|no way|not enough)\b/i
      .test(answer)
  ) {
    failures.push("individual_scent_not_known");
  }
  return failures;
}

export async function evaluateFieldChatAnswers(
  cases: FieldChatAnswerCase[],
  generate: (request: FieldChatAnswerCase["request"]) => Promise<{
    text?: string;
  }>,
  report: (result: { id: string; failures: string[] }) => void,
): Promise<boolean> {
  let passed = true;
  for (const testCase of cases) {
    let failures: string[];
    try {
      const result = await generate(testCase.request);
      failures = assessFieldChatAnswer(
        testCase.expectation,
        extractFieldChatReplyJson<unknown>(result.text ?? ""),
      );
    } catch {
      // Never print provider diagnostics, response bodies, or credentials.
      report({ id: testCase.id, failures: ["provider_or_parse_error"] });
      return false;
    }
    report({ id: testCase.id, failures });
    if (failures.length > 0) passed = false;
  }
  return passed;
}

if (import.meta.main) {
  if (Deno.args.length !== 1 || Deno.args[0] !== "--live") {
    console.error(
      "Not run. Pass --live to make nine paid Gemini calls with synthetic context only.",
    );
    Deno.exit(2);
  }
  if (!Deno.env.get("GEMINI_PAID_API_KEY")?.trim()) {
    console.error(
      "Not run: GEMINI_PAID_API_KEY is unavailable. Configure the approved test key outside chat; no provider requests were made.",
    );
    Deno.exit(2);
  }
  const { _genAI } = await import("../functions/_shared/gemini.ts");
  const passed = await evaluateFieldChatAnswers(
    buildFieldChatAnswerCases(),
    (request) => _genAI.models.generateContent(request),
    (result) => console.log(JSON.stringify(result)),
  );
  Deno.exit(passed ? 0 : 1);
}
