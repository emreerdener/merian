"use client";

import Script from "next/script";
import type { FormEvent } from "react";
import { useEffect, useRef, useState } from "react";
import { Alert, Button, Group, Stack, Text, TextInput } from "@mantine/core";
import { IconArrowRight, IconCheck, IconX } from "@tabler/icons-react";

type FormState = "idle" | "submitting" | "success" | "error";

type TurnstileApi = {
  render: (
    container: HTMLElement,
    options: {
      sitekey: string;
      action: string;
      appearance: "interaction-only";
      callback: (token: string) => void;
      "expired-callback": () => void;
      "error-callback": () => void;
    },
  ) => string;
  remove: (widgetId: string) => void;
  reset: (widgetId: string) => void;
};

declare global {
  interface Window {
    turnstile?: TurnstileApi;
  }
}

const turnstileSiteKey = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? "";

export function WaitlistForm() {
  const [email, setEmail] = useState("");
  const [formState, setFormState] = useState<FormState>("idle");
  const [message, setMessage] = useState("");
  const [scriptReady, setScriptReady] = useState(false);
  const [turnstileToken, setTurnstileToken] = useState("");
  const challengeContainerRef = useRef<HTMLDivElement>(null);
  const widgetIdRef = useRef<string | null>(null);

  useEffect(() => {
    if (
      !scriptReady ||
      !turnstileSiteKey ||
      !challengeContainerRef.current ||
      !window.turnstile ||
      widgetIdRef.current
    ) {
      return;
    }

    widgetIdRef.current = window.turnstile.render(
      challengeContainerRef.current,
      {
        sitekey: turnstileSiteKey,
        action: "waitlist",
        appearance: "interaction-only",
        callback: setTurnstileToken,
        "expired-callback": () => setTurnstileToken(""),
        "error-callback": () => setTurnstileToken(""),
      },
    );

    return () => {
      if (widgetIdRef.current && window.turnstile) {
        window.turnstile.remove(widgetIdRef.current);
      }
      widgetIdRef.current = null;
    };
  }, [scriptReady]);

  function resetChallenge() {
    setTurnstileToken("");
    if (widgetIdRef.current && window.turnstile) {
      window.turnstile.reset(widgetIdRef.current);
    }
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!turnstileToken) {
      setFormState("error");
      setMessage("Complete the security check and try again.");
      return;
    }

    setFormState("submitting");
    setMessage("");

    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          email,
          turnstile_token: turnstileToken,
        }),
      });
      const payload = (await response.json()) as { message?: string };

      if (!response.ok) {
        throw new Error(payload.message ?? "Could not join the beta list.");
      }

      setFormState("success");
      setMessage(payload.message ?? "You are on the beta list.");
      setEmail("");
    } catch (error) {
      setFormState("error");
      setMessage(
        error instanceof Error
          ? error.message
          : "Something went wrong. Please try again.",
      );
    } finally {
      resetChallenge();
    }
  }

  return (
    <Stack gap="sm" id="waitlist" className="waitlist-signup">
      <Script
        src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
        strategy="afterInteractive"
        onReady={() => setScriptReady(true)}
      />
      <form onSubmit={handleSubmit}>
        <Stack gap="xs">
          <Group
            gap="sm"
            wrap="nowrap"
            align="center"
            className="waitlist-signup__row"
          >
            <TextInput
              aria-label="Email address"
              placeholder="you@example.com"
              value={email}
              onChange={(event) => setEmail(event.currentTarget.value)}
              type="email"
              inputMode="email"
              autoComplete="email"
              maxLength={254}
              required
              size="lg"
              className="waitlist-signup__input"
            />
            <Button
              type="submit"
              size="lg"
              loading={formState === "submitting"}
              disabled={!turnstileSiteKey || !turnstileToken}
              rightSection={<IconArrowRight size={18} />}
              className="waitlist-signup__button"
            >
              Join beta
            </Button>
          </Group>
          <div
            ref={challengeContainerRef}
            className="waitlist-signup__challenge"
          />
        </Stack>
      </form>

      {message
        ? (
          <Alert
            color={formState === "success" ? "green" : "red"}
            icon={formState === "success"
              ? <IconCheck size={18} />
              : <IconX size={18} />}
            variant="light"
            className="waitlist-signup__alert"
          >
            <Text size="sm">{message}</Text>
          </Alert>
        )
        : (
          <Text size="sm" className="waitlist-signup__fineprint">
            We will only use your email for Naturebook beta updates and invites.
          </Text>
        )}
    </Stack>
  );
}
