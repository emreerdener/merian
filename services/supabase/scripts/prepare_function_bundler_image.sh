#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$script_dir/require_supabase_cli_version.sh"
# Coupled to the reviewed CLI 2.109.1 image. Keep the same tag across Supabase's
# official ECR, GHCR and Docker Hub mirrors; never fall back to latest.
image=supabase/edge-runtime:v1.74.2
canonical="public.ecr.aws/$image"
# The CLI can fall back to API bundling when Docker is absent. Fail first so the
# function-local deno.json and shared frozen dependencies.lock stay mounted.
docker info >/dev/null
if docker image inspect "$canonical" >/dev/null 2>&1; then
  exit 0
fi
for source in "$canonical" "ghcr.io/$image" "$image"; do
  if docker pull "$source"; then
    if [ "$source" != "$canonical" ]; then
      docker tag "$source" "$canonical"
    fi
    docker image inspect "$canonical" >/dev/null
    echo "Prepared pinned local Function bundler from $source."
    exit 0
  fi
  echo "Bundler image unavailable from $source; trying the next reviewed mirror." >&2
done
echo "All reviewed Function bundler registries failed; deployment stopped." >&2
exit 1
