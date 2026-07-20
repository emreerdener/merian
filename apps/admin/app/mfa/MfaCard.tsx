"use client";

import { Alert, Button, Code, Image, Paper, PinInput, Stack, Text, Title } from "@mantine/core";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { createBrowserSupabaseClient } from "@/lib/supabase-browser";

type Factor = { id: string; status: string; friendly_name?: string };

export function MfaCard() {
  const router = useRouter();
  const [factor, setFactor] = useState<Factor | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [secret, setSecret] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);

  useEffect(() => { void prepare(); }, []);

  async function prepare() {
    const supabase = createBrowserSupabaseClient();
    const assurance = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    if (assurance.data.currentLevel === "aal2") {
      router.replace("/overview"); router.refresh(); return;
    }
    const factors = await supabase.auth.mfa.listFactors();
    const verified = factors.data?.totp.find((item: Factor) => item.status === "verified");
    if (verified) {
      setFactor(verified); setBusy(false); return;
    }
    const enrollment = await supabase.auth.mfa.enroll({ factorType: "totp", friendlyName: "Naturebook Admin" });
    if (enrollment.error) { setError(enrollment.error.message); setBusy(false); return; }
    setFactor(enrollment.data);
    setQr(enrollment.data.totp.qr_code);
    setSecret(enrollment.data.totp.secret);
    setBusy(false);
  }

  async function verify() {
    if (!factor || code.length !== 6) return;
    setBusy(true); setError(null);
    const supabase = createBrowserSupabaseClient();
    const result = await supabase.auth.mfa.challengeAndVerify({ factorId: factor.id, code });
    if (result.error) { setError(result.error.message); setBusy(false); return; }
    router.replace("/overview"); router.refresh();
  }

  return (
    <Paper withBorder shadow="md" radius="lg" p="xl" w="min(460px, 92vw)">
      <Stack align="center" gap="lg">
        <div><Title order={2} ta="center">Verify authenticator</Title><Text c="dimmed" ta="center">AAL2 is required for every admin session.</Text></div>
        {qr && <><Image src={qr} alt="Authenticator enrollment QR code" w={220} h={220} /><Text size="sm">Scan this once with your authenticator app.</Text>{secret && <Code>{secret}</Code>}</>}
        {error && <Alert color="red" w="100%">{error}</Alert>}
        <PinInput length={6} type="number" value={code} onChange={setCode} oneTimeCode aria-label="Six digit authenticator code" />
        <Button fullWidth onClick={verify} loading={busy} disabled={!factor || code.length !== 6}>Verify and continue</Button>
      </Stack>
    </Paper>
  );
}
