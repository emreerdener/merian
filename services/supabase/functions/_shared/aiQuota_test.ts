import { buildDescribeAIRequest } from "../identify-describe/provider.ts";
import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
  assertThrows,
} from "@std/assert";
import {
  AIQuotaError,
  type AIQuotaReservation,
  clientAddressForQuota,
  createAIProviderQuotaLease,
  deriveAIRequestId,
  hmacClientAddress,
  quotaErrorForDatabaseMessage,
  reserveIdentificationProviderCall,
  resolveAIRequestId,
  resolveQuotaIpHashSecret,
} from "./aiQuota.ts";

const REQUEST_ID = "00000000-0000-0000-0000-000000000123";
const SECRET = "test-only-ai-quota-hmac-secret-32-bytes";

Deno.test("internal replay selects capability-aware admission without claiming worker capability", async () => {
  const prior = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
  Deno.env.set("AI_QUOTA_IP_HASH_SECRET", SECRET);
  try {
    const workerHeaders: Record<string, string>[] = [{}, {
      "X-Merian-Identification-Protocol": "4",
      "X-Merian-Identification-Recipient": "google_gemini",
    }];
    for (const headers of workerHeaders) {
      let calls = 0;
      const error = await assertRejects(() =>
        reserveIdentificationProviderCall(
          new Request("https://example.invalid", { headers }),
          {
            rpc: (name: string, args: Record<string, unknown>) => {
              calls++;
              assertEquals(name, "reserve_identification_quota");
              assertEquals(args.p_identification_protocol, null);
              assertEquals(
                args.p_expected_processor_permission,
                headers["X-Merian-Identification-Recipient"] ?? null,
              );
              assertEquals(args.p_internal_replay, true);
              assertEquals(args.p_original_analysis_id, REQUEST_ID);
              return {
                abortSignal: () =>
                  Promise.resolve({
                    data: null,
                    error: { message: "client_update_required" },
                  }),
              };
            },
          } as never,
          {
            request: buildDescribeAIRequest("Synthetic observation", {
              safeGpsLat: null,
              safeGpsLon: null,
            }),
            userId: "synthetic-owner",
            operation: "scan_identification",
            requestId: REQUEST_ID,
            originalAnalysisId: REQUEST_ID,
            internalReplay: true,
          },
        ), AIQuotaError);
      assertEquals(calls, 1);
      assertEquals(error.code, "client_update_required");
    }
  } finally {
    if (prior === undefined) Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
    else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", prior);
  }
});

Deno.test("identification capability is separate from entitlement and cannot select a provider", async () => {
  const prior = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
  Deno.env.set("AI_QUOTA_IP_HASH_SECRET", SECRET);
  try {
    for (const capability of ["4", "5", "3", "6", "04", "garbage"]) {
      let calls = 0;
      const error = await assertRejects(() =>
        reserveIdentificationProviderCall(
          new Request("https://example.invalid", {
            headers: {
              "X-Merian-Entitlement-Protocol": "3",
              "X-Merian-Identification-Protocol": capability,
              "X-Merian-Identification-Recipient": "google_gemini",
            },
          }),
          {
            rpc: (_name: string, args: Record<string, unknown>) => {
              calls++;
              assertEquals(args.p_client_protocol, 3);
              assertEquals(args.p_identification_protocol, Number(capability));
              assertEquals("p_model" in args || "p_provider" in args, false);
              return {
                abortSignal: () =>
                  Promise.resolve({
                    data: null,
                    error: { message: "client_update_required" },
                  }),
              };
            },
          } as never,
          {
            request: buildDescribeAIRequest("Synthetic observation", {
              safeGpsLat: null,
              safeGpsLon: null,
            }),
            userId: "synthetic-owner",
            operation: "scan_identification",
            requestId: REQUEST_ID,
          },
        ), AIQuotaError);
      assertEquals(calls, ["4", "5"].includes(capability) ? 1 : 0);
      assertEquals(error.status, ["4", "5"].includes(capability) ? 426 : 400);
    }
  } finally {
    if (prior === undefined) Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
    else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", prior);
  }
});

Deno.test("AI request id prefers the validated body id", () => {
  const request = new Request("https://example.invalid", {
    headers: {
      "Idempotency-Key": "00000000-0000-0000-0000-000000000999",
    },
  });
  assertEquals(resolveAIRequestId(request, REQUEST_ID), REQUEST_ID);
});

