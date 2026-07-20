import { SupabaseClient } from "@supabase/supabase-js";

interface ReportableProfileRow {
  author_user_id: string;
}

function httpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function requireReportableUser(
  reporterUserId: string,
  reportedUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (reporterUserId === reportedUserId) {
    throw httpError(400, "You cannot report your own profile.");
  }

  // Reuse the public author-profile visibility contract instead of treating a
  // syntactically valid UUID as a reportable profile.
  const { data, error } = await supabaseAdmin.rpc(
    "get_explore_author_profile",
    {
      self_id: reporterUserId,
      target_author_user_id: reportedUserId,
      preview_limit: 1,
    },
  );
  const rows = (data ?? []) as ReportableProfileRow[];
  if (
    error || rows.length === 0 || rows[0]?.author_user_id !== reportedUserId
  ) {
    throw httpError(404, "Explore profile not found.");
  }
}

export async function upsertUserReport(
  input: {
    reporterUserId: string;
    reportedUserId: string;
    reason: string;
    details: string | null;
  },
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("user_reports")
    .upsert({
      reporter_user_id: input.reporterUserId,
      reported_user_id: input.reportedUserId,
      reason: input.reason,
      details: input.details,
      updated_at: new Date().toISOString(),
    }, {
      onConflict: "reporter_user_id,reported_user_id",
      ignoreDuplicates: false,
    });

  if (error) {
    throw new Error(`Failed to save user report: ${error.message}`);
  }
}
