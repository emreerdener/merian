import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import {
  type CapturePromotionTransfer,
  createCapturePromotionDb,
} from "../_shared/capturePromotionDb.ts";
import { captureObjectBackendDigest } from "../_shared/captureObjectRetirement.ts";

const databaseURL = Deno.env.get("SUPABASE_DB_TEST_URL");
// Real service-role SQL plus the fixed production adapter and synthetic storage.
// Rollback-bound fixture/shim: not PostgREST auth, hosted S3 or commit/crash proof.
for (
  const mode of [
    "acknowledged",
    "lost_write",
    "lost_receipt",
    "retired",
    "mismatch",
  ] as const
) {
  Deno.test({
    name: `capture composition service SQL and storage recovery: ${mode}`,
    ignore: !databaseURL,
    async fn() {
      assert(databaseURL);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseURL).hostname,
        ),
      );
      const db = new Client(databaseURL);
      const names = ["SUPABASE_URL", "SUPABASE_SERVER_API_KEY"];
      const saved = names.map((n) => Deno.env.get(n));
      const bytes = new Uint8Array([1, 2, 3, 4]);
      const hash = [
        ...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
      ].map((v) => v.toString(16).padStart(2, "0")).join("");
      const backend = {
        endpoint: "https://storage.invalid",
        bucketName: "synthetic",
      };
      const owner = crypto.randomUUID(),
        scan = crypto.randomUUID(),
        operation = crypto.randomUUID();
      const binding = {
        operationId: operation,
        ownerId: owner,
        scanId: scan,
        assetId: crypto.randomUUID(),
        sessionId: crypto.randomUUID(),
        backendSHA256: await captureObjectBackendDigest(backend),
        sourceKey: `staging/${owner}/fixture.webp`,
        destinationKey:
          `public_uploads/free/${owner}/capture-promotion-${operation}`,
        contentType: "image/webp",
        byteCount: bytes.length,
        sha256: hash,
      };
      await db.connect();
      try {
        await db.queryArray("BEGIN");
        await db.queryArray("SET LOCAL statement_timeout='10s'");
        await db.queryArray(
          "SELECT set_config('request.jwt.claim.role','service_role',true)",
        );
        await db.queryArray(
          "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
          [owner],
        );
        await db.queryArray(
          "INSERT INTO public.scan_media_assets(id,user_id,client_scan_id,upload_session_id,kind,role,status,source,storage_key,order_index,content_type,byte_size,checksum_sha256) VALUES($1,$2,$3,$4,'image','display','staged','capture_upload',$5,0,$6,$7,$8)",
          [
            binding.assetId,
            owner,
            scan,
            binding.sessionId,
            binding.sourceKey,
            binding.contentType,
            bytes.length,
            hash,
          ],
        );
        await db.queryArray(
          "SELECT public.register_capture_upload_capabilities($1,$2,jsonb_build_array(jsonb_build_object('object_key',$3::text,'expires_at',clock_timestamp()+interval '1 hour','scan_id',$4::uuid,'asset_id',$5::uuid,'session_id',$6::uuid)))",
          [
            owner,
            binding.backendSHA256,
            binding.sourceKey,
            scan,
            binding.assetId,
            binding.sessionId,
          ],
        );
        await db.queryArray(
          "SELECT public.begin_scan_ingestion($1,$2,'identify-multimodal',$3,$4,$5,$6)",
          [
            scan,
            owner,
            {
              schemaVersion: 1,
              clientScanId: scan,
              media: {
                r2ObjectKeys: [binding.sourceKey],
                audioR2ObjectKeys: [],
                videoR2ObjectKeys: [],
              },
            },
            { image_count: 1, audio_count: 0, video_count: 0 },
            { image: [binding.sourceKey], audio: [], video: [] },
            [binding.sourceKey],
          ],
        );
        const projection = await db.queryObject<
          { manifest: string; request: string }
        >(
          "SELECT j.manifest_checksum AS manifest,i.payload_checksum AS request FROM public.scan_ingestion_jobs j JOIN public.scan_ingestion_intents i ON i.user_id=j.user_id AND i.scan_id=j.scan_id WHERE j.user_id=$1 AND j.scan_id=$2",
          [owner, scan],
        );
        const input: CapturePromotionTransfer = {
          cohortId: crypto.randomUUID(),
          operationId: operation,
          manifestSHA256: projection.rows[0].manifest,
          requestSHA256: projection.rows[0].request,
          bindings: [binding],
        };
        await db.queryArray("SET LOCAL ROLE service_role");
        const calls: string[] = [];
        let lostReceipt = false;
        Deno.env.set(names[0], "https://database.invalid");
        Deno.env.set(names[1], "sb_secret_" + "x".repeat(40));
        const adapter = createCapturePromotionDb(async (url, init) => {
          assertEquals(new URL(String(url)).origin, "https://database.invalid");
          assertEquals(init?.method, "POST");
          assertEquals(init?.redirect, "error");
          assertEquals(
            new Headers(init?.headers).get("apikey"),
            "sb_secret_" + "x".repeat(40),
          );
          const name = String(url).split("/").at(-1)!;
          calls.push(name);
          const a = JSON.parse(String(init?.body));
          let sql: string, args: unknown[];
          switch (name) {
            case "register_capture_promotion_ingestion":
              sql =
                "SELECT public.register_capture_promotion_ingestion($1,$2,$3,$4) AS result";
              args = [
                a.p_cohort,
                a.p_manifest,
                a.p_request,
                JSON.stringify(a.p_bindings),
              ];
              break;
            case "authorize_capture_promotion_action":
              sql =
                "SELECT public.authorize_capture_promotion_action($1,$2) AS result";
              args = [a.p_binding, a.p_action];
              break;
            case "authorize_capture_promotion_recovery":
              sql =
                "SELECT public.authorize_capture_promotion_recovery($1) AS result";
              args = [a.p_binding];
              break;
            case "record_capture_promotion_verification":
              sql =
                "SELECT public.record_capture_promotion_verification($1,$2) AS result";
              args = [a.p_binding, a.p_origin];
              break;
            default:
              throw new Error("unexpected synthetic RPC");
          }
          await db.queryArray("SAVEPOINT rpc");
          let result: unknown;
          try {
            result =
              (await db.queryObject<{ result: unknown }>(sql, args)).rows[0]
                .result;
          } catch {
            await db.queryArray("ROLLBACK TO SAVEPOINT rpc");
            await db.queryArray("RELEASE SAVEPOINT rpc");
            return new Response(null, { status: 500 });
          }
          await db.queryArray("RELEASE SAVEPOINT rpc");
          if (
            mode === "lost_receipt" &&
            name === "record_capture_promotion_verification" && !lostReceipt
          ) {
            lostReceipt = true;
            throw new Error("synthetic lost receipt reply");
          }
          return new Response(JSON.stringify(result), {
            headers: { "Content-Type": "application/json" },
          });
        });
        let target: Uint8Array | null = null,
          puts = 0,
          sourceReads = 0,
          destinationReads = 0;
        let removed = false;
        const storage = {
          backend,
          sign: (request: Request) => Promise.resolve(request),
          fetch: async (request: RequestInfo | URL, _init?: RequestInit) => {
            assert(request instanceof Request);
            if (request.method === "PUT") {
              puts++;
              target = new Uint8Array(await request.arrayBuffer());
              assertEquals(target, bytes);
              if (mode === "lost_write" || mode === "mismatch") {
                throw new Error("synthetic lost write reply");
              }
              return new Response(null, { status: 200 });
            }
            assertEquals(request.method, "GET");
            const source = request.url.endsWith(binding.sourceKey);
            if (source) {
              sourceReads++;
              assertEquals(removed, false);
            } else destinationReads++;
            const content = source ? bytes : target;
            assert(content);
            if (mode === "retired" && !source) {
              await db.queryArray(
                "SELECT public.retire_capture_promotion_operation($1)",
                [binding],
              );
            }
            return new Response(content.slice(), {
              headers: {
                "Content-Type": binding.contentType,
                "Content-Length": "4",
              },
            });
          },
        };
        const fresh = await adapter.transfer(
          input,
          storage,
          new AbortController().signal,
        );
        assertEquals(
          fresh.outcome,
          mode === "acknowledged" ? "verified" : "held",
        );
        assertEquals(puts, 1);
        assertEquals(sourceReads, 1);
        await db.queryArray("RESET ROLE");
        await db.queryArray(
          "DELETE FROM public.scan_media_assets WHERE id=$1",
          [binding.assetId],
        );
        await db.queryArray(
          "DELETE FROM public.scan_ingestion_jobs WHERE user_id=$1 AND scan_id=$2",
          [owner, scan],
        );
        await db.queryArray(
          "DELETE FROM public.scan_ingestion_intents WHERE user_id=$1 AND scan_id=$2",
          [owner, scan],
        );
        removed = true;
        if (mode === "mismatch") target = new Uint8Array([9, 9, 9, 9]);
        await db.queryArray("SET LOCAL ROLE service_role");
        calls.length = 0;
        const previousReads = destinationReads;
        const recovered = await adapter.recover(
          { cohortId: input.cohortId, binding },
          storage,
          new AbortController().signal,
        );
        assertEquals(
          recovered.outcome,
          mode === "retired" || mode === "mismatch" ? "held" : "verified",
        );
        if (fresh.outcome === "verified") assertEquals(recovered, fresh);
        assertEquals(puts, 1);
        assertEquals(sourceReads, 1);
        assertEquals(
          destinationReads - previousReads,
          mode === "retired" ? 0 : 1,
        );
        assertEquals(
          calls,
          mode === "retired" || mode === "mismatch"
            ? ["authorize_capture_promotion_recovery"]
            : [
              "authorize_capture_promotion_recovery",
              "record_capture_promotion_verification",
            ],
        );
        await db.queryArray("RESET ROLE");
        const state =
          (await db.queryObject<{ issued: boolean; verified: boolean }>(
            "SELECT write_authorized_at IS NOT NULL AS issued,destination_verified_at IS NOT NULL AS verified FROM internal.capture_promotion_operations WHERE operation_id=$1",
            [operation],
          )).rows[0];
        assertEquals(state, {
          issued: true,
          verified: mode !== "retired" && mode !== "mismatch",
        });
      } finally {
        try {
          await db.queryArray("ROLLBACK");
        } finally {
          await db.end();
        }
        names.forEach((n, i) =>
          saved[i] === undefined
            ? Deno.env.delete(n)
            : Deno.env.set(n, saved[i]!)
        );
      }
    },
  });
}
