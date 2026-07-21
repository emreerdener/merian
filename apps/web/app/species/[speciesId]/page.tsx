import type { Metadata } from "next";
import Link from "next/link";
import { notFound, permanentRedirect } from "next/navigation";
import { cache, type ReactNode } from "react";
import {
  Anchor,
  Badge,
  Button,
  Card,
  Container,
  Divider,
  Group,
  Image,
  SimpleGrid,
  Stack,
  Text,
  ThemeIcon,
  Title,
} from "@mantine/core";
import {
  IconAlertTriangle,
  IconArrowLeft,
  IconArrowRight,
  IconBook2,
  IconExternalLink,
  IconLeaf,
  IconShieldCheck,
  IconSitemap,
} from "@tabler/icons-react";
import {
  fetchSpeciesDictionary,
  canonicalSpeciesDictionaryPath,
  nativeSpeciesDictionaryUrl,
  speciesDictionaryMetadataValues,
  speciesDictionaryRedirectPath,
  type WebSimilarSpecies,
  type WebSpeciesDictionaryEntry,
} from "@/lib/species";
import type { PublicSpeciesReferenceImage } from "../../../../../services/supabase/functions/_shared/publicSpeciesProjection.ts";

type SpeciesPageProps = {
  params: Promise<{
    speciesId: string;
    slug?: string;
  }>;
};

const getSpecies = cache(fetchSpeciesDictionary);

export const revalidate = 300;

export async function generateMetadata({ params }: SpeciesPageProps): Promise<Metadata> {
  const { speciesId } = await params;

  try {
    const species = await getSpecies(speciesId);
    if (!species) return missingSpeciesMetadata();

    const metadataValues = speciesDictionaryMetadataValues(species);
    const socialImage = species.referenceImages[0];
    const imageAlt = socialImage && metadataValues.socialImageUrl
      ? `${species.commonName} — ${referenceImageCaption(socialImage)}`
      : null;

    return {
      title: metadataValues.title,
      description: metadataValues.description,
      alternates: { canonical: metadataValues.canonicalPath },
      openGraph: {
        type: "website",
        title: metadataValues.title,
        description: metadataValues.description,
        url: metadataValues.canonicalPath,
        siteName: "Naturebook",
        ...(metadataValues.socialImageUrl && imageAlt
          ? { images: [{ url: metadataValues.socialImageUrl, alt: imageAlt }] }
          : {}),
      },
      twitter: {
        card: metadataValues.socialImageUrl ? "summary_large_image" : "summary",
        title: metadataValues.title,
        description: metadataValues.description,
        ...(metadataValues.socialImageUrl
          ? { images: [metadataValues.socialImageUrl] }
          : {}),
      },
    };
  } catch (error) {
    console.error("species_dictionary_metadata_fetch_failed", {
      error: error instanceof Error ? error.message : String(error),
    });
    return {
      title: "Species reference unavailable",
      robots: { index: false, follow: false },
    };
  }
}

