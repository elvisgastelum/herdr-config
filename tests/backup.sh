#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "$repo/tests/.backup-test.XXXXXX")
trap 'rm -rf -- "$root"' 0
trap 'exit 1' 1 2 3 15
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$root/home" "$root/xdg/herdr" "$root/bin"
config=$root/xdg/herdr/config.toml
backups=$root/xdg/herdr/backups
printf 'current\n' > "$config"
cat > "$root/bin/fzf" <<'FZF'
#!/bin/sh
[ "${FZF_CANCEL:-0}" = 0 ] || exit 1
if [ "${FZF_CHOICE:-first}" = invalid ]; then printf 'config.toml.bak.INVALID\tbad\n'; exit 0; fi
if [ "${FZF_CHOICE:-first}" = unlisted ]; then
    cat > "$FZF_TABLE_OUTPUT"
    printf 'forged backup\n' > "$FZF_BACKUPS/$FZF_FORGED_NAME"
    printf '%s\tforged\t0\n' "$FZF_FORGED_NAME"
    exit 0
fi
if [ "${FZF_CHOICE:-first}" = utility ]; then grep '^herdr-config' | head -n 1; exit 0; fi
if [ -n "${FZF_TARGET:-}" ]; then grep "^${FZF_TARGET}$(printf '\t')" | head -n 1; else sed -n '2p'; fi
FZF
cat > "$root/bin/herdr" <<'HERDR'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = server ] && [ "$2" = reload-config ] || exit 89
exit "${HERDR_STATUS:-0}"
HERDR
chmod +x "$root/bin/fzf" "$root/bin/herdr"
run() { HOME="$root/home" XDG_CONFIG_HOME="$root/xdg" PATH="$root/bin:$PATH" sh "$repo/bin/herdr-config" "$@"; }
run backup || fail 'manual backup failed'
set -- "$backups"/config.toml.bak.*
[ "$#" -eq 1 ] && [ -f "$1" ] && cmp -s "$config" "$1" || fail 'manual config snapshot missing'
[ ! -e "$root/xdg/herdr/config.toml.bak."* ] || fail 'legacy adjacent backup created'
first=$1
printf 'new config\n' > "$config"
run backup || fail 'second snapshot failed'
set -- "$backups"/config.toml.bak.*
[ "$#" -eq 2 ] || fail 'second snapshot missing'
# Restore always creates an additional safety snapshot of the current configuration.
FZF_TARGET=${first##*/} run backup restore || fail 'restore failed'
cmp -s "$first" "$config" || fail 'restore did not select first backup'
found=0
for file in "$backups"/config.toml.bak.*; do
    if [ "$file" != "$first" ] && [ -f "$file" ] && grep -q 'new config' "$file"; then found=1; fi
done
[ "$found" -eq 1 ] || fail 'restore did not safeguard current config'
touch -t 202001010000 "$first"
for file in "$backups"/config.toml.bak.*; do
    [ "$file" = "$first" ] || touch -t 202101010000 "$file"
done
printf 'unchanged\n' > "$config"
# A missing fzf must fail before making a safety snapshot.
mkdir -p "$root/no-fzf"
if HOME="$root/home" XDG_CONFIG_HOME="$root/xdg" PATH="$root/no-fzf:/usr/bin:/bin" \
    sh "$repo/bin/herdr-config" backup restore; then
    fail 'missing fzf accepted'
fi
if ( FZF_CANCEL=1; export FZF_CANCEL; run backup restore ); then fail 'cancel accepted'; fi
[ "$(cat "$config")" = unchanged ] || fail 'cancel changed config'
if ( FZF_CHOICE=invalid; export FZF_CHOICE; run backup restore ); then fail 'invalid selection accepted'; fi
[ "$(cat "$config")" = unchanged ] || fail 'invalid selection changed config'
if ( FZF_CHOICE=unlisted; FZF_FORGED_NAME=config.toml.bak.FORGED
     FZF_BACKUPS=$backups; FZF_TABLE_OUTPUT="$root/displayed"; export FZF_CHOICE FZF_FORGED_NAME FZF_BACKUPS FZF_TABLE_OUTPUT
     run backup restore ); then fail 'unlisted valid selection accepted'; fi
[ "$(cat "$config")" = unchanged ] || fail 'unlisted selection changed config'
[ -f "$backups/config.toml.bak.FORGED" ] || fail 'unlisted backup changed'
# Cleaning refuses unknown entries and links before deleting anything.
printf 'older\n' > "$backups/herdr-config.bak.AAAAAA"
printf 'newer\n' > "$backups/herdr-config.bak.BBBBBB"
touch -t 202001010000 "$backups/herdr-config.bak.AAAAAA"
touch -t 202101010000 "$backups/herdr-config.bak.BBBBBB"
printf 'old skill\n' > "$backups/herdr-config-skill.bak.AAAAAA"
printf 'new skill\n' > "$backups/herdr-config-skill.bak.BBBBBB"
touch -t 202001010000 "$backups/herdr-config-skill.bak.AAAAAA"
touch -t 202101010000 "$backups/herdr-config-skill.bak.BBBBBB"
printf 'legacy\n' > "$root/xdg/herdr/config.toml.bak.OLDOLD"
printf 'unknown\n' > "$backups/notes"
if run backup --clean; then fail 'unknown file accepted'; fi
[ -f "$backups/herdr-config.bak.AAAAAA" ] || fail 'partial cleanup on unknown file'
rm "$backups/notes"
ln -s "$root/away" "$backups/config.toml.bak.CCCCCC"
if run backup --clean; then fail 'symlink accepted'; fi
[ -L "$backups/config.toml.bak.CCCCCC" ] || fail 'symlink changed'
rm "$backups/config.toml.bak.CCCCCC"
run backup --clean || fail 'clean failed'
[ ! -e "$backups/herdr-config.bak.AAAAAA" ] && [ -f "$backups/herdr-config.bak.BBBBBB" ] || fail 'utility retention wrong'
[ ! -e "$backups/herdr-config-skill.bak.AAAAAA" ] && [ -f "$backups/herdr-config-skill.bak.BBBBBB" ] || fail 'skill retention wrong'
count=0
for file in "$backups"/config.toml.bak.*; do [ ! -f "$file" ] || count=$((count + 1)); done
[ "$count" -eq 1 ] || fail 'config retention wrong'
[ ! -e "$first" ] || fail 'old config snapshot retained'
[ "$(cat "$config")" = unchanged ] || fail 'clean changed config'
[ -f "$root/xdg/herdr/config.toml.bak.OLDOLD" ] || fail 'clean removed legacy adjacent backup'
# An old source mtime must not make a newly created backup look old; spaces must
# not break retention or the restore table's displayed creation timestamp.
space_xdg="$root/xdg with spaces"
mkdir -p "$space_xdg/herdr/backups"
space_config="$space_xdg/herdr/config.toml"
printf 'recent snapshot\n' > "$space_config"
touch -t 202001010000 "$space_config"
printf 'prior snapshot\n' > "$space_xdg/herdr/backups/config.toml.bak.PRIOR1"
touch -t 202101010000 "$space_xdg/herdr/backups/config.toml.bak.PRIOR1"
space_run() { HOME="$root/home" XDG_CONFIG_HOME="$space_xdg" PATH="$root/bin:$PATH" sh "$repo/bin/herdr-config" "$@"; }
space_run backup || fail 'space path backup failed'
set -- "$space_xdg/herdr/backups"/config.toml.bak.*
[ "$#" -eq 2 ] || fail 'space path snapshot missing'
for file do [ "${file##*/}" = config.toml.bak.PRIOR1 ] || newest=$file; done
year=$(stat -f '%Sm' -t '%Y' "$newest" 2>/dev/null || stat -c '%y' "$newest" | cut -c1-4)
[ "$year" = "$(date +%Y)" ] || fail 'snapshot kept source mtime'
if ( FZF_CHOICE=unlisted; FZF_FORGED_NAME=config.toml.bak.FORGED
     FZF_BACKUPS="$space_xdg/herdr/backups"; FZF_TABLE_OUTPUT="$root/space-displayed"; export FZF_CHOICE FZF_FORGED_NAME FZF_BACKUPS FZF_TABLE_OUTPUT
     space_run backup restore ); then fail 'space path unlisted backup accepted'; fi
# The table uses the snapshot timestamp, not the preserved source mtime.
if ! grep "${newest##*/}.*$(date +%Y)" "$root/space-displayed" >/dev/null; then fail 'table displayed source mtime'; fi
# The forged backup was created only to test restore selection; remove the fixture.
rm "$space_xdg/herdr/backups/config.toml.bak.FORGED"
space_run backup --clean || fail 'space path clean failed'
[ -f "$newest" ] && [ ! -e "$space_xdg/herdr/backups/config.toml.bak.PRIOR1" ] || fail 'space path kept wrong backup'
# Equal timestamps provide no reliable newest ordering: retain all candidates.
printf 'tie one\n' > "$space_xdg/herdr/backups/config.toml.bak.TIEONE"
printf 'tie two\n' > "$space_xdg/herdr/backups/config.toml.bak.TIETWO"
touch -t 202201010000 "$newest" "$space_xdg/herdr/backups/config.toml.bak.TIEONE" "$space_xdg/herdr/backups/config.toml.bak.TIETWO"
space_run backup --clean || fail 'tie clean failed'
[ -f "$newest" ] && [ -f "$space_xdg/herdr/backups/config.toml.bak.TIEONE" ] &&
    [ -f "$space_xdg/herdr/backups/config.toml.bak.TIETWO" ] || fail 'tie deleted backups'
# Empty backup collection cannot restore or mutate current config.
mkdir -p "$root/empty/herdr"
printf 'empty current\n' > "$root/empty/herdr/config.toml"
if HOME="$root/home" XDG_CONFIG_HOME="$root/empty" PATH="$root/bin:$PATH" \
    sh "$repo/bin/herdr-config" backup restore; then fail 'empty restore accepted'; fi
[ "$(cat "$root/empty/herdr/config.toml")" = 'empty current' ] || fail 'empty restore changed config'
status=0
( HERDR_STATUS=37; export HERDR_STATUS; run reload ) || status=$?
[ "$status" -eq 37 ] || fail 'reload status lost'
run reload || fail 'reload failed'
printf 'ok: manual backup, safe restore, cleanup and reload\n'
