#!/bin/sh
# Install the published Herdr config and sync utility without reading piped stdin.
set -eu
base=https://raw.githubusercontent.com/elvisgastelum/herdr-config/main
if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    config_home=$XDG_CONFIG_HOME
else
    config_home=${HOME:?HOME must be set}/.config
fi
home=${HOME:?HOME must be set}
config_dir=$config_home/herdr
config_target=$config_dir/config.toml
backup_dir=$config_dir/backups
bin_dir=$home/.local/bin
utility_target=$bin_dir/herdr-config
skill_parent=$home/.agents/skills
skill_dir=$skill_parent/herdr-config
skill_target=$skill_dir/SKILL.md

# All three overrides must name regular files in the same trusted checkout. Sync uses
# these only after checking the checkout's origin and branch.
if [ -n "${HERDR_CONFIG_SOURCE:-}" ] || [ -n "${HERDR_UTILITY_SOURCE:-}" ] || [ -n "${HERDR_SKILL_SOURCE:-}" ]; then
    [ -n "${HERDR_CONFIG_SOURCE:-}" ] && [ -n "${HERDR_UTILITY_SOURCE:-}" ] && [ -n "${HERDR_SKILL_SOURCE:-}" ] &&
        [ -f "$HERDR_CONFIG_SOURCE" ] && [ ! -L "$HERDR_CONFIG_SOURCE" ] &&
        [ -f "$HERDR_UTILITY_SOURCE" ] && [ ! -L "$HERDR_UTILITY_SOURCE" ] &&
        [ -f "$HERDR_SKILL_SOURCE" ] && [ ! -L "$HERDR_SKILL_SOURCE" ] || {
        printf 'All three source overrides must be regular, non-symlink files.\n' >&2
        exit 1
    }
fi
# Check the caller-controlled parents as well as the immediate destinations.
# More distant system ancestors are outside this installer's ownership.
for dir in "$home" "$config_home" "$home/.local" "$config_dir" "$backup_dir" "$bin_dir" "$home/.agents" "$skill_parent" "$skill_dir"; do
    if [ -L "$dir" ]; then
        printf 'Refusing symlinked destination directory: %s\n' "$dir" >&2
        exit 1
    fi
done
mkdir -p "$config_dir" "$bin_dir" "$skill_dir"
check_destinations() {
    for path in "$config_dir" "$backup_dir" "$bin_dir" "$home/.agents" "$skill_parent" "$skill_dir" "$config_target" "$utility_target" "$skill_target"; do
        if [ -L "$path" ]; then
            printf 'Refusing symlinked destination: %s\n' "$path" >&2
            return 1
        fi
    done
    for dir in "$backup_dir" "$home/.agents" "$skill_parent" "$skill_dir"; do
        if [ -e "$dir" ] && [ ! -d "$dir" ]; then
            printf 'Refusing non-directory destination: %s\n' "$dir" >&2
            return 1
        fi
    done
    for path in "$config_target" "$utility_target" "$skill_target"; do
        if [ -e "$path" ] && [ ! -f "$path" ]; then
            printf 'Refusing non-file destination: %s\n' "$path" >&2
            return 1
        fi
    done
}
check_destinations
config_tmp=$(mktemp "$config_target.tmp.XXXXXX")
utility_tmp=
skill_tmp=
trap 'rm -f -- "$config_tmp" "$utility_tmp" "$skill_tmp"' 0
trap 'exit 1' 1 2 3 15
utility_tmp=$(mktemp "$utility_target.tmp.XXXXXX")
skill_tmp=$(mktemp "$skill_target.tmp.XXXXXX")
if [ -n "${HERDR_CONFIG_SOURCE:-}" ]; then
    cp "$HERDR_CONFIG_SOURCE" "$config_tmp" && cp "$HERDR_UTILITY_SOURCE" "$utility_tmp" &&
        cp "$HERDR_SKILL_SOURCE" "$skill_tmp" || {
        printf 'Could not stage checkout files; destinations unchanged.\n' >&2
        exit 1
    }
else
    curl -fsSL -o "$config_tmp" "$base/config.toml" &&
        curl -fsSL -o "$utility_tmp" "$base/bin/herdr-config" &&
        curl -fsSL -o "$skill_tmp" "$base/skills/herdr-config/SKILL.md" || {
        printf 'Herdr download failed; destinations unchanged.\n' >&2
        exit 1
    }
fi
chmod 755 "$utility_tmp"
check_destinations
backup_file() {
    path=$1
    kind=$2
    backup=
    if [ -e "$path" ]; then
        mkdir -p "$backup_dir" || return 1
        [ ! -L "$backup_dir" ] || return 1
        backup=$(mktemp "$backup_dir/$kind.bak.XXXXXX")
        if ! cp -p "$path" "$backup" || ! touch -m "$backup"; then
            rm -f -- "$backup"
            printf 'Could not back up %s; destinations unchanged.\n' "$path" >&2
            return 1
        fi
        printf 'Backed up existing file to %s\n' "$backup"
    fi
}
backup_file "$config_target" config.toml
backup_file "$utility_target" herdr-config
utility_backup=$backup
backup_file "$skill_target" herdr-config-skill
skill_backup=$backup
check_destinations
rollback_file() {
    target=$1
    saved=$2
    if [ -n "$saved" ]; then
        rollback_tmp=$(mktemp "$target.tmp.XXXXXX") || return 1
        if ! cp -p "$saved" "$rollback_tmp" || ! mv -f "$rollback_tmp" "$target"; then
            printf 'Rollback failed; restore %s manually from %s\n' "$target" "$saved" >&2
            return 1
        fi
    else
        rm -f -- "$target" || return 1
    fi
}
mv -f "$skill_tmp" "$skill_target"
if ! mv -f "$utility_tmp" "$utility_target"; then
    rollback_file "$skill_target" "$skill_backup" || exit 1
    printf 'Utility move failed; skill restored.\n' >&2
    exit 1
fi
if ! mv -f "$config_tmp" "$config_target"; then
    # The old config is still in place; restore both previously deployed files.
    restored=1
    rollback_file "$utility_target" "$utility_backup" || restored=0
    rollback_file "$skill_target" "$skill_backup" || restored=0
    [ "$restored" -eq 1 ] || exit 1
    printf 'Config move failed; utility and skill restored and backups preserved.\n' >&2
    exit 1
fi
printf 'Installed Herdr config at %s, sync utility at %s, and skill at %s\n' "$config_target" "$utility_target" "$skill_target"
