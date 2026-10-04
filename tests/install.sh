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
[ "$#" -eq 4 ] && [ "$1" = -fsSL ] && [ "$2" = -o ] &&
    [ "$4" = https://raw.githubusercontent.com/elvisgastelum/herdr-config/main/config.toml ] || exit 91
if [ "${FETCH_FAIL:-0}" = 1 ]; then
    printf 'partial download\n' > "$3"
    exit 22
fi
cp "$FETCH_SOURCE" "$3"
CURL
chmod +x "$root/bin/curl"
printf 'new configuration\n' > "$root/new"
printf 'updated configuration\n' > "$root/updated"

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

mkdir -p "$root/fresh"
install fresh '' "$root/new" || fail 'fresh install failed'
assert_same "$root/new" "$root/fresh/.config/herdr/config.toml"
assert_backups "$root/fresh/.config/herdr/config.toml" 0
printf 'ok: fresh install\n'

mkdir -p "$root/existing/.config/herdr"
printf 'original configuration\n' > "$root/old"
cp "$root/old" "$root/existing/.config/herdr/config.toml"
install existing '' "$root/new" || fail 'replacement failed'
assert_same "$root/new" "$root/existing/.config/herdr/config.toml"
assert_backups "$root/existing/.config/herdr/config.toml" 1
for backup in "$root/existing/.config/herdr/config.toml".bak.*; do
    assert_same "$root/old" "$backup"
done
printf 'ok: backup before replacement\n'

mkdir -p "$root/failure/.config/herdr"
cp "$root/old" "$root/failure/.config/herdr/config.toml"
if install failure '' "$root/new" 1; then fail 'fetch failure returned success'; fi
assert_same "$root/old" "$root/failure/.config/herdr/config.toml"
assert_backups "$root/failure/.config/herdr/config.toml" 0
printf 'ok: failed fetch leaves existing config unchanged\n'

mkdir -p "$root/linked-file/.config/herdr" "$root/outside-file"
cp "$root/old" "$root/outside-file/config.toml"
ln -s "$root/outside-file/config.toml" "$root/linked-file/.config/herdr/config.toml"
if install linked-file '' "$root/new"; then fail 'symlinked config accepted'; fi
assert_same "$root/old" "$root/outside-file/config.toml"
assert_backups "$root/linked-file/.config/herdr/config.toml" 0
[ "$(find "$root/linked-file/.config/herdr" ! -path "$root/linked-file/.config/herdr" | wc -l | tr -d ' ')" -eq 1 ] || fail 'symlinked config gained files'
printf 'ok: symlinked config refused without backup or writes\n'

mkdir -p "$root/linked-dir/.config" "$root/outside-dir"
cp "$root/old" "$root/outside-dir/config.toml"
ln -s "$root/outside-dir" "$root/linked-dir/.config/herdr"
if install linked-dir '' "$root/new"; then fail 'symlinked herdr directory accepted'; fi
assert_same "$root/old" "$root/outside-dir/config.toml"
assert_backups "$root/outside-dir/config.toml" 0
[ "$(find "$root/outside-dir" ! -path "$root/outside-dir" | wc -l | tr -d ' ')" -eq 1 ] || fail 'symlinked directory gained files'
[ -L "$root/linked-dir/.config/herdr" ] || fail 'herdr directory symlink changed'
printf 'ok: symlinked herdr directory refused without outside writes\n'

mkdir -p "$root/xdg" "$root/xdg-home"
HOME="$root/xdg-home" XDG_CONFIG_HOME="$root/xdg" FETCH_SOURCE="$root/new" \
    PATH="$root/bin:$PATH" sh "$repo/install.sh" || fail 'XDG install failed'
assert_same "$root/new" "$root/xdg/herdr/config.toml"
[ ! -e "$root/xdg-home/.config/herdr/config.toml" ] || fail 'XDG install wrote to HOME config'
printf 'ok: XDG_CONFIG_HOME respected\n'

install existing '' "$root/updated" || fail 'repeated install failed'
assert_same "$root/updated" "$root/existing/.config/herdr/config.toml"
assert_backups "$root/existing/.config/herdr/config.toml" 2
found_first=0
for backup in "$root/existing/.config/herdr/config.toml".bak.*; do
    if cmp -s "$root/new" "$backup"; then found_first=1; fi
done
[ "$found_first" -eq 1 ] || fail 'first install not preserved on repeat'
printf 'ok: repeated install preserves earlier backups\n'
