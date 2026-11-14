import { serveGeminiEdge } from "../_shared/ai/geminiDeployment.ts";
import { analyzeVideoRoute } from "./route.ts";
serveGeminiEdge(
  "analyze-observation-video",
  (req: Request) => analyzeVideoRoute(req),
);
