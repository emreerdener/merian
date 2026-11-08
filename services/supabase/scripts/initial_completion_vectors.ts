import { completionAcquisitionFixture } from "../functions/_shared/initialAnalysis/fixtures/completionAcquisition.ts";
import { cpmCompletionAdmissionFixture } from "../functions/_shared/initialAnalysis/fixtures/cpmCompletionAdmission.ts";
import {
  decodeInitialCompletionAcquisition,
  snapshotInitialCompletionAdmission,
} from "../functions/_shared/initialAnalysis/completionAcquisition.ts";
import { encodeInitialCompletionStatus } from "../functions/_shared/initialAnalysis/completionStatusResponse.ts";
import { initialCompletionResultVectors } from "./initial_completion_result_vectors.ts";
import { completionRecoveryVector } from "./initial_completion_recovery_vector.ts";
/** Synthetic byte vectors shared by Deno, native decoding and SQL structural checks. */
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import { cpmCompletionAdmissionVectors } from "./initial_cpm_completion_admission_vectors.ts";
import {
  id,
  projection,
  receipt,
} from "../functions/_shared/initialAnalysis/fixtures/completionDocuments.ts";

export async function completionVectors() {
  const documents: {
    name: string;
    valid: boolean;
    structural: boolean;
    receipt: string;
    projection: string;
  }[] = [];
  async function add(
    name: string,
    p: ReturnType<typeof projection>,
    valid = true,
    structural = true,
    changeReceipt?: (r: Awaited<ReturnType<typeof receipt>>) => void,
  ) {
    const r = await receipt(p);
    changeReceipt?.(r);
    documents.push({
      name,
      valid,
      structural,
      receipt: initialCanonicalText(r),
      projection: initialCanonicalText(p),
    });
  }
  for (const cpm of [true, false]) {
    for (
      const outcome of [
        "none",
        "consumed_durable_result",
        "released_paid_before_completion",
      ]
    ) {
      await add(
        `${cpm ? "cpm" : "legacy"}_${outcome}`,
        projection(cpm, outcome),
      );
    }
  }
  for (const kind of ["audio", "video"]) {
    const p = projection(false);
    Object.assign(p.media.items[0], {
      kind,
      content_type: kind === "audio" ? "audio/wav" : "video/mp4",
      poster_media_id: kind === "video" ? id(9) : null,
    });
    await add(kind, p);
  }
  for (const name of ["é", "e\u0301", "\ufeffTaxon\n\t/🦋\u2028\u2029\u0001"]) {
    const p = projection();
    p.species_association = { species_id: id(8), scientific_name: name };
    await add(`unicode_${documents.length}`, p);
  }
  const faults: [
    string,
    boolean,
    (p: ReturnType<typeof projection>) => void,
  ][] = [
    ["owner", true, (p) => {
      p.owner_id = id(9);
    }],
    ["credit", true, (p) => {
      p.credit_consumed = false;
    }],
    ["calendar", true, (p) => {
      p.completed_at = p.scan_timestamp = "2026-02-31T03:00:00+00:00";
    }],
    ["leap_second", true, (p) => {
      p.completed_at = p.scan_timestamp = "2026-12-31T23:59:60+00:00";
    }],
    ["clock_newline", false, (p) => {
      p.completed_at += "\n";
      p.scan_timestamp = p.completed_at;
    }],
    ["privacy", true, (p) => {
      p.geoprivacy = "open";
    }],
    ["empty_media", true, (p) => {
      p.media.items = [];
    }],
    ["duplicate_media", true, (p) => {
      p.media.items.push({ ...p.media.items[0], ordinal: 1 });
    }],
    ["cpm_format", true, (p) => {
      p.media.items[0].content_type = "image/png";
    }],
    ["cpm_bytes", true, (p) => {
      p.media.items[0].byte_count = 4194305;
    }],
    ["extra_key", false, (p) => {
      Reflect.set(p.settlement, "extra", true);
    }],
    ["missing_key", false, (p) => {
      Reflect.deleteProperty(p.entitlement_after, "is_paid");
    }],
    ["boolean_integer", false, (p) => {
      Reflect.set(p.entitlement_after, "in_flight_count", true);
    }],
    ["quota", false, (p) => {
      p.entitlement_after.scans_remaining = 4;
    }],
  ];
  for (const [name, structural, mutate] of faults) {
    const p = projection();
    mutate(p);
    await add(name, p, false, structural);
  }
  await add("digest", projection(), false, true, (r) => {
    r.completion_projection_digest = "b".repeat(64);
  });
  await add("operation", projection(), false, true, (r) => {
    r.operation_id = id(9);
  });
  const max = projection();
  max.entitlement_after.in_flight_count = Number.MAX_SAFE_INTEGER;
  await add("safe_integer_max", max);
  const zero = projection();
  zero.completed_at = zero.scan_timestamp = "0000-02-29T00:00:00+00:00";
  await add("year_zero", zero);
  const boundary = projection();
  boundary.species_association = { species_id: id(8), scientific_name: "" };
  const jsonbText = (value: unknown): string =>
    Array.isArray(value)
      ? `[${value.map(jsonbText).join(", ")}]`
      : value !== null && typeof value === "object"
      ? `{${
        Object.entries(value).map(([key, v]) =>
          `${JSON.stringify(key)}: ${jsonbText(v)}`
        ).join(", ")
      }}`
      : JSON.stringify(value);
  boundary.species_association.scientific_name = "x".repeat(
    65536 - new TextEncoder().encode(jsonbText(boundary)).length,
  );
  await add("jsonb_exact_limit", boundary);
  boundary.species_association.scientific_name += "x";
  await add("jsonb_over_limit", boundary, false, true);
  const admissions = await cpmCompletionAdmissionVectors();
  const original = await cpmCompletionAdmissionFixture();
  const admission = snapshotInitialCompletionAdmission(original.admission);
  const replies = [{
    name: "pending",
    outcome: "pending",
    bytes: new TextDecoder().decode(
      encodeInitialCompletionStatus(admission, null),
    ),
    result_canonical: null as string | null,
  }];
  for (
    const [name, reasoning] of [["found", "Synthetic result"], [
      "unicode",
      "\ufeffe\u0301/🦋\n\t",
    ]]
  ) {
    const f = await completionAcquisitionFixture(true, admission, reasoning);
    const acquired = await decodeInitialCompletionAcquisition(
      f.reply,
      admission,
    );
    if (!acquired) throw new Error("status_fixture_missing");
    replies.push({
      name,
      outcome: "found",
      bytes: new TextDecoder().decode(
        encodeInitialCompletionStatus(admission, acquired),
      ),
      result_canonical: acquired.delivery.result.result_canonical,
    });
  }
  return {
    admissions,
    status_reply: {
      original: admissions.original,
      acknowledgement: initialCanonicalText(original.reply),
      replies,
    },
    recovery_record: await completionRecoveryVector(),
    retained_results: await initialCompletionResultVectors(),
    documents,
    canonical: [
      ...[
        "null",
        "true",
        "false",
        "0",
        "-1",
        "9007199254740991",
        "-9007199254740991",
        '{"a":"é","b":"é","c":"🦋/","d":"\\u0001\\b\\t\\n\\f\\r\\"\\\\"}',
      ]
        .map((text) => ({ text, valid: true })),
      ...[
        '{"a":1,"a":2}',
        '{"b":1,"a":2}',
        '{"a": 1}',
        "1.0",
        "1e0",
        "-0",
        "9007199254740992",
        '"\\u0061"',
        '"\\/"',
        '"\\ud800"',
        '"\\u0000"',
        '{"Upper":1}',
        '{"é":1}',
        "\ufeff{}",
        "{}\n",
      ]
        .map((text) => ({ text, valid: false })),
    ],
  };
}
