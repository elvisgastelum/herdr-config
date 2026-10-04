#!/bin/sh
# Install only the published Herdr config.toml, without reading piped stdin.
set -eu

url=https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/config.toml
if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    config_home=$XDG_CONFIG_HOME
else
    config_home=${HOME:?HOME must be set when XDG_CONFIG_HOME is unset}/.config
fi
config_dir=$config_home/herdr
target=$config_dir/config.toml

if [ -L "$config_dir" ]; then
    printf 'Refusing symlinked Herdr config directory: %s\n' "$config_dir" >&2
    exit 1
fi
mkdir -p "$config_dir"
if [ -L "$config_dir" ] || [ -L "$target" ]; then
    printf 'Refusing symlinked Herdr config directory or file: %s\n' "$target" >&2
    exit 1
fi
tmp=$(mktemp "$target.tmp.XXXXXX")
trap 'rm -f "$tmp"' 0
trap 'exit 1' 1 2 3 15

# A failed or partial fetch must never affect an existing configuration.
if ! curl -fsSL -o "$tmp" "$url"; then
    printf 'Herdr config download failed; existing config was not changed.\n' >&2
    exit 1
fi

if [ -L "$config_dir" ] || [ -L "$target" ]; then
    printf 'Refusing symlinked Herdr config directory or file: %s\n' "$target" >&2
    exit 1
fi
if [ -e "$target" ]; then
    if [ ! -f "$target" ]; then
        printf 'Refusing to replace non-file config: %s\n' "$target" >&2
        exit 1
    fi
    # mktemp reserves a unique backup name, so repeated installs never overwrite one.
    backup=$(mktemp "$target.bak.XXXXXX")
    if ! cp -p "$target" "$backup"; then
        rm -f "$backup"
        printf 'Could not back up config; existing config was not changed.\n' >&2
        exit 1
    fi
    printf 'Backed up existing config to %s\n' "$backup"
fi

mv -f "$tmp" "$target"
printf 'Installed Herdr config at %s\n' "$target"