Deno.test("AI request id uses a validated Idempotency-Key header", () => {
  const request = new Request("https://example.invalid", {
    headers: { "Idempotency-Key": REQUEST_ID.toUpperCase() },
  });
  assertEquals(resolveAIRequestId(request), REQUEST_ID);
});

Deno.test("invalid AI idempotency keys fail before database access", () => {
  const error = assertThrows(
    () =>
      resolveAIRequestId(
        new Request("https://example.invalid"),
        "attacker-controlled-arbitrary-key",
      ),
    AIQuotaError,
  );
  assertEquals(error.status, 400);
  assertEquals(error.code, "ai_request_id_invalid");
});

Deno.test("paid sub-operations derive stable, non-reversible UUIDs", async () => {
  const first = await deriveAIRequestId(
    REQUEST_ID,
    "audio-checksum:policy-v1",
  );
  const replay = await deriveAIRequestId(
    REQUEST_ID,
    "audio-checksum:policy-v1",
  );
  const differentMedia = await deriveAIRequestId(
    REQUEST_ID,
    "different-checksum:policy-v1",
  );

  assertEquals(first, replay);
  assertNotEquals(first, differentMedia);
  assert(
    /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(first),
  );
  assert(!first.includes("audio-checksum"));
});

Deno.test("quota address trusts proxy-observed headers and right-most forwarding peer", () => {
  assertEquals(
    clientAddressForQuota(
      new Headers({
        "x-real-ip": "203.0.113.8",
        "x-forwarded-for": "198.51.100.4, 192.0.2.7",
      }),
    ),
    "203.0.113.8",
  );
  assertEquals(
    clientAddressForQuota(
      new Headers({
        "x-forwarded-for": "attacker-value, 192.0.2.7",
      }),
    ),
    "192.0.2.7",
  );
  assertEquals(clientAddressForQuota(new Headers()), "unavailable");
});

Deno.test("quota IP HMAC is deterministic per day and rotates without exposing the IP", async () => {
  const address = "203.0.113.8";
  const first = await hmacClientAddress(
    address,
    SECRET,
    new Date("2026-07-23T12:00:00Z"),
  );
  const sameDay = await hmacClientAddress(
    address,
    SECRET,
    new Date("2026-07-23T23:59:59Z"),
  );
  const nextDay = await hmacClientAddress(
    address,
    SECRET,
    new Date("2026-07-24T00:00:00Z"),
  );

  assertEquals(first, sameDay);
  assertNotEquals(first, nextDay);
  assert(/^[0-9a-f]{64}$/.test(first));
  assert(!first.includes(address));
});

Deno.test("quota hashing fails closed when its dedicated secret is weak", async () => {
  let caught: unknown;
  try {
    await hmacClientAddress("203.0.113.8", "too-short");
  } catch (error) {
    caught = error;
  }
  assert(caught instanceof AIQuotaError);
  assertEquals(caught.status, 503);
  assertEquals(caught.code, "ai_quota_unavailable");
});

Deno.test("quota hashing uses an optional dedicated override or a server-only platform key", () => {
  const dedicated = `${SECRET}-dedicated`;
  const platform = `${SECRET}-platform`;
  assertEquals(
    resolveQuotaIpHashSecret({
      dedicatedSecret: ` ${dedicated} `,
      platformSecretKey: platform,
    }),
    dedicated,
  );
  assertEquals(
    resolveQuotaIpHashSecret({
      platformSecretKey: platform,
      serviceRoleKey: `${SECRET}-legacy`,
    }),
    platform,
  );
  assertEquals(
    resolveQuotaIpHashSecret({ serviceRoleKey: `${SECRET}-legacy` }),
    `${SECRET}-legacy`,
  );
  assertThrows(
    () =>
      resolveQuotaIpHashSecret({
        dedicatedSecret: "explicit-but-weak",
        platformSecretKey: platform,
      }),
    AIQuotaError,
  );
});

Deno.test("provider-head revocation maps to a caller-safe AI Edge denial", () => {
  const error = quotaErrorForDatabaseMessage(
    "ai_consent_required",
  );

  assertEquals(error.status, 403);
  assertEquals(error.code, "ai_consent_required");
  assertEquals(
    error.message,
    "Confirm you are 18 or older, accept the current Terms, and allow Google Gemini processing to continue.",
  );
});

