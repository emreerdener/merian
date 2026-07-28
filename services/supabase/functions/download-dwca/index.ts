import {
  clientAddressFromHeaders,
  resolveClientAddressHashSecret,
} from "../_shared/clientAddress.ts";
import { serveEdge } from "../_shared/edgeHandler.ts";
import { publicErrorResponse } from "../_shared/http.ts";
import { requireServerApiKeyFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import {
  defaultDownloadDwcaDependencies,
  handleDownloadDwca,
} from "./handler.ts";

serveEdge(async (req: Request) => {
  try {
    const serverApiKey = requireServerApiKeyFromEnvironment();
    const hashSecret = resolveClientAddressHashSecret({
      dedicatedSecret: Deno.env.get("DWCA_DOWNLOAD_IP_HASH_SECRET"),
      platformSecretKey: serverApiKey,
    });
    const supabaseAdmin = createServiceRoleClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serverApiKey,
    );
    return await handleDownloadDwca(
      req,
      defaultDownloadDwcaDependencies(supabaseAdmin, hashSecret),
    );
  } catch (error) {
    console.error(JSON.stringify({
      event: "dwca_download_configuration_unavailable",
      client_address_available:
        clientAddressFromHeaders(req.headers) !== "unavailable",
      error: error instanceof Error ? error.name : typeof error,
      ts: new Date().toISOString(),
    }));
    return publicErrorResponse(
      req,
      503,
      "download_unavailable",
      "The download is temporarily unavailable.",
      { extraHeaders: { "Cache-Control": "private, no-store" } },
    );
  }
});
