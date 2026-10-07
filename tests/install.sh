#!/bin/sh
# Run from any directory; all effects are isolated under tests/.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
root=$(mktemp -d "$repo/tests/.install-test.XXXXXX")
trap 'rm -rf -- "$root"' 0
trap 'exit 1' 1 2 3 15
mkdir -p "$root/bin"
cat > "$root/bin/curl" <<'CURL'
#!/bin/sh
[ "$#" -eq 4 ] && [ "$1" = -fsSL ] && [ "$2" = -o ] || exit 91
case $4 in
    https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/config.toml)
        if [ "${FETCH_FAIL:-0}" = 1 ]; then
            printf 'partial download\n' > "$3"
            exit 22
        fi
        cp "$FETCH_SOURCE" "$3" ;;
    https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/bin/herdr-config)
        if [ "${UTILITY_FAIL:-0}" = 1 ]; then
            printf 'partial utility\n' > "$3"
            exit 22
        fi
        cp "$UTILITY_SOURCE" "$3" ;;
    https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/skills/herdr-config/SKILL.md)
        [ "${SKILL_FAIL:-0}" = 0 ] || exit 22
        cp "$SKILL_SOURCE" "$3" ;;
    *) exit 91 ;;
esac
CURL
chmod +x "$root/bin/curl"
# Fail only the second deployment move, after the utility was replaced.
cat > "$root/bin/mv" <<'MV'
#!/bin/sh
if [ "${FAIL_CONFIG_MOVE:-0}" = 1 ] && [ "$3" = "$CONFIG_MOVE_TARGET" ]; then exit 73; fi
exec "$MV_REAL" "$@"
MV
chmod +x "$root/bin/mv"
MV_REAL=$(command -v mv)
export MV_REAL
printf 'new configuration\n' > "$root/new"
printf 'updated configuration\n' > "$root/updated"
# The fake utility records how install.sh invokes it and can simulate a failed sync.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "${UTILITY_CALLS:-/dev/null}"\nexit "${UTILITY_STATUS:-0}"\n' > "$root/utility"
export UTILITY_SOURCE="$root/utility" SKILL_SOURCE="$repo/skills/herdr-config/SKILL.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_same() { cmp -s "$1" "$2" || fail "different content: $1"; }
assert_backups() {
    expected=$2
    set -- "$1".bak.*
    count=0
    for backup do
        [ -f "$backup" ] || continue
        count=$((count + 1))
    done
    [ "$count" -eq "$expected" ] || fail "expected $expected backups, found $count"
}
install() {
    HOME="$root/$1" XDG_CONFIG_HOME="${2:-}" FETCH_SOURCE="$3" FETCH_FAIL="${4:-0}" \
        PATH="$root/bin:$PATH" sh "$repo/install.sh"
}
unset HERDR_CONFIG_SYNCING

mkdir -p "$root/fresh"
install fresh '' "$root/new" || fail 'fresh install failed'
assert_same "$root/new" "$root/fresh/.config/herdr/config.toml"
assert_backups "$root/fresh/.config/herdr/backups/config.toml" 0
assert_same "$root/utility" "$root/fresh/.local/bin/herdr-config"
[ -x "$root/fresh/.local/bin/herdr-config" ] || fail 'utility not executable'
assert_same "$SKILL_SOURCE" "$root/fresh/.agents/skills/herdr-config/SKILL.md"
printf 'ok: fresh install provisions utility\n'

# Install finishes by running the installed utility's sync, unless sync itself
# is running the installer.
mkdir -p "$root/sync-run" "$root/sync-guarded" "$root/sync-failure"
( UTILITY_CALLS="$root/sync-run.calls"; export UTILITY_CALLS; install sync-run '' "$root/new" ) || fail 'install with sync failed'
[ "$(cat "$root/sync-run.calls")" = sync ] || fail 'install did not run sync'
( UTILITY_CALLS="$root/sync-guarded.calls" HERDR_CONFIG_SYNCING=1; export UTILITY_CALLS HERDR_CONFIG_SYNCING
    install sync-guarded '' "$root/new" ) || fail 'guarded install failed'
[ ! -e "$root/sync-guarded.calls" ] || fail 'guarded install ran sync'
( UTILITY_CALLS="$root/sync-guarded.calls" HERDR_CONFIG_SOURCE="$root/new" HERDR_UTILITY_SOURCE="$root/utility" \
    HERDR_SKILL_SOURCE="$SKILL_SOURCE"; export UTILITY_CALLS HERDR_CONFIG_SOURCE HERDR_UTILITY_SOURCE HERDR_SKILL_SOURCE
    install sync-guarded '' "$root/new" ) || fail 'local source install failed'
[ ! -e "$root/sync-guarded.calls" ] || fail 'local source install ran sync'
if ( UTILITY_STATUS=5; export UTILITY_STATUS; install sync-failure '' "$root/new" > "$root/sync-failure.out" 2>&1 ); then
    fail 'failed sync accepted'
fi
assert_same "$root/new" "$root/sync-failure/.config/herdr/config.toml"
grep -q 'sync failed' "$root/sync-failure.out" || fail 'sync failure not reported'
printf 'ok: install runs sync, honors the sync guard, and reports sync failure\n'