function quotaReservation(): AIQuotaReservation {
  return {
    id: "00000000-0000-0000-0000-000000000321",
    requestId: REQUEST_ID,
    leaseToken: "00000000-0000-0000-0000-000000000654",
    leaseExpiresAt: "2026-07-23T12:10:00.000Z",
    attemptCount: 1,
    model: "gemini-2.5-flash",
    tier: {
      current_plan: "free",
      current_tier: "free",
      is_paid: false,
      scans_remaining: 0,
      scans_available_to_start: 0,
      in_flight_count: 0,
      effective_tier: "free",
      plan: "free",
      subscription_tier: "free",
      trial_active: false,
      user_exists: true,
      entitlement_version: 1,
    },
    policyVersion: 1,
    dailyLimit: 1,
    dailyRemaining: 0,
    originalAnalysisId: null,
    complimentaryClientScanId: null,
    flashFallbackUsed: false,
  };
}

Deno.test("provider commit fails closed and forwards the attempt fencing token", async () => {
  const calls: Array<Record<string, unknown>> = [];
  const client = {
    rpc: (_name: string, args: Record<string, unknown>) => {
      calls.push(args);
      return {
        abortSignal: () =>
          Promise.resolve({
            data: null,
            error: { code: "P0001" },
          }),
      };
    },
  };
  const lease = createAIProviderQuotaLease(
    client as never,
    "00000000-0000-0000-0000-000000000111",
    quotaReservation(),
  );

  const error = await assertRejects(
    () => lease.commit(),
    AIQuotaError,
  );
  assertEquals(error.status, 503);
  assertEquals(error.code, "ai_quota_unavailable");
  assertEquals(
    calls[0]?.p_lease_token,
    quotaReservation().leaseToken,
  );
});

Deno.test("failed provider attempts transition committed leases without refunding", async () => {
  const states: unknown[] = [];
  const client = {
    rpc: (_name: string, args: Record<string, unknown>) => {
      states.push(args.p_final_state);
      return {
        abortSignal: () => Promise.resolve({ data: true, error: null }),
      };
    },
  };
  const lease = createAIProviderQuotaLease(
    client as never,
    "00000000-0000-0000-0000-000000000111",
    quotaReservation(),
  );

  await lease.commit();
  assertEquals(await lease.fail(), true);
  assertEquals(await lease.refund(), false);
  assertEquals(states, ["committed", "failed"]);
});

