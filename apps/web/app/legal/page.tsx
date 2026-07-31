import type { Metadata } from "next";
import { Anchor, Paper, Stack, Text, Title } from "@mantine/core";
import { PublicPageShell } from "@/components/PublicPageShell";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "Legal",
  description: "Naturebook legal, privacy, community, and support pages.",
};

const links = [
  {
    href: "/privacy",
    title: "Privacy Policy",
    description:
      "How Naturebook collects, uses, shares, and protects information.",
  },
  {
    href: "/terms",
    title: "Terms of Service",
    description: "Rules and terms for using Naturebook and public web pages.",
  },
  {
    href: "/guidelines",
    title: "Community Guidelines",
    description: "Expectations for sharing and participating in Explore.",
  },
  {
    href: "/privacy-choices",
    title: "Privacy Choices",
    description:
      "Manage permissions, account deletion, public sharing, and understand scientific retention.",
  },
  {
    href: "/support",
    title: "Support",
    description:
      "Contact Naturebook for bugs, feature ideas, and account help.",
  },
];

export default function LegalIndexPage() {
  return (
    <PublicPageShell>
      <Paper radius="md" shadow="sm" withBorder p={{ base: "lg", sm: "xl" }}>
        <Stack gap="xl">
          <Stack gap="xs">
            <Text fw={700} c="dimmed" tt="uppercase" size="sm">
              Naturebook legal
            </Text>
            <Title order={1}>Legal and support</Title>
            <Text size="lg" c="dimmed">
              Public policies for Naturebook. Last updated{" "}
              {siteConfig.legalUpdatedAt}.
            </Text>
          </Stack>

          <ul className="legal-list">
            {links.map((item) => (
              <li key={item.href}>
                <Stack gap={2}>
                  <Anchor href={item.href} fw={700}>
                    {item.title}
                  </Anchor>
                  <Text c="dimmed">{item.description}</Text>
                </Stack>
              </li>
            ))}
          </ul>
        </Stack>
      </Paper>
    </PublicPageShell>
  );
}
