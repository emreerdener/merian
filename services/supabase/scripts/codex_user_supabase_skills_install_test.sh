#!/usr/bin/env bash
set -euo pipefail

installer_test_script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
installer_test_repository_root="$(cd -- "$installer_test_script_dir/../../.." && pwd -P)"
installer_test_installer="$installer_test_repository_root/skills/user/install.sh"
installer_test_tmp="$(mktemp -d "${TMPDIR:-/tmp}/merian-skill-install.XXXXXX")"
trap 'rm -rf -- "$installer_test_tmp"' EXIT

installer_test_target="$installer_test_tmp/.agents/skills"
installer_test_legacy="$installer_test_tmp/.codex/skills"
installer_test_backups="$installer_test_tmp/backups"

bash -n "$installer_test_installer"

for installer_test_skill in supabase supabase-postgres-best-practices; do
  mkdir -p -- \
    "$installer_test_target/$installer_test_skill" \
    "$installer_test_legacy/$installer_test_skill"
  printf 'current sentinel\n' > \
    "$installer_test_target/$installer_test_skill/sentinel.txt"
  printf 'legacy sentinel\n' > \
    "$installer_test_legacy/$installer_test_skill/sentinel.txt"
done

if CODEX_USER_SKILLS_DIR="$installer_test_target" \
  CODEX_LEGACY_SKILLS_DIR="$installer_test_legacy" \
  CODEX_SKILL_BACKUP_DIR="$installer_test_backups" \
  bash "$installer_test_installer" --check >/dev/null 2>&1; then
  echo "Installer check unexpectedly accepted stale skills." >&2
  exit 1
fi

CODEX_USER_SKILLS_DIR="$installer_test_target" \
  CODEX_LEGACY_SKILLS_DIR="$installer_test_legacy" \
  CODEX_SKILL_BACKUP_DIR="$installer_test_backups" \
  bash "$installer_test_installer" --apply

for installer_test_skill in supabase supabase-postgres-best-practices; do
  installer_test_expected="$installer_test_repository_root/skills/user/$installer_test_skill"
  installer_test_link="$installer_test_target/$installer_test_skill"

  [ -L "$installer_test_link" ]
  [ "$(readlink "$installer_test_link")" = "$installer_test_expected" ]
  [ ! -e "$installer_test_legacy/$installer_test_skill" ]
  [ ! -L "$installer_test_legacy/$installer_test_skill" ]
done

grep -R -Fq 'current sentinel' "$installer_test_backups"
grep -R -Fq 'legacy sentinel' "$installer_test_backups"

CODEX_USER_SKILLS_DIR="$installer_test_target" \
  CODEX_LEGACY_SKILLS_DIR="$installer_test_legacy" \
  CODEX_SKILL_BACKUP_DIR="$installer_test_backups" \
  bash "$installer_test_installer" --check

CODEX_USER_SKILLS_DIR="$installer_test_target" \
  CODEX_LEGACY_SKILLS_DIR="$installer_test_legacy" \
  CODEX_SKILL_BACKUP_DIR="$installer_test_backups" \
  bash "$installer_test_installer" --apply >/dev/null

printf 'Codex user Supabase skill installer tests passed.\n'