mkdir -p "$root/existing/.config/herdr"
printf 'original configuration\n' > "$root/old"
cp "$root/old" "$root/existing/.config/herdr/config.toml"
touch -t 202001010000 "$root/existing/.config/herdr/config.toml"
install existing '' "$root/new" || fail 'replacement failed'
assert_same "$root/new" "$root/existing/.config/herdr/config.toml"
assert_backups "$root/existing/.config/herdr/backups/config.toml" 1
for backup in "$root/existing/.config/herdr/backups/config.toml".bak.*; do
    assert_same "$root/old" "$backup"
    year=$(stat -f '%Sm' -t '%Y' "$backup" 2>/dev/null || stat -c '%y' "$backup" | cut -c1-4)
    [ "$year" = "$(date +%Y)" ] || fail 'installer backup kept old source mtime'
done
printf 'ok: backup before replacement\n'

mkdir -p "$root/failure/.config/herdr"
cp "$root/old" "$root/failure/.config/herdr/config.toml"
if install failure '' "$root/new" 1; then fail 'fetch failure returned success'; fi
assert_same "$root/old" "$root/failure/.config/herdr/config.toml"
assert_backups "$root/failure/.config/herdr/backups/config.toml" 0
printf 'ok: failed fetch leaves existing config unchanged\n'
mkdir -p "$root/utility-failure/.config/herdr"
cp "$root/old" "$root/utility-failure/.config/herdr/config.toml"
if HOME="$root/utility-failure" FETCH_SOURCE="$root/new" UTILITY_FAIL=1 \
    PATH="$root/bin:$PATH" sh "$repo/install.sh"; then fail 'utility fetch failure returned success'; fi
assert_same "$root/old" "$root/utility-failure/.config/herdr/config.toml"
assert_backups "$root/utility-failure/.config/herdr/backups/config.toml" 0
[ ! -e "$root/utility-failure/.local/bin/herdr-config" ] || fail 'partial utility installed'
printf 'ok: failed utility fetch leaves destinations unchanged\n'

mkdir -p "$root/move-failure/.config/herdr" "$root/move-failure/.local/bin"
cp "$root/old" "$root/move-failure/.config/herdr/config.toml"
printf 'original utility\n' > "$root/old-utility"
cp "$root/old-utility" "$root/move-failure/.local/bin/herdr-config"
if HOME="$root/move-failure" FETCH_SOURCE="$root/new" FAIL_CONFIG_MOVE=1 \
    CONFIG_MOVE_TARGET="$root/move-failure/.config/herdr/config.toml" MV_REAL="$(command -v mv)" \
    PATH="$root/bin:$PATH" sh "$repo/install.sh"; then fail 'second move failure returned success'; fi
assert_same "$root/old" "$root/move-failure/.config/herdr/config.toml"
assert_same "$root/old-utility" "$root/move-failure/.local/bin/herdr-config"
assert_backups "$root/move-failure/.config/herdr/backups/config.toml" 1
assert_backups "$root/move-failure/.config/herdr/backups/herdr-config" 1
printf 'ok: second move failure rolls back utility and preserves backups\n'

mkdir -p "$root/linked-file/.config/herdr" "$root/outside-file"
cp "$root/old" "$root/outside-file/config.toml"
ln -s "$root/outside-file/config.toml" "$root/linked-file/.config/herdr/config.toml"
if install linked-file '' "$root/new"; then fail 'symlinked config accepted'; fi
assert_same "$root/old" "$root/outside-file/config.toml"
assert_backups "$root/linked-file/.config/herdr/backups/config.toml" 0
[ "$(find "$root/linked-file/.config/herdr" ! -path "$root/linked-file/.config/herdr" | wc -l | tr -d ' ')" -eq 1 ] || fail 'symlinked config gained files'
printf 'ok: symlinked config refused without backup or writes\n'

mkdir -p "$root/linked-dir/.config" "$root/outside-dir"
cp "$root/old" "$root/outside-dir/config.toml"
ln -s "$root/outside-dir" "$root/linked-dir/.config/herdr"
if install linked-dir '' "$root/new"; then fail 'symlinked herdr directory accepted'; fi
assert_same "$root/old" "$root/outside-dir/config.toml"
assert_backups "$root/outside-dir/backups/config.toml" 0
[ "$(find "$root/outside-dir" ! -path "$root/outside-dir" | wc -l | tr -d ' ')" -eq 1 ] || fail 'symlinked directory gained files'
[ -L "$root/linked-dir/.config/herdr" ] || fail 'herdr directory symlink changed'
printf 'ok: symlinked herdr directory refused without outside writes\n'
mkdir -p "$root/linked-parent" "$root/outside-parent"
ln -s "$root/outside-parent" "$root/linked-parent/.config"
if install linked-parent '' "$root/new"; then fail 'symlinked config parent accepted'; fi
[ ! -e "$root/outside-parent/herdr/config.toml" ] || fail 'symlinked parent wrote outside'
printf 'ok: symlinked config parent refused\n'
mkdir -p "$root/linked-utility/.local/bin" "$root/utility-outside"
printf 'original utility\n' > "$root/utility-outside/herdr-config"
ln -s "$root/utility-outside/herdr-config" "$root/linked-utility/.local/bin/herdr-config"
if install linked-utility '' "$root/new"; then fail 'symlinked utility accepted'; fi
[ "$(cat "$root/utility-outside/herdr-config")" = 'original utility' ] || fail 'symlink target changed'
[ ! -e "$root/linked-utility/.config/herdr/config.toml" ] || fail 'config installed despite unsafe utility'
printf 'ok: symlinked utility refused\n'

