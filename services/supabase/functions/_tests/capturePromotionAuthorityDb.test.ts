import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { captureObjectBackendDigest } from "../_shared/captureObjectRetirement.ts";
import {
  type CapturePromotionBinding,
  transferVerifiedCapturePromotion,
  verifyCapturePromotionDestination,
} from "../_shared/capturePromotionStorage.ts";

const databaseURL = Deno.env.get("SUPABASE_DB_TEST_URL");
for (
  const { lostWriteReply, cohortBound } of [
    { lostWriteReply: false, cohortBound: false },
    { lostWriteReply: true, cohortBound: false },
    { lostWriteReply: false, cohortBound: true },
    { lostWriteReply: true, cohortBound: true },
  ]
) {
  Deno.test({
    name: `capture promotion ${
      cohortBound ? "cohort" : "operation"
    } SQL authority joins verified bytes and retains ${
      lostWriteReply ? "unknown" : "acknowledged"
    } write across retirement`,
    ignore: !databaseURL,
    async fn() {
      assert(databaseURL);
      assert(
        ["localhost", "127.0.0.1", "[::1]"].includes(
          new URL(databaseURL).hostname,
        ),
      );
      const db = new Client(databaseURL);
      const bytes = new Uint8Array([1, 2, 3, 4]);
      const hash = [
        ...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
      ]
        .map((v) => v.toString(16).padStart(2, "0")).join("");
      const backend = {
        endpoint: "https://capture-fixture.invalid",
        bucketName: "synthetic",
      };
      const owner = crypto.randomUUID(), operation = crypto.randomUUID();
      const binding: CapturePromotionBinding = {
        operationId: operation,
        ownerId: owner,
        scanId: crypto.randomUUID(),
        assetId: crypto.randomUUID(),
        sessionId: crypto.randomUUID(),
        backendSHA256: await captureObjectBackendDigest(backend),
        sourceKey: `staging/${owner}/fixture.webp`,
        destinationKey:
          `public_uploads/free/${owner}/capture-promotion-${operation}`,
        contentType: "image/webp",
        byteCount: bytes.byteLength,
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
            binding.scanId,
            binding.sessionId,
            binding.sourceKey,
            binding.contentType,
            binding.byteCount,
            hash,
          ],
        );
        await db.queryArray(
          "SELECT public.register_capture_upload_capabilities($1,$2,jsonb_build_array(jsonb_build_object('object_key',$3::text,'expires_at',clock_timestamp()+interval '1 hour','scan_id',$4::uuid,'asset_id',$5::uuid,'session_id',$6::uuid)))",
          [
            owner,
            binding.backendSHA256,
            binding.sourceKey,
            binding.scanId,
            binding.assetId,
            binding.sessionId,
          ],
        );
        if (cohortBound) {
          const keys = { image: [binding.sourceKey], audio: [], video: [] };
          await db.queryArray(
            "SELECT public.begin_scan_ingestion($1,$2,'identify-multimodal',$3,$4,$5,$6)",
            [
              binding.scanId,
              owner,
              {
                schemaVersion: 1,
                clientScanId: binding.scanId,
                media: {
                  r2ObjectKeys: keys.image,
                  audioR2ObjectKeys: [],
                  videoR2ObjectKeys: [],
                },
              },
              { image_count: 1, audio_count: 0, video_count: 0 },
              keys,
              [binding.sourceKey],
            ],
          );
          // Fixture inspection is administrative; the registration itself runs
          // as service_role, which intentionally cannot select the ledger.
          const projection = await db.queryObject<
            { id: string; manifest: string; request: string }
          >(
            `SELECT j.id,j.manifest_checksum AS manifest,i.payload_checksum AS request
             FROM public.scan_ingestion_jobs j JOIN public.scan_ingestion_intents i
             ON i.user_id=j.user_id AND i.scan_id=j.scan_id WHERE j.user_id=$1 AND j.scan_id=$2`,
            [owner, binding.scanId],
          );
          const { id, manifest, request } = projection.rows[0];
          await db.queryArray("SET LOCAL ROLE service_role");
          const sealed = await db.queryObject<{ seal: string }>(
            "SELECT public.register_capture_promotion_cohort($1,$2,$3,$4,$5) AS seal",
            [
              crypto.randomUUID(),
              id,
              manifest,
              request,
              JSON.stringify([binding]),
            ],
          );
          assert(/^[0-9a-f]{64}$/.test(sealed.rows[0].seal));
        }
        await db.queryArray("SET LOCAL ROLE service_role");
        const saved = await db.queryObject<{ ok: boolean }>(
          "SELECT public.register_capture_promotion_operation($1) AS ok",
          [binding],
        );
        assertEquals(saved.rows[0].ok, true);
        let puts = 0, gets = 0;
        let destination: Uint8Array | null = null;
        const deps = {
          backend,
          authorize: async (
            b: Readonly<CapturePromotionBinding>,
            action: string,
          ) => {
            const result = await db.queryObject<{ ok: boolean }>(
              "SELECT public.authorize_capture_promotion_action($1,$2) AS ok",
              [b, action],
            );
            if (result.rows[0].ok !== true) {
              throw new Error("synthetic authority unavailable");
            }
          },
          sign: (request: Request) => Promise.resolve(request),
          fetch: async (input: RequestInfo | URL, _init?: RequestInit) => {
            assert(input instanceof Request);
            const isSource = input.url.endsWith(binding.sourceKey);
            if (input.method === "PUT") {
              puts++;
              destination = new Uint8Array(await input.arrayBuffer());
              assertEquals([...destination], [...bytes]);
              assertEquals(input.headers.get("If-None-Match"), "*");
              if (lostWriteReply) throw new Error("synthetic lost PUT reply");
              return new Response(null, { status: 200 });
            }
            gets++;
            const content = isSource ? bytes : destination;
            assert(content);
            return new Response(new Uint8Array(content), {
              headers: {
                "Content-Type": binding.contentType,
                "Content-Length": String(content.byteLength),
              },
            });
          },
        };
        assertEquals(
          await verifyCapturePromotionDestination(
            binding,
            deps,
            new AbortController().signal,
          ),
          { outcome: "held" },
        );
        assertEquals(gets, 0); // Registered but no authorized PUT: no destination read.
        assertEquals(
          await transferVerifiedCapturePromotion(
            binding,
            deps,
            new AbortController().signal,
          ),
          lostWriteReply
            ? { outcome: "held", write: "unknown" }
            : { outcome: "verified", write: "acknowledged" },
        );
        assertEquals(puts, 1);
        assertEquals(gets, lostWriteReply ? 1 : 2);
        // A new invocation cannot turn a consumed durable dispatch into a retry,
        // even when the first network reply was lost and the target exists.
        assertEquals(
          await transferVerifiedCapturePromotion(
            binding,
            deps,
            new AbortController().signal,
          ),
          { outcome: "held", write: "not_started" },
        );
        assertEquals(puts, 1);
        assertEquals(
          await verifyCapturePromotionDestination(
            binding,
            deps,
            new AbortController().signal,
          ),
          { outcome: "verified" },
        );
        assertEquals(puts, 1);
        assertEquals(gets, lostWriteReply ? 2 : 3);
        await db.queryArray("RESET ROLE");
        await db.queryArray(
          "INSERT INTO internal.scan_deletion_tombstones(scan_id,user_id) VALUES($1,$2)",
          [binding.scanId, owner],
        );
        await db.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
        const token = crypto.randomUUID();
        await db.queryArray("SET LOCAL ROLE service_role");
        await db.queryArray("SAVEPOINT retired_verification");
        assertEquals(
          await verifyCapturePromotionDestination(
            binding,
            deps,
            new AbortController().signal,
          ),
          { outcome: "held" },
        );
        await db.queryArray("ROLLBACK TO SAVEPOINT retired_verification");
        assertEquals(puts, 1);
        assertEquals(gets, lostWriteReply ? 2 : 3);

        const targets = await db.queryObject<
          { operation_id: string; object_key: string }
        >("SELECT * FROM public.claim_capture_promotion_retirements($1,25)", [
          token,
        ]);
        assertEquals(targets.rows.map((r) => r.object_key), [
          binding.destinationKey,
        ]);
        assertEquals(targets.rows[0].operation_id, operation);
        const seen = await db.queryObject<{ ok: boolean }>(
          "SELECT public.observe_capture_promotion_retirement($1,$2,true,NULL) AS ok",
          [operation, token],
        );
        assertEquals(seen.rows[0].ok, true);
        await db.queryArray("RESET ROLE");
        const retained = await db.queryObject<
          { target: boolean; source: boolean }
        >(
          "SELECT o.retired_at IS NOT NULL AND o.observed_absent_at IS NOT NULL AND o.write_authorized_at IS NOT NULL AS target,s.retired_at IS NOT NULL AND s.observed_absent_at IS NULL AS source FROM internal.capture_promotion_operations o JOIN internal.capture_object_authorities s ON s.backend_sha256=o.backend_sha256 AND s.object_key=o.source_key WHERE o.operation_id=$1",
          [operation],
        );
        assertEquals(retained.rows, [{ target: true, source: true }]);
      } finally {
        await db.queryArray("ROLLBACK");
        await db.end();
      }
    },
  });
}
