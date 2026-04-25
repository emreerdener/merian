import { Resend } from "npm:resend@4.1.2";

export async function sendExportEmail(email: string, signedUrl: string) {
  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    console.warn("No RESEND_API_KEY found. Skipping email delivery.");
    return;
  }

  const resend = new Resend(resendKey);

  const { error } = await resend.emails.send({
    // TODO: PRODUCTION - Remove onboarding fallback once merian.app is verified in Resend.
    // Set RESEND_FROM_EMAIL to 'exports@merian.app' in Supabase Edge Secrets.
    from: Deno.env.get("RESEND_FROM_EMAIL") || "Merian Data Exports <onboarding@resend.dev>",
    to: [email],
    subject: "Your Merian Darwin Core Archive is Ready",
    html: `
      <h2>Your Export is Ready</h2>
      <p>Your Darwin Core Archive (DwC-A) containing your scans has finished processing.</p>
      <p>This secure link will expire in 24 hours.</p>
      <a href="${signedUrl}" style="display:inline-block;padding:12px 24px;background-color:#007AFF;color:white;text-decoration:none;border-radius:8px;">Download Archive</a>
      <br><br>
      <p>Thank you for contributing to Merian!</p>
    `
  });

  if (error) {
    throw new Error(`Failed to send export email via Resend: ${error.message}`);
  }
}
