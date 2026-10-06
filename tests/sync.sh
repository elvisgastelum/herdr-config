#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
base_path=$PATH
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
root=$(mktemp -d "$repo/tests/.sync-test.XXXXXX")
trap 'rm -rf -- "$root"' 0
trap 'exit 1' 1 2 3 15
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
# A local bare remote exercises real clone/pull behavior without network or SSH.
mkdir -p "$root/seed" "$root/home" "$root/xdg"
git init -q "$root/seed"
git -C "$root/seed" config user.name Test
git -C "$root/seed" config user.email test@example.invalid
git -C "$root/seed" checkout -qb main
cp "$repo/install.sh" "$root/seed/install.sh"
mkdir "$root/seed/bin"
cp "$repo/bin/herdr-config" "$root/seed/bin/herdr-config"
mkdir -p "$root/seed/skills/herdr-config"
cp "$repo/skills/herdr-config/SKILL.md" "$root/seed/skills/herdr-config/SKILL.md"
mkdir -p "$root/seed/plugins"
cp -R "$repo/plugins/port-forward" "$root/seed/plugins/port-forward"
printf 'initial config\n' > "$root/seed/config.toml"
git -C "$root/seed" add .
git -C "$root/seed" commit -qm initial
git clone -q --bare "$root/seed" "$root/remote.git"
git -C "$root/seed" remote add origin "$root/remote.git"
# A fake herdr records argv and serves a plugin list from a fixture file; the
# real Herdr server and plugin registry are never touched.
mkdir "$root/herdr-bin"
cat > "$root/herdr-bin/herdr" <<'HERDR'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_HERDR_CALLS"
case $1:$2 in
    plugin:list) cat "$FAKE_HERDR_PLUGINS" ;;
    plugin:link)
        [ -z "${FAKE_HERDR_LINK_FAIL:-}" ] || { printf 'link refused\n' >&2; exit 3; }
        printf '{"result":{"plugins":[{"plugin_id":"elvisgastelum.port-forward","enabled":true,"plugin_root":"%s","source":{"kind":"local"}}]}}\n' "$3" > "$FAKE_HERDR_PLUGINS" ;;
    *) exit 64 ;;
