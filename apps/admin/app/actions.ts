"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { adminRpc } from "@/lib/admin";

async function verifyMutationOrigin() {
  const requestHeaders = await headers();
  const origin = requestHeaders.get("origin");
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  if (!origin || !host || new URL(origin).host !== host) throw new Error("Invalid mutation origin.");
}

function required(form: FormData, name: string): string {
  const value = form.get(name);
  if (typeof value !== "string" || !value.trim()) throw new Error(`${name} is required.`);
  return value.trim();
}

export async function updateReviewCase(form: FormData) {
  await verifyMutationOrigin();
  const caseId = required(form, "case_id");
  await adminRpc("admin_update_review_case", {
    p_case_id: caseId,
    p_status: required(form, "status"),
    p_priority: required(form, "priority"),
    p_assigned_to: String(form.get("assigned_to") ?? "").trim() || null,
    p_change_assignee: true,
    p_resolution_code: String(form.get("resolution_code") ?? "") || null,
    p_note: String(form.get("note") ?? "") || null,
  }, "moderator");
  revalidatePath("/reviews"); revalidatePath(`/reviews/${caseId}`);
}

export async function setContentVisibility(form: FormData) {
  await verifyMutationOrigin();
  const caseId = required(form, "case_id");
  await adminRpc("admin_set_content_visibility", {
    p_case_id: caseId,
    p_hidden: required(form, "hidden") === "true",
    p_reason: required(form, "reason"),
  }, "moderator");
  revalidatePath(`/reviews/${caseId}`);
}

export async function updateFeedback(form: FormData) {
  await verifyMutationOrigin();
  await adminRpc("admin_update_feedback", {
    p_source_type: required(form, "source_type"),
    p_source_id: required(form, "source_id"),
    p_status: required(form, "status"),
    p_assigned_to: String(form.get("assigned_to") ?? "").trim() || null,
    p_tags: String(form.get("tags") ?? "").split(",").map((tag) => tag.trim()).filter(Boolean),
    p_note: String(form.get("note") ?? "") || null,
  }, "moderator");
  revalidatePath("/feedback");
}

export async function searchUsers(search: string, cursor?: { created_at: string; id: string } | null) {
  if (search.trim().length < 2) return { items: [], next_cursor: null, limit: 50 };
  return await adminRpc<{ items: Record<string, unknown>[]; next_cursor?: { created_at: string; id: string } | null; limit: number }>("admin_list_users", {
    p_search: search.trim(),
    p_cursor_created_at: cursor?.created_at ?? null,
    p_cursor_id: cursor?.id ?? null,
    p_limit: 50,
  }, "moderator");
}

export async function upsertMember(form: FormData) {
  await verifyMutationOrigin();
  await adminRpc("admin_upsert_member", {
    p_email: required(form, "email"),
    p_role: required(form, "role"),
    p_is_active: required(form, "is_active") === "true",
  }, "owner");
  revalidatePath("/access");
}

export async function revokeAdminSession(form: FormData) {
  await verifyMutationOrigin();
  await adminRpc("admin_revoke_session", {
    p_session_id: required(form, "session_id"), p_reason: required(form, "reason"),
  }, "owner");
  revalidatePath("/access");
}
