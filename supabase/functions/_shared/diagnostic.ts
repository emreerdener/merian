import {
  GoogleGenerativeAI,
  SchemaType,
  ResponseSchema,
} from "https://esm.sh/@google/generative-ai@0.24.1";

export async function fetchDiagnosticComparison(
  scientificName: string,
  genAI: GoogleGenerativeAI,
) {
  const model = genAI.getGenerativeModel({
    model: "gemini-2.5-flash",
    systemInstruction:
      "You are a world-class biologist. Given a species scientific name, return a brief diagnostic comparison explaining the primary identification rationale, the most commonly confused lookalike species, and the key morphological or behavioural features that differentiate them.",
    generationConfig: { temperature: 0.1, maxOutputTokens: 400 },
  });

  const schema: Record<string, unknown> = {
    type: SchemaType.OBJECT,
    properties: {
      primary_match_rationale: { type: SchemaType.STRING },
      confusing_lookalike_name: { type: SchemaType.STRING },
      key_differentiators: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        description: "2–4 concise differentiating features vs. the lookalike.",
      },
    },
    required: [
      "primary_match_rationale",
      "confusing_lookalike_name",
      "key_differentiators",
    ],
  };

  try {
    const result = await model.generateContent({
      contents: [
        {
          role: "user",
          parts: [{ text: `Diagnostic comparison for: ${scientificName}` }],
        },
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: schema as unknown as ResponseSchema,
      },
    });
    const text = result.response.text();
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start === -1 || end === -1) throw new Error("Malformed response");
    return JSON.parse(text.substring(start, end + 1)) as {
      primary_match_rationale: string;
      confusing_lookalike_name: string;
      key_differentiators: string[];
    };
  } catch (e) {
    console.error("fetchDiagnosticComparison failed:", e);
    return null;
  }
}
