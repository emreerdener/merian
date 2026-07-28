import type { ReactNode } from "react";
import { Anchor, Paper, Stack, Text, Title } from "@mantine/core";
import { PublicPageShell } from "./PublicPageShell";
import { siteConfig } from "@/lib/site";

type LegalPageProps = {
  eyebrow: string;
  title: string;
  description: string;
  lastUpdated?: string;
  children: ReactNode;
};

type LegalSectionProps = {
  title: string;
  children: ReactNode;
};

export function LegalPage({
  eyebrow,
  title,
  description,
  lastUpdated,
  children,
}: LegalPageProps) {
  return (
    <PublicPageShell>
      <Paper radius="md" shadow="sm" withBorder p={{ base: "lg", sm: "xl" }}>
        <Stack gap="xl">
          <Stack gap="xs">
            <Text fw={700} c="dimmed" tt="uppercase" size="sm">
              {eyebrow}
            </Text>
            <Title order={1}>{title}</Title>
            <Text size="lg" c="dimmed">
              {description}
            </Text>
            <Text size="sm" c="dimmed">
              Last updated: {lastUpdated ?? siteConfig.legalUpdatedAt}
            </Text>
          </Stack>

          {children}
        </Stack>
      </Paper>
    </PublicPageShell>
  );
}

export function LegalSection({ title, children }: LegalSectionProps) {
  return (
    <Stack gap="sm">
      <Title order={2} size="h3">
        {title}
      </Title>
      {children}
    </Stack>
  );
}

export function LegalList({ children }: { children: ReactNode }) {
  return <ul className="legal-list">{children}</ul>;
}

export function LegalEmailLink() {
  return (
    <Anchor href={`mailto:${siteConfig.supportEmail}`} fw={700}>
      {siteConfig.supportEmail}
    </Anchor>
  );
}
