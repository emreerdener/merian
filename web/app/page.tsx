import { Anchor, Button, Group, Stack, Text, Title } from "@mantine/core";
import { IconArrowRight } from "@tabler/icons-react";
import { PublicPageShell } from "@/components/PublicPageShell";

export default function HomePage() {
  const appStoreUrl = process.env.NEXT_PUBLIC_APP_STORE_URL;

  return (
    <PublicPageShell size="sm">
      <Stack gap="xl">
        <Stack gap="sm">
          <Text fw={700} c="dimmed" tt="uppercase" size="sm">
            Merian
          </Text>
          <Title order={1}>Ecological discoveries, shared from the field.</Title>
          <Text size="lg" c="dimmed">
            Public Explore pages are coming online here. Shared discoveries open in Merian
            when the app is installed and provide a web preview for everyone else.
          </Text>
        </Stack>

        <Group>
          {appStoreUrl ? (
            <Button component="a" href={appStoreUrl} rightSection={<IconArrowRight size={18} />}>
              Get Merian
            </Button>
          ) : null}
          <Anchor href="/legal">
            Legal and support
          </Anchor>
        </Group>
      </Stack>
    </PublicPageShell>
  );
}