Deno.test("identification admission requires database assignment and preserves non-dispatchable legacy replay", async (test) => {
  const previous = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
  Deno.env.set("AI_QUOTA_IP_HASH_SECRET", SECRET);
  try {
    const valid = {
      reservation_id: "00000000-0000-0000-0000-000000000321",
      request_id: REQUEST_ID,
      lease_token: "00000000-0000-0000-0000-000000000654",
      lease_expires_at: "2099-01-01T00:00:00Z",
      reservation_state: "reserved",
      is_replay: false,
      attempt_count: 1,
      model: "gemini-2.5-flash",
      effective_plan: "free",
      effective_tier: "free",
      subscription_tier: "free",
      trial_active: false,
      entitlement_version: 1,
      policy_version: 1,
      daily_limit: 10,
      daily_remaining: 9,
      original_analysis_id: null,
      complimentary_client_scan_id: null,
      flash_fallback_used: false,
      scans_remaining: 0,
      scans_available_to_start: 0,
      in_flight_count: 0,
      provider: "gemini",
      binding: "gemini_baseline_v1",
      processor_permission: "google_gemini",
      input_profile: "description_compat_v1",
    };
    for (
      const [name, changes, code] of [
        ["valid", {}, null],
        [
          "missing input profile",
          { input_profile: undefined },
          "ai_quota_unavailable",
        ],
        [
          "unknown input profile",
          { input_profile: "user_choice" },
          "ai_quota_unavailable",
        ],
        [
          "mismatched complete input",
          { input_profile: "multimodal_audio_v1" },
          "ai_quota_unavailable",
        ],
        ["missing provider", { provider: undefined }, "ai_quota_unavailable"],
        ["missing binding", { binding: undefined }, "ai_quota_unavailable"],
        [
          "missing permission",
          { processor_permission: undefined },
          "ai_quota_unavailable",
        ],
        ["unknown provider", { provider: "openai" }, "ai_quota_unavailable"],
        [
          "wrong binding",
          { binding: "openai_photo_text_v1" },
          "ai_quota_unavailable",
        ],
        [
          "wrong permission",
          { processor_permission: "openai" },
          "ai_quota_unavailable",
        ],
        ["wrong model", { model: "gpt-6-sol" }, "ai_quota_unavailable"],
        ["legacy active replay", {
          is_replay: true,
          provider: null,
          binding: null,
          processor_permission: null,
        }, "ai_request_in_progress"],
        ["legacy completion replay", {
          is_replay: true,
          reservation_state: "committed",
          provider: null,
          binding: null,
          processor_permission: null,
        }, "ai_request_already_completed"],
      ] as const
    ) {
      await test.step(name, async () => {
        const calls: string[] = [];
        const client = {
          rpc: (rpc: string, args: Record<string, unknown>) => {
            calls.push(rpc);
            assertEquals(rpc, "reserve_identification_quota");
            assertEquals(
              Object.keys(args).sort(),
              [
                "p_user_id",
                "p_operation",
                "p_request_id",
                "p_ip_hash",
                "p_original_analysis_id",
                "p_flash_fallback_eligible",
                "p_client_protocol",
                "p_internal_replay",
                "p_input_profile",
              ].sort(),
            );
            return {
              abortSignal: () =>
                Promise.resolve({
                  data: { ...valid, ...changes },
                  error: null,
                }),
            };
          },
        };
        const call = () =>
          reserveIdentificationProviderCall(
            new Request("https://example.invalid"),
            client as never,
            {
              request: buildDescribeAIRequest("Synthetic observation", {
                safeGpsLat: null,
                safeGpsLon: null,
              }),
              userId: "synthetic-owner",
              operation: "scan_identification",
              requestId: REQUEST_ID,
            },
          );
        if (code) {
          const error = await assertRejects(call, AIQuotaError);
          assertEquals(error.code, code);
        } else {
          const lease = await call();
          assertEquals(lease.reservation.assignment, {
            provider: "gemini",
            binding: "gemini_baseline_v1",
            permission: "google_gemini",
            inputProfile: "description_compat_v1",
          });
          assert(Object.isFrozen(lease.reservation.assignment));
        }
        assertEquals(calls, ["reserve_identification_quota"]);
      });
    }
    await test.step("content operation never reaches the identification RPC", async () => {
      const error = await assertRejects(
        () =>
          reserveIdentificationProviderCall(
            new Request("https://example.invalid"),
            {
              rpc: () => {
                throw new Error("must not call RPC");
              },
            } as never,
            {
              request: buildDescribeAIRequest("Synthetic observation", {
                safeGpsLat: null,
                safeGpsLon: null,
              }),
              userId: "synthetic-owner",
              operation: "species_overview" as never,
            },
          ),
        AIQuotaError,
      );
      assertEquals(error.code, "ai_quota_unavailable");
    });
  } finally {
    if (previous === undefined) Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
    else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", previous);
  }
});

Deno.test("missing database assignment has a stable content-free failure", () => {
  const error = quotaErrorForDatabaseMessage(
    "ai_provider_assignment_unavailable",
  );
  assertEquals(error.status, 503);
  assertEquals(error.code, "ai_quota_unavailable");
  assertEquals(error.message, "AI service is temporarily unavailable.");
});

Deno.test("identification compatibility denial returns 426 without another reservation or provider lease", async (test) => {
  const previous = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
  Deno.env.set("AI_QUOTA_IP_HASH_SECRET", SECRET);
  try {
    for (
      const [header, expected] of [
        [null, null],
        ["2", 2],
        ["3", 3],
        ["999", 999],
        ["3.0", null],
        ["03", null],
        ["3junk", null],
      ] as const
    ) {
      await test.step(String(header), async () => {
        let calls = 0;
        const error = await assertRejects(
          () =>
            reserveIdentificationProviderCall(
              new Request("https://example.invalid", {
                headers: header == null
                  ? {}
                  : { "X-Merian-Entitlement-Protocol": header },
              }),
              {
                rpc: (name: string, args: Record<string, unknown>) => {
                  calls++;
                  assertEquals(name, "reserve_identification_quota");
                  assertEquals(args.p_client_protocol, expected);
                  return {
                    abortSignal: () =>
                      Promise.resolve({
                        data: null,
                        error: {
                          message: "client_update_required",
                          code: "P0001",
                        },
                      }),
                  };
                },
              } as never,
              {
                request: buildDescribeAIRequest("Synthetic observation", {
                  safeGpsLat: null,
                  safeGpsLon: null,
                }),
                userId: "synthetic-owner",
                operation: "scan_identification",
                requestId: REQUEST_ID,
              },
            ),
          AIQuotaError,
        );
        assertEquals(calls, 1);
        assertEquals(error.status, 426);
        assertEquals(error.code, "client_update_required");
        assertEquals(
          error.message,
          "Please update Naturebook to continue identifying.",
        );
      });
    }
  } finally {
    if (previous === undefined) Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
    else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", previous);
  }
});