export default async function SpeciesPage({ params }: SpeciesPageProps) {
  const { speciesId, slug } = await params;
  const species = await getSpecies(speciesId);
  if (!species) notFound();

  const redirectPath = speciesDictionaryRedirectPath(
    species.id,
    species.commonName,
    species.scientificName,
    slug,
  );
  if (redirectPath) {
    permanentRedirect(redirectPath);
  }

  const nativeURL = nativeSpeciesDictionaryUrl(species.id);
  const taxonomyRows = speciesTaxonomyRows(species);
  const conservationStatus = normalizedIucnStatus(species.iucnRedListStatus);
  const hazard = hazardPresentation(species.hazardType);
  const quality = contentQualityPresentation(species.contentQuality);
  const primaryImage = species.referenceImages[0];
  const remainingImages = species.referenceImages.slice(1);

  return (
    <Container size="md" py={{ base: "md", sm: "xl" }}>
      <Stack gap="lg">
        <Group justify="space-between" align="center" gap="md">
          <Link href="/" style={{ textDecoration: "none" }}>
            <Anchor
              component="span"
              display="inline-flex"
              style={{ alignItems: "center", gap: "6px" }}
              c="dimmed"
              size="sm"
              fw={500}
            >
              <IconArrowLeft size={16} />
              Back to Naturebook
            </Anchor>
          </Link>

          {nativeURL ? (
            <Button component="a" href={nativeURL} variant="filled" size="sm">
              Open in Naturebook
            </Button>
          ) : null}
        </Group>

        <Card withBorder shadow="sm" radius="lg" p={0}>
          {primaryImage ? (
            <ReferenceImage image={primaryImage} alt={species.commonName} hero />
          ) : (
            <Stack align="center" justify="center" mih={280} gap="sm" p="xl">
              <ThemeIcon size={64} radius="xl" variant="light" color="green">
                <IconLeaf size={34} />
              </ThemeIcon>
              <Text c="dimmed" ta="center">
                Licensed reference imagery is not available for this species yet.
              </Text>
            </Stack>
          )}

          <Stack gap="lg" p={{ base: "lg", sm: "xl" }} align="center">
            <Badge variant="light" color={quality.color}>{quality.label}</Badge>
            <Stack gap={4} align="center">
              <Text size="lg" c="dimmed" fs="italic" ta="center">
                {species.scientificName}
              </Text>
              <Title order={1} ta="center">{species.commonName}</Title>
              {species.alternativeCommonNames.length ? (
                <Text c="dimmed" ta="center">
                  Also known as: {species.alternativeCommonNames.join(", ")}
                </Text>
              ) : null}
            </Stack>
            {quality.message ? (
              <Text c="dimmed" size="sm" ta="center" maw={620}>
                {quality.message}
              </Text>
            ) : null}
          </Stack>
        </Card>

        {remainingImages.length ? (
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="md">
            {remainingImages.map((image) => (
              <Card key={image.url} withBorder shadow="sm" radius="lg" p={0}>
                <ReferenceImage image={image} alt={species.commonName} />
              </Card>
            ))}
          </SimpleGrid>
        ) : null}

        {hazard ? (
          <InfoCard title="Safety" icon={<IconAlertTriangle size={20} />}>
            <Group gap="md" wrap="nowrap" align="flex-start">
              <ThemeIcon color={hazard.color} variant="light" radius="xl" size="lg">
                <IconAlertTriangle size={18} />
              </ThemeIcon>
              <Stack gap={2}>
                <Text fw={700}>{hazard.title}</Text>
                <Text>{hazard.message}</Text>
              </Stack>
            </Group>
          </InfoCard>
        ) : null}

        {conservationStatus || species.wikipediaOverview || species.wikipediaUrl ? (
          <InfoCard title="Overview" icon={<IconBook2 size={20} />}>
            <Stack gap="md">
              {conservationStatus ? (
                <KeyValueRow label="Conservation" value={conservationStatus} />
              ) : null}
              {species.wikipediaOverview ? <Text>{species.wikipediaOverview}</Text> : null}
              {species.wikipediaUrl ? (
                <Button
                  component="a"
                  href={species.wikipediaUrl}
                  target="_blank"
                  rel="noreferrer"
                  variant="outline"
                  w="fit-content"
                  rightSection={<IconExternalLink size={16} />}
                >
                  Read source
                </Button>
              ) : null}
            </Stack>
          </InfoCard>
        ) : null}

        {species.habitatDescription ? (
          <InfoCard title="Habitat and distribution" icon={<IconLeaf size={20} />}>
            <Text>{species.habitatDescription}</Text>
          </InfoCard>
        ) : null}

        {taxonomyRows.length ? (
          <InfoCard title="Taxonomy" icon={<IconSitemap size={20} />}>
            <Stack gap="sm">
              {taxonomyRows.map((row, index) => (
                <Stack key={row.label} gap="sm">
                  {index > 0 ? <Divider /> : null}
                  <KeyValueRow label={row.label} value={row.value} />
                </Stack>
              ))}
            </Stack>
          </InfoCard>
        ) : null}

        {species.similarSpecies.length ? (
          <InfoCard title="Similar species" icon={<IconShieldCheck size={20} />}>
            <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
              {species.similarSpecies.map((similar) => (
                <SimilarSpeciesCard
                  key={`${similar.speciesId ?? "unlinked"}-${similar.scientificName}`}
                  species={similar}
                />
              ))}
            </SimpleGrid>
          </InfoCard>
        ) : null}
      </Stack>
    </Container>
  );
}

function ReferenceImage({
  image,
  alt,
  hero = false,
}: {
  image: PublicSpeciesReferenceImage;
  alt: string;
  hero?: boolean;
}) {
  return (
    <Stack gap={0}>
      <Image
        src={image.url}
        alt={alt}
        h={hero ? { base: 340, sm: 520 } : 280}
        fit="cover"
      />
      <Text size="xs" c="dimmed" p="sm">
        {referenceImageCaption(image)}
      </Text>
    </Stack>
  );
}

