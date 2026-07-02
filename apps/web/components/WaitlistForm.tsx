"use client";

import type { FormEvent } from "react";
import { useState } from "react";
import { Alert, Button, Group, Stack, Text, TextInput } from "@mantine/core";
import { IconArrowRight, IconCheck, IconX } from "@tabler/icons-react";

type FormState = "idle" | "submitting" | "success" | "error";

export function WaitlistForm() {
  const [email, setEmail] = useState("");
  const [formState, setFormState] = useState<FormState>("idle");
  const [message, setMessage] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setFormState("submitting");
    setMessage("");

    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ email }),
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
    }
  }

  return (
    <Stack gap="sm" id="waitlist" className="waitlist-signup">
      <form onSubmit={handleSubmit}>
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
            required
            size="lg"
            className="waitlist-signup__input"
          />
          <Button
            type="submit"
            size="lg"
            loading={formState === "submitting"}
            rightSection={<IconArrowRight size={18} />}
            className="waitlist-signup__button"
          >
            Join beta
          </Button>
        </Group>
      </form>

      {message ? (
        <Alert
          color={formState === "success" ? "green" : "red"}
          icon={
            formState === "success" ? (
              <IconCheck size={18} />
            ) : (
              <IconX size={18} />
            )
          }
          variant="light"
          className="waitlist-signup__alert"
        >
          <Text size="sm">{message}</Text>
        </Alert>
      ) : (
        <Text size="sm" className="waitlist-signup__fineprint">
          We will only use your email for Merian beta updates and invites.
        </Text>
      )}
    </Stack>
  );
}
