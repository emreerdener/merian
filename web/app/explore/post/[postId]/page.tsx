import type { Metadata } from "next";
import { notFound } from "next/navigation";
import {
  Anchor,
  Avatar,
  Badge,
  Button,
  Container,
  Group,
  Image,
  Paper,
  Stack,
  Text,
  Title
} from "@mantine/core";
import { IconArrowUpRight, IconMessageCircle, IconHeart } from "@tabler/icons-react";
import { fetchExplorePost } from "@/lib/explore";
import { compactSpeciesTitle, nativeExplorePostUrl, postTitle } from "@/lib/formatting";

type ExplorePostPageProps = {
  params: Promise<{
    postId: string;
  }>;
};

export const revalidate = 300;

export async function generateMetadata({ params }: ExplorePostPageProps): Promise<Metadata> {
  const { postId } = await params;
  const post = await fetchExplorePost(postId);

  if (!post) {
    return {
      title: "Discovery not found",
      robots: {
        index: false,
        follow: false
      }
    };
  }

  const title = postTitle(post.speciesCommonName, post.publicLocationLabel);
  const description = compactSpeciesTitle(post.speciesCommonName, post.speciesScientificName);
  const canonicalPath = `/explore/post/${post.postId}`;

  return {
    title,
    description: `${description} shared on Merian.`,
    alternates: {
      canonical: canonicalPath
    },
    openGraph: {
      type: "article",
      title,
      description: `${description} shared on Merian.`,
      url: canonicalPath,
      siteName: "Merian",
      images: [
        {
          url: post.heroImageUrl,
          alt: title
        }
      ]
    },
    twitter: {
      card: "summary_large_image",
      title,
      description: `${description} shared on Merian.`,
      images: [post.heroImageUrl]
    }
  };
}

export default async function ExplorePostPage({ params }: ExplorePostPageProps) {
  const { postId } = await params;
  const post = await fetchExplorePost(postId);

  if (!post) {
    notFound();
  }

  const title = postTitle(post.speciesCommonName, post.publicLocationLabel);
  const speciesLabel = compactSpeciesTitle(post.speciesCommonName, post.speciesScientificName);
  const appStoreUrl = process.env.NEXT_PUBLIC_APP_STORE_URL;

  return (
    <main>
      <Container size="lg" py={{ base: 20, sm: 48 }}>
        <Paper radius="lg" shadow="md" withBorder p={{ base: "md", sm: "xl" }}>
          <Stack gap="xl">
            <Stack gap="xs">
              <Text fw={700} c="dimmed" tt="uppercase" size="sm">
                Merian Explore
              </Text>
              <Title order={1}>{title}</Title>
              <Text size="lg" c="dimmed">
                {speciesLabel}
              </Text>
            </Stack>

            <Image
              src={post.heroImageUrl}
              alt={title}
              radius="md"
              fit="cover"
              mah={620}
              fallbackSrc="/image-placeholder.svg"
            />

            <Group justify="space-between" align="center" gap="md">
              <Group gap="sm">
                <Avatar src={post.authorAvatarUrl} alt={post.authorName} radius="xl" />
                <Stack gap={0}>
                  <Text fw={700}>{post.authorName}</Text>
                  <Text size="sm" c="dimmed">
                    Shared on Merian
                  </Text>
                </Stack>
              </Group>

              <Group gap="xs">
                <Badge leftSection={<IconHeart size={13} />} variant="light">
                  {post.likeCount}
                </Badge>
                <Badge leftSection={<IconMessageCircle size={13} />} variant="light" color="gray">
                  {post.commentCount}
                </Badge>
              </Group>
            </Group>

            <Group>
              <Button
                component="a"
                href={nativeExplorePostUrl(post.postId)}
                rightSection={<IconArrowUpRight size={18} />}
              >
                Open in Merian
              </Button>
              {appStoreUrl ? (
                <Button component="a" href={appStoreUrl} variant="light">
                  Get the app
                </Button>
              ) : null}
            </Group>

            <Text size="sm" c="dimmed">
              Public locations are privacy-filtered by Merian.{" "}
              <Anchor href="/" fw={600}>
                Learn more about Merian
              </Anchor>
            </Text>
          </Stack>
        </Paper>
      </Container>
    </main>
  );
}