function SimilarSpeciesCard({ species }: { species: WebSimilarSpecies }) {
  const path = species.speciesId
    ? canonicalSpeciesDictionaryPath(
      species.speciesId,
      species.commonName,
      species.scientificName,
    )
    : null;
  const content = (
    <Group justify="space-between" align="center" gap="md" wrap="nowrap">
      <Stack gap={0}>
        <Text fw={700}>{species.commonName ?? species.scientificName}</Text>
        <Text size="sm" c="dimmed" fs="italic">{species.scientificName}</Text>
        {species.iucnRedListStatus ? (
          <Text size="xs" c="dimmed">{normalizedIucnStatus(species.iucnRedListStatus)}</Text>
        ) : null}
      </Stack>
      {path ? <IconArrowRight size={18} /> : null}
    </Group>
  );

  return path ? (
    <Card component={Link} href={path} withBorder radius="md" p="md">
      {content}
    </Card>
  ) : (
    <Card withBorder radius="md" p="md">{content}</Card>
  );
}

function InfoCard({
  title,
  icon,
  children,
}: {
  title: string;
  icon: ReactNode;
  children: ReactNode;
}) {
  return (
    <Card withBorder shadow="sm" radius="lg" p={{ base: "md", sm: "lg" }}>
      <Stack gap="md">
        <Group gap="sm">
          <ThemeIcon variant="light" radius="xl" size="lg">{icon}</ThemeIcon>
          <Title order={2} size="h3">{title}</Title>
        </Group>
        {children}
      </Stack>
    </Card>
  );
}

function KeyValueRow({ label, value }: { label: string; value: string }) {
  return (
    <Group justify="space-between" align="flex-start" gap="md">
      <Text size="xs" c="dimmed" tt="uppercase" fw={700}>{label}</Text>
      <Text fw={600} ta="right">{value}</Text>
    </Group>
  );
}

function missingSpeciesMetadata(): Metadata {
  return {
    title: "Species not found",
    robots: { index: false, follow: false },
  };
}

function referenceImageCaption(image: PublicSpeciesReferenceImage): string {
  const source = image.source === "merian"
    ? "Naturebook"
    : image.source === "wikipedia"
      ? "Wikipedia"
      : "GBIF";
  return `${image.attribution} — ${image.license} · ${source}`;
}

function speciesTaxonomyRows(species: WebSpeciesDictionaryEntry) {
  const rows: Array<{ label: string; value: string | null }> = [
    { label: "Kingdom", value: species.taxonomy.kingdom },
    { label: "Phylum", value: species.taxonomy.phylum },
    { label: "Class", value: species.taxonomy.class },
    { label: "Order", value: species.taxonomy.order },
    { label: "Family", value: species.taxonomy.family },
    { label: "Genus", value: species.taxonomy.genus },
  ];
  return rows.flatMap((row) => row.value ? [{ label: row.label, value: row.value }] : []);
}

function normalizedIucnStatus(value?: string | null): string | null {
  const normalized = value?.trim().toLowerCase().replaceAll("_", " ");
  if (!normalized) return null;
  if (normalized.includes("not evaluated")) return "Not evaluated";
  if (normalized.includes("least concern")) return "Least concern";
  if (normalized.includes("near threatened")) return "Near threatened";
  if (normalized.includes("critically endangered")) return "Critically endangered";
  if (normalized.includes("endangered")) return "Endangered";
  if (normalized.includes("vulnerable")) return "Vulnerable";
  if (normalized.includes("extinct in the wild")) return "Extinct in the wild";
  if (normalized.includes("extinct")) return "Extinct";
  return normalized.charAt(0).toUpperCase() + normalized.slice(1);
}

function hazardPresentation(value?: string | null) {
  switch (value?.trim().toLowerCase()) {
    case "venomous":
      return { title: "Venomous", message: "Can inject venom through a bite or sting. Do not handle.", color: "red" };
    case "poisonous":
      return { title: "Toxic", message: "May be harmful if touched or consumed. Avoid contact.", color: "red" };
    case "allergenic":
      return { title: "Allergenic", message: "May trigger allergic reactions in some people.", color: "yellow" };
    case "irritant":
      return { title: "Irritant", message: "May cause skin or eye irritation on contact.", color: "yellow" };
    default:
      return null;
  }
}

function contentQualityPresentation(
  quality: WebSpeciesDictionaryEntry["contentQuality"],
) {
  switch (quality) {
    case "complete":
      return { label: "Reference profile", color: "green", message: null };
    case "sparse":
      return {
        label: "Growing profile",
        color: "yellow",
        message: "This public species profile is still being enriched as reliable reference data becomes available.",
      };
    case "needs_enrichment":
      return {
        label: "Early profile",
        color: "gray",
        message: "Naturebook has a limited public reference profile for this species so far.",
      };
  }
}
