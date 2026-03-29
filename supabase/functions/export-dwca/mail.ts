export async function sendExportEmail(email: string, signedUrl: string) {
  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    console.warn("No RESEND_API_KEY found. Skipping email delivery.");
    return;
  }

  const emailRes = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${resendKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "Merian Data Exports <exports@merian.app>", // Update domain if needed
      to: [email],
      subject: "Your Merian Darwin Core Archive is Ready",
      html: `
        <h2>Your Export is Ready</h2>
        <p>Your Darwin Core Archive (DwC-A) containing your scans has finished processing.</p>
        <p>This secure link will expire in 24 hours.</p>
        <a href="${signedUrl}" style="display:inline-block;padding:12px 24px;background-color:#007AFF;color:white;text-decoration:none;border-radius:8px;">Download Archive</a>
        <br><br>
        <p>Thank you for contributing to Merian!</p>
      `,
    }),
  });

  if (!emailRes.ok) {
    const errBody = await emailRes.text();
    console.error("Failed to send Resend email:", errBody);
  }
}
