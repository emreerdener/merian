"use client";

import { Alert, Button, Paper, Stack, Text, Title } from "@mantine/core";
import { useSearchParams } from "next/navigation";
import { useState } from "react";
import { createBrowserSupabaseClient } from "@/lib/supabase-browser";

const errors: Record<string, string> = {
  "not-authorized": "This Google account is not an active Naturebook admin member.",
  "session-expired": "Your admin session expired or was revoked. Sign in again.",
  "access-check": "We could not verify admin access. Sign in again.",
  "oauth": "Google sign-in could not be completed.",
};

export function LoginCard() {
  const [loading, setLoading] = useState(false);
  const params = useSearchParams();
  const error = params.get("error");

  async function signIn() {
    setLoading(true);
    const supabase = createBrowserSupabaseClient();
    const { error: signInError } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: {
        redirectTo: `${window.location.origin}/auth/callback?next=/mfa`,
        scopes: "openid email profile",
        queryParams: { prompt: "select_account" },
      },
    });
    if (signInError) setLoading(false);
  }

  return (
    <Paper withBorder shadow="md" radius="lg" p="xl" w="min(440px, 92vw)">
      <Stack gap="lg">
        <div><Title order={2}>Naturebook Internal</Title><Text c="dimmed">Authorized staff only</Text></div>
        {error && <Alert color="red" title="Access unavailable">{errors[error] ?? "Sign-in failed."}</Alert>}
        <Text size="sm">Sign in with your approved Google account. A verified authenticator code is required before any internal data is available.</Text>
        <Button onClick={signIn} loading={loading} size="md">Continue with Google</Button>
      </Stack>
    </Paper>
  );
}
