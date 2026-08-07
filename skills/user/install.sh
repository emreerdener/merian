#!/usr/bin/env bash
set -euo pipefail

user_skill_usage() {
  cat <<'USAGE'
Usage: bash skills/user/install.sh [--check|--apply]

  --check  Verify that both user skills point to this tracked source.
  --apply  Back up conflicting current/legacy installs and create symlinks.

Optional test/administration overrides:
  CODEX_USER_SKILLS_DIR    Destination root (default: $HOME/.agents/skills)
  CODEX_LEGACY_SKILLS_DIR  Legacy root (default: $CODEX_HOME/skills or
                           $HOME/.codex/skills)
  CODEX_SKILL_BACKUP_DIR   Recoverable backup root
USAGE
}

user_skill_mode="check"
case "${1:-}" in
  "" | --check)
    ;;
  --apply)
    user_skill_mode="apply"
    ;;
  -h | --help)
    user_skill_usage
    exit 0
    ;;
  *)
    user_skill_usage >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  user_skill_usage >&2
  exit 2
fi

user_skill_source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
user_skill_home="${HOME:?HOME must resolve the user skill location}"
user_skill_target_root="${CODEX_USER_SKILLS_DIR:-$user_skill_home/.agents/skills}"
user_skill_legacy_root="${CODEX_LEGACY_SKILLS_DIR:-${CODEX_HOME:-$user_skill_home/.codex}/skills}"
user_skill_backup_root="${CODEX_SKILL_BACKUP_DIR:-$user_skill_home/.agents/skill-backups}"
user_skill_names=(supabase supabase-postgres-best-practices)

user_skill_require_safe_root() {
  local user_skill_label="$1"
  local user_skill_root="$2"
  case "$user_skill_root" in
    /*)
      ;;
    *)
      echo "$user_skill_label must be an absolute path: $user_skill_root" >&2
      exit 2
      ;;
  esac
  if [ "$user_skill_root" = "/" ]; then
    echo "$user_skill_label must not be the filesystem root." >&2
    exit 2
  fi
}

user_skill_require_safe_root "Current skill root" "$user_skill_target_root"
user_skill_require_safe_root "Legacy skill root" "$user_skill_legacy_root"
user_skill_require_safe_root "Backup root" "$user_skill_backup_root"

if [ "$user_skill_target_root" = "$user_skill_legacy_root" ]; then
  echo "Current and legacy skill roots must be different." >&2
  exit 2
fi
if [ "$user_skill_backup_root" = "$user_skill_target_root" ] ||
  [ "$user_skill_backup_root" = "$user_skill_legacy_root" ]; then
  echo "Backup root must differ from current and legacy skill roots." >&2
  exit 2
fi

user_skill_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

user_skill_is_current() {
  local user_skill_path="$1"
  local user_skill_source="$2"
  [ -L "$user_skill_path" ] && [ "$(readlink "$user_skill_path")" = "$user_skill_source" ]
}

for user_skill_name in "${user_skill_names[@]}"; do
  user_skill_source="$user_skill_source_root/$user_skill_name"
  user_skill_manifest="$user_skill_source/SKILL.md"

  if [ ! -f "$user_skill_manifest" ]; then
    echo "Missing source manifest: $user_skill_manifest" >&2
    exit 1
  fi
  if ! grep -Fqx "name: $user_skill_name" "$user_skill_manifest"; then
    echo "Skill name does not match its directory: $user_skill_manifest" >&2
    exit 1
  fi
  if grep -Fq "TODO" "$user_skill_manifest"; then
    echo "Unresolved TODO in $user_skill_manifest" >&2
    exit 1
  fi
done

if [ "$user_skill_mode" = "check" ]; then
  user_skill_outdated=0
  for user_skill_name in "${user_skill_names[@]}"; do
    user_skill_source="$user_skill_source_root/$user_skill_name"
    user_skill_target="$user_skill_target_root/$user_skill_name"
    user_skill_legacy="$user_skill_legacy_root/$user_skill_name"

    if user_skill_is_current "$user_skill_target" "$user_skill_source"; then
      echo "current: $user_skill_target -> $user_skill_source"
    else
      echo "update required: $user_skill_target" >&2
      user_skill_outdated=1
    fi
    if user_skill_exists "$user_skill_legacy"; then
      echo "legacy duplicate must be backed up: $user_skill_legacy" >&2
      user_skill_outdated=1
    fi
  done
  exit "$user_skill_outdated"
fi

user_skill_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
user_skill_backup_session="$user_skill_backup_root/$user_skill_timestamp-$$"
mkdir -p -- "$user_skill_target_root" "$user_skill_backup_session"

for user_skill_name in "${user_skill_names[@]}"; do
  user_skill_source="$user_skill_source_root/$user_skill_name"
  user_skill_target="$user_skill_target_root/$user_skill_name"
  user_skill_legacy="$user_skill_legacy_root/$user_skill_name"
  user_skill_target_backup="$user_skill_backup_session/current-$user_skill_name"
  user_skill_legacy_backup="$user_skill_backup_session/legacy-$user_skill_name"
  user_skill_target_changed=0

  if ! user_skill_is_current "$user_skill_target" "$user_skill_source"; then
    if user_skill_exists "$user_skill_target"; then
      mv -- "$user_skill_target" "$user_skill_target_backup"
    fi
    if ! ln -s -- "$user_skill_source" "$user_skill_target"; then
      if user_skill_exists "$user_skill_target_backup"; then
        mv -- "$user_skill_target_backup" "$user_skill_target"
      fi
      exit 1
    fi
    user_skill_target_changed=1
  fi

  if user_skill_exists "$user_skill_legacy"; then
    if ! mv -- "$user_skill_legacy" "$user_skill_legacy_backup"; then
      if [ "$user_skill_target_changed" -eq 1 ]; then
        unlink -- "$user_skill_target"
        if user_skill_exists "$user_skill_target_backup"; then
          mv -- "$user_skill_target_backup" "$user_skill_target"
        fi
      fi
      exit 1
    fi
  fi

  if ! user_skill_is_current "$user_skill_target" "$user_skill_source"; then
    echo "Failed to verify installed skill: $user_skill_target" >&2
    exit 1
  fi
  if user_skill_exists "$user_skill_legacy"; then
    echo "Legacy duplicate still exists: $user_skill_legacy" >&2
    exit 1
  fi

  echo "installed: $user_skill_target -> $user_skill_source"
done

echo "Recoverable backups, when needed: $user_skill_backup_session"