Deno.test("OpenAI denial has a distinct bounded recipient code", () => {
  const error = quotaErrorForDatabaseMessage("ai_openai_consent_required");
  assertEquals(error.status, 403);
  assertEquals(error.code, "ai_openai_consent_required");
  assertEquals(
    error.message,
    "OpenAI processing permission is required before identifying this observation.",
  );
  for (
    const message of [
      "ai_openai_consent_required_unknown",
      "private detail: ai_openai_consent_required",
    ]
  ) {
    const unknown = quotaErrorForDatabaseMessage(message);
    assertEquals(unknown.status, 503);
    assertEquals(unknown.code, "ai_entitlement_unavailable");
    assertEquals(unknown.message.includes("private detail"), false);
  }
});

Deno.test("recipient expectations only select the guarded admission overload and never a provider", async (test) => {
  const previous = Deno.env.get("AI_QUOTA_IP_HASH_SECRET");
  Deno.env.set("AI_QUOTA_IP_HASH_SECRET", SECRET);
  try {
    for (const recipient of ["google_gemini", "openai", "recovery_only"]) {
      await test.step(recipient, async () => {
        let calls = 0;
        const error = await assertRejects(
          () =>
            reserveIdentificationProviderCall(
              new Request("https://example.invalid", {
                headers: { "X-Merian-Identification-Recipient": recipient },
              }),
              {
                rpc: (name: string, args: Record<string, unknown>) => {
                  calls++;
                  assertEquals(name, "reserve_identification_quota");
                  assertEquals(args.p_expected_processor_permission, recipient);
                  assertEquals(args.p_input_profile, "description_compat_v1");
                  assertEquals("p_provider" in args, false);
                  assertEquals("p_model" in args, false);
                  return {
                    abortSignal: () =>
                      Promise.resolve({
                        data: null,
                        error: {
                          code: "P0001",
                          message: "ai_identification_preflight_changed",
                        },
                      }),
                  };
                },
              } as never,
              {
                request: buildDescribeAIRequest("Synthetic observation", {
                  safeGpsLat: null,
                  safeGpsLon: null,
                }),
                userId: "synthetic-owner",
                operation: "scan_identification",
                requestId: REQUEST_ID,
              },
            ),
          AIQuotaError,
        );
        assertEquals(calls, 1);
        assertEquals(error.status, 409);
        assertEquals(error.code, "ai_identification_preflight_changed");
        assertEquals(
          error.message,
          "Identification requirements changed. Please check again before retrying.",
        );
      });
    }
    for (
      const recipient of [
        "",
        "gemini",
        "OpenAI",
        "google_gemini, openai",
        "unknown-recipient",
      ]
    ) {
      await test.step(`invalid: ${recipient}`, async () => {
        let calls = 0;
        const error = await assertRejects(
          () =>
            reserveIdentificationProviderCall(
              new Request("https://example.invalid", {
                headers: { "X-Merian-Identification-Recipient": recipient },
              }),
              {
                rpc: () => {
                  calls++;
                  throw new Error("must not reserve");
                },
              } as never,
              {
                request: buildDescribeAIRequest("Synthetic observation", {
                  safeGpsLat: null,
                  safeGpsLon: null,
                }),
                userId: "synthetic-owner",
                operation: "scan_identification",
                requestId: REQUEST_ID,
              },
            ),
          AIQuotaError,
        );
        assertEquals(calls, 0);
        assertEquals(error.status, 400);
        assertEquals(error.code, "ai_identification_preflight_invalid");
        assertEquals(
          error.message,
          "Invalid identification preflight expectation.",
        );
      });
    }
  } finally {
    if (previous === undefined) Deno.env.delete("AI_QUOTA_IP_HASH_SECRET");
    else Deno.env.set("AI_QUOTA_IP_HASH_SECRET", previous);
  }
});

Deno.test("recipient drift mapping is exact and does not expose database details", () => {
  for (
    const message of [
      "ai_identification_preflight_changed_extra",
      "private detail: ai_identification_preflight_changed",
    ]
  ) {
    const error = quotaErrorForDatabaseMessage(message);
    assertEquals(error.status, 503);
    assertEquals(error.code, "ai_entitlement_unavailable");
    assertEquals(error.message.includes("private detail"), false);
  }
});