mkdir -p "$root/xdg" "$root/xdg-home"
HOME="$root/xdg-home" XDG_CONFIG_HOME="$root/xdg" FETCH_SOURCE="$root/new" \
    PATH="$root/bin:$PATH" sh "$repo/install.sh" || fail 'XDG install failed'
assert_same "$root/new" "$root/xdg/herdr/config.toml"
[ ! -e "$root/xdg-home/.config/herdr/config.toml" ] || fail 'XDG install wrote to HOME config'
printf 'ok: XDG_CONFIG_HOME respected\n'

install existing '' "$root/updated" || fail 'repeated install failed'
assert_same "$root/updated" "$root/existing/.config/herdr/config.toml"
assert_backups "$root/existing/.config/herdr/backups/config.toml" 2
found_first=0
for backup in "$root/existing/.config/herdr/backups/config.toml".bak.*; do
    if cmp -s "$root/new" "$backup"; then found_first=1; fi
done
[ "$found_first" -eq 1 ] || fail 'first install not preserved on repeat'
printf 'ok: repeated install preserves earlier backups\n'
mkdir -p "$root/skill-existing/.agents/skills/herdr-config" "$root/skill-existing/.config/herdr"
printf 'old skill\n' > "$root/skill-existing/.agents/skills/herdr-config/SKILL.md"
install skill-existing '' "$root/new" || fail 'existing skill install failed'
assert_same "$SKILL_SOURCE" "$root/skill-existing/.agents/skills/herdr-config/SKILL.md"
[ "$(cat "$root/skill-existing/.config/herdr/backups/herdr-config-skill.bak."*)" = 'old skill' ] || fail 'skill backup missing'
mkdir -p "$root/skill-linked/.agents/skills/herdr-config" "$root/skill-outside"
printf 'outside\n' > "$root/skill-outside/SKILL.md"
ln -s "$root/skill-outside/SKILL.md" "$root/skill-linked/.agents/skills/herdr-config/SKILL.md"
if install skill-linked '' "$root/new"; then fail 'symlinked skill accepted'; fi
[ "$(cat "$root/skill-outside/SKILL.md")" = outside ] || fail 'skill symlink followed'
[ ! -e "$root/skill-linked/.config/herdr/config.toml" ] || fail 'config installed despite skill symlink'
mkdir -p "$root/skill-failure/.config/herdr"
printf 'original\n' > "$root/skill-failure/.config/herdr/config.toml"
if ( SKILL_FAIL=1; export SKILL_FAIL; install skill-failure '' "$root/new" ); then fail 'skill fetch failure accepted'; fi
[ "$(cat "$root/skill-failure/.config/herdr/config.toml")" = original ] || fail 'skill fetch failure changed config'
mkdir -p "$root/skill-rollback/.agents/skills/herdr-config" "$root/skill-rollback/.config/herdr"
printf 'old skill\n' > "$root/skill-rollback/.agents/skills/herdr-config/SKILL.md"
if ( FAIL_CONFIG_MOVE=1 CONFIG_MOVE_TARGET="$root/skill-rollback/.config/herdr/config.toml"; export FAIL_CONFIG_MOVE CONFIG_MOVE_TARGET; install skill-rollback '' "$root/new" ); then fail 'config failure accepted'; fi
[ "$(cat "$root/skill-rollback/.agents/skills/herdr-config/SKILL.md")" = 'old skill' ] || fail 'skill rollback failed'
printf 'ok: skill provisioning, backup, symlink, fetch and rollback\n'

# The README one-liner pipes the installer into bash. A full stream installs and
# syncs; a truncated stream must fail to parse instead of running partially.
mkdir -p "$root/piped" "$root/truncated"
( UTILITY_CALLS="$root/piped.calls"; export UTILITY_CALLS
    HOME="$root/piped" FETCH_SOURCE="$root/new" FETCH_FAIL=0 PATH="$root/bin:$PATH" bash < "$repo/install.sh" ) ||
    fail 'piped install failed'
assert_same "$root/new" "$root/piped/.config/herdr/config.toml"
[ "$(cat "$root/piped.calls")" = sync ] || fail 'piped install did not run sync'
head -n 40 "$repo/install.sh" | HOME="$root/truncated" FETCH_SOURCE="$root/new" PATH="$root/bin:$PATH" bash 2>/dev/null || :
[ ! -e "$root/truncated/.config" ] && [ ! -e "$root/truncated/.local" ] || fail 'truncated piped installer ran partially'
printf 'ok: piped bash install and truncated stream\n'
