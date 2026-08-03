import type { Metadata } from "next";
import {
  Anchor,
  Button,
  Group,
  Paper,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import { IconMail, IconShieldLock } from "@tabler/icons-react";
import { PublicPageShell } from "@/components/PublicPageShell";
import { siteConfig, supportMailto } from "@/lib/site";

export const metadata: Metadata = {
  title: "Support",
  description: "Contact Naturebook support and find policy links.",
};

export default function SupportPage() {
  return (
    <PublicPageShell>
      <Paper radius="md" shadow="sm" withBorder p={{ base: "lg", sm: "xl" }}>
        <Stack gap="xl">
          <Stack gap="xs">
            <Text fw={700} c="dimmed" tt="uppercase" size="sm">
              Naturebook support
            </Text>
            <Title order={1}>How can we help?</Title>
            <Text size="lg" c="dimmed">
              Send bug reports, feature ideas, account questions, and privacy
              requests to the Naturebook support inbox.
            </Text>
          </Stack>

          <Group>
            <Button
              component="a"
              href={supportMailto("Naturebook support request")}
              leftSection={<IconMail size={18} />}
            >
              Email support
            </Button>
            <Button
              component="a"
              href="/privacy-choices"
              variant="light"
              leftSection={<IconShieldLock size={18} />}
            >
              Privacy choices
            </Button>
          </Group>

          <Stack gap="sm">
            <Title order={2} size="h3">
              Share a photo from Photos
            </Title>
            <Text>
              Open one photo in the iOS Photos app, tap Share, then choose
              Naturebook in the app row. Naturebook opens the photo in its
              normal crop and identification flow. If Naturebook is not
              immediately visible, scroll the app row and tap More.
            </Text>
            <Text c="dimmed" size="sm">
              You can exclude Location from Photos&apos; share Options before
              sending. Multi-photo sharing is not supported in this version.
            </Text>
          </Stack>

          <Stack gap="sm">
            <Title order={2} size="h3">
              Complimentary Pro scans
            </Title>
            <Text>
              Every account includes three complimentary Pro scans with no
              calendar expiry. Naturebook uses them automatically before the
              separate daily Flash scan. Results and Settings show the
              server-verified number remaining.
            </Text>
            <Text>
              After all three are used, saved Pro results remain available and
              ordinary single-photo, standalone-audio, or description scans can
              continue under the daily Flash limit. Video, multi-item, mixed,
              and other Pro-only actions require a paid plan.
            </Text>
            <Text c="dimmed" size="sm">
              An interrupted scan may remain in flight while Naturebook safely
              checks whether it completed. Retrying the same queued scan does
              not use another complimentary scan; a proven terminal failure
              releases its hold.
            </Text>
          </Stack>

          <Stack gap="sm">
            <Title order={2} size="h3">
              Contact
            </Title>
            <Text>
              Email:{" "}
              <Anchor href={`mailto:${siteConfig.supportEmail}`} fw={700}>
                {siteConfig.supportEmail}
              </Anchor>
            </Text>
          </Stack>

          <Stack gap="sm">
            <Title order={2} size="h3">
              Useful Links
            </Title>
            <ul className="legal-list">
              <li>
                <Anchor href="/privacy">
                  Privacy Policy
                </Anchor>
              </li>
              <li>
                <Anchor href="/terms">
                  Terms of Service
                </Anchor>
              </li>
              <li>
                <Anchor href="/guidelines">
                  Community Guidelines
                </Anchor>
              </li>
              <li>
                <Anchor href="/legal">
                  Legal hub
                </Anchor>
              </li>
            </ul>
          </Stack>
        </Stack>
      </Paper>
    </PublicPageShell>
  );
}