esac
HERDR
chmod +x "$root/herdr-bin/herdr"
FAKE_HERDR_CALLS=$root/herdr-calls FAKE_HERDR_PLUGINS=$root/herdr-plugins.json
export FAKE_HERDR_CALLS FAKE_HERDR_PLUGINS
: > "$FAKE_HERDR_CALLS"
printf '{"result":{"plugins":[]}}\n' > "$FAKE_HERDR_PLUGINS"
link_calls() { grep -c '^plugin link ' "$FAKE_HERDR_CALLS" || :; }
run() {
    HOME="$root/home" XDG_CONFIG_HOME="$root/xdg" XDG_DATA_HOME="${SYNC_DATA_HOME:-$root/data}" \
        HERDR_CONFIG_REPOSITORY="$root/remote.git" PATH="$root/herdr-bin:$PATH" \
        sh "$repo/bin/herdr-config" sync
}
mkdir -p "$root/outside-data"
ln -s "$root/outside-data" "$root/linked-data"
if ( SYNC_DATA_HOME="$root/linked-data" run ); then fail 'symlinked data home accepted'; fi
[ ! -e "$root/outside-data/herdr-config" ] || fail 'symlinked data home wrote outside'
run || fail 'initial clone failed'
[ "$(git -C "$root/data/herdr-config" branch --show-current)" = main ] || fail 'wrong branch'
[ "$(cat "$root/xdg/herdr/config.toml")" = 'initial config' ] || fail 'initial deploy'
[ -x "$root/home/.local/bin/herdr-config" ] || fail 'utility not executable'
cmp -s "$repo/skills/herdr-config/SKILL.md" "$root/home/.agents/skills/herdr-config/SKILL.md" || fail 'initial skill not installed'
plugin_dir=$(cd -P -- "$root/data/herdr-config/plugins/port-forward" && pwd -P)
grep -qxF "plugin link $plugin_dir --enabled" "$FAKE_HERDR_CALLS" || fail 'initial sync did not link plugin from checkout'
printf 'next config\n' > "$root/seed/config.toml"
git -C "$root/seed" add config.toml
git -C "$root/seed" commit -qm next
git -C "$root/seed" push -q origin main
# A checkout hook and ambient global Git config must not execute code during sync.
mkdir -p "$root/hooks" "$root/data/herdr-config/.git/hooks"
printf '#!/bin/sh\nprintf hook > "%s"\n' "$root/hook-ran" > "$root/hooks/post-merge"
cp "$root/hooks/post-merge" "$root/data/herdr-config/.git/hooks/post-merge"
chmod +x "$root/hooks/post-merge" "$root/data/herdr-config/.git/hooks/post-merge"
printf '[core]\n\thooksPath = %s\n\tfsmonitor = %s\n' "$root/hooks" "$root/hooks/post-merge" > "$root/hostile.gitconfig"
( GIT_CONFIG_GLOBAL="$root/hostile.gitconfig" GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$root/hooks" \
    run ) || fail 'fast-forward with ambient Git config failed'
[ ! -e "$root/hook-ran" ] || fail 'ambient Git config or checkout hook executed'
[ "$(cat "$root/xdg/herdr/config.toml")" = 'next config' ] || fail 'updated deploy'
[ -f "$root/home/.agents/skills/herdr-config/SKILL.md" ] || fail 'sync removed skill'
[ "$(cat "$root/xdg/herdr/backups/config.toml".bak.*)" = 'initial config' ] || fail 'missing backup'
[ "$(link_calls)" -eq 1 ] || fail 'already linked plugin was linked again'
# Inject a pull failure while retaining a valid origin and checkout.
mkdir "$root/bin"
cat > "$root/bin/git" <<'GIT'
#!/bin/sh
for arg do
    if [ "$arg" = pull ]; then exit 42; fi
done
exec "$GIT_REAL" "$@"
GIT
chmod +x "$root/bin/git"
if ( GIT_REAL="$(command -v git)" PATH="$root/bin:$PATH" run ); then fail 'failed pull accepted'; fi
[ "$(cat "$root/xdg/herdr/config.toml")" = 'next config' ] || fail 'pull failure deployed config'
printf 'pending config\n' > "$root/seed/config.toml"
git -C "$root/seed" add config.toml
git -C "$root/seed" commit -qm pending
git -C "$root/seed" push -q origin main
# Neither untracked nor nonconflicting tracked edits may be executed after pulling.
printf 'personal notes\n' > "$root/data/herdr-config/local-note"
if run; then fail 'dirty untracked checkout accepted'; fi
[ "$(cat "$root/data/herdr-config/local-note")" = 'personal notes' ] || fail 'untracked file changed'
[ "$(cat "$root/xdg/herdr/config.toml")" = 'next config' ] || fail 'dirty checkout deployed config'
[ "$(git -C "$root/data/herdr-config" rev-parse HEAD)" = "$(git -C "$root/seed" rev-parse HEAD^)" ] || fail 'dirty checkout pulled'
# Move the fixture note aside; also check an unrelated tracked edit by itself.
mv "$root/data/herdr-config/local-note" "$root/local-note"
printf '# local comment\n' >> "$root/data/herdr-config/install.sh"
if run; then fail 'dirty nonconflicting tracked checkout accepted'; fi
[ "$(tail -n 1 "$root/data/herdr-config/install.sh")" = '# local comment' ] || fail 'tracked edit changed'
[ "$(cat "$root/xdg/herdr/config.toml")" = 'next config' ] || fail 'dirty tracked checkout deployed config'
# A dirty conflicting checkout must not overwrite the local file or deployed config.
printf 'dirty config\n' > "$root/data/herdr-config/config.toml"
if run; then fail 'dirty conflicting pull succeeded'; fi
[ "$(cat "$root/data/herdr-config/config.toml")" = 'dirty config' ] || fail 'dirty checkout overwritten'
[ "$(cat "$root/xdg/herdr/config.toml")" = 'next config' ] || fail 'failed pull deployed config'
# Origin mismatch must be refused before deployment.
git -C "$root/data/herdr-config" remote set-url origin "$root/seed"
if run; then fail 'mismatched origin accepted'; fi
[ "$(cat "$root/xdg/herdr/config.toml")" = 'next config' ] || fail 'origin failure deployed config'
# Simulate a concurrent edit immediately after a successful pull. No installer
# may run even though Git itself returned success.
SYNC_DATA_HOME="$root/after-data" PATH="$base_path" run || fail 'second fixture clone failed'
printf 'latest config\n' > "$root/seed/config.toml"
git -C "$root/seed" add config.toml
git -C "$root/seed" commit -qm latest
git -C "$root/seed" push -q origin main
cat > "$root/bin/git" <<'GIT'
#!/bin/sh
for arg do
    if [ "$arg" = pull ]; then
        "$GIT_REAL" "$@" || exit $?
        printf 'concurrent edit\n' > "$SYNC_DATA_HOME/herdr-config/concurrent-note"
        exit 0
    fi
done
exec "$GIT_REAL" "$@"
GIT
if ( SYNC_DATA_HOME="$root/after-data" GIT_REAL="$(command -v git)" PATH="$root/bin:$PATH" run ); then
    fail 'post-pull dirty checkout accepted'
fi
[ "$(cat "$root/after-data/herdr-config/concurrent-note")" = 'concurrent edit' ] || fail 'post-pull edit changed'
[ "$(cat "$root/xdg/herdr/config.toml")" = 'pending config' ] || fail 'post-pull dirty checkout deployed'
# A plugin registered from elsewhere (another checkout or GitHub) is left alone.
printf '{"result":{"plugins":[{"plugin_id":"elvisgastelum.port-forward","enabled":true,"plugin_root":"/elsewhere/port-forward","source":{"kind":"github"}}]}}\n' > "$FAKE_HERDR_PLUGINS"
: > "$FAKE_HERDR_CALLS"
SYNC_DATA_HOME="$root/plugin-data" run > "$root/elsewhere.out" 2>&1 || fail 'plugin linked elsewhere failed sync'
[ "$(link_calls)" -eq 0 ] || fail 'plugin linked elsewhere was overwritten'
grep -q '/elsewhere/port-forward' "$root/elsewhere.out" || fail 'plugin linked elsewhere not reported'
# A failed link is reported as a sync failure, after config was deployed.
printf '{"result":{"plugins":[]}}\n' > "$FAKE_HERDR_PLUGINS"
if ( SYNC_DATA_HOME="$root/plugin-data" FAKE_HERDR_LINK_FAIL=1 run > "$root/link-fail.out" 2>&1 ); then
    fail 'failed plugin link accepted'
fi
[ "$(link_calls)" -eq 1 ] || fail 'failed link not attempted'
grep -q 'plugin link' "$root/link-fail.out" || fail 'failed link not explained'
[ "$(cat "$root/xdg/herdr/config.toml")" = 'latest config' ] || fail 'config not deployed before link failure'
printf 'ok: clone, fast-forward, backup, hook/config isolation, dirty checks, origin failure and plugin link\n'
