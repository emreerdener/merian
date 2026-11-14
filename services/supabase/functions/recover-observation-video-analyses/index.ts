import { serveGeminiEdge } from "../_shared/ai/geminiDeployment.ts";
import { recoverVideoRoute } from "./route.ts";
serveGeminiEdge("recover-observation-video-analyses", recoverVideoRoute);
