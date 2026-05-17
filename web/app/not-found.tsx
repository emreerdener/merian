import { Button, Container, Stack, Text, Title } from "@mantine/core";

export default function NotFound() {
  return (
    <main>
      <Container size="sm" py={{ base: 56, sm: 96 }}>
        <Stack gap="md">
          <Title order={1}>Discovery not found</Title>
          <Text c="dimmed">
            This Explore post may have been removed, unpublished, or made private.
          </Text>
          <Button component="a" href="/" w="fit-content">
            Go to Merian
          </Button>
        </Stack>
      </Container>
    </main>
  );
}
