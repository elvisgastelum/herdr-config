#!/bin/sh
# Offline tests for plugins/port-forward: fake ssh and herdr only, never a real host.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
script=$repo/plugins/port-forward/port-forward
root=$(mktemp -d "$repo/tests/.port-forward-test.XXXXXX")
cleanup() {
    for file in "$root"/state/*.pid "$root"/decoy.pid; do
        [ -f "$file" ] || continue
        kill "$(cat "$file")" 2>/dev/null || :
    done
    rm -rf -- "$root"
}
trap cleanup 0
trap 'exit 1' 1 2 3 15
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
mkdir -p "$root/bin" "$root/config" "$root/state"
specs=$root/config/forwards.tsv
calls=$root/ssh-calls
toasts=$root/toasts
cat > "$root/bin/ssh" <<'SSH'
#!/bin/sh
for last; do :; done
printf '%s\n' "$*" >> "$FAKE_SSH_CALLS"
if [ "$last" = "${FAKE_SSH_FAIL:-}" ]; then
    printf 'ssh: connect to host %s port 22: Connection refused\n' "$last" >&2
    exit 255
fi
trap 'kill "$child" 2>/dev/null; exit 0' TERM INT HUP
sleep 300 &
child=$!
wait "$child"
SSH
cat > "$root/bin/herdr" <<'HERDR'
#!/bin/sh
printf '%s\n' "$*" >> "$FAKE_HERDR_CALLS"
HERDR
chmod +x "$root/bin/ssh" "$root/bin/herdr"
FAKE_SSH_CALLS=$calls FAKE_HERDR_CALLS=$toasts
HERDR_PLUGIN_CONFIG_DIR=$root/config HERDR_PLUGIN_STATE_DIR=$root/state
PF_SSH=$root/bin/ssh PF_START_WAIT=5
export FAKE_SSH_CALLS FAKE_HERDR_CALLS HERDR_PLUGIN_CONFIG_DIR HERDR_PLUGIN_STATE_DIR PF_SSH PF_START_WAIT
unset HERDR_BIN_PATH 2>/dev/null || :
pf() { sh "$script" "$@"; }
alive() { [ -f "$root/state/$1.pid" ] && kill -0 "$(cat "$root/state/$1.pid")" 2>/dev/null; }
row() { pf list | awk -v id="$1" '$1 == id'; }
starts() { grep -c -- "-- $1\$" "$calls" || :; }

[ -f "$script" ] || fail 'port-forward script missing'
sh -n "$script" || fail 'port-forward syntax'
pf list > /dev/null || fail 'list on empty state failed'

# Add both directions; each spec is saved enabled and its tunnel started.
pf add host1 L 8080 localhost:80 || fail 'add remote->local failed'
pf add host1 R 9090 db:5432 || fail 'add local->remote failed'
[ "$(wc -l < "$specs" | tr -d ' ')" -eq 2 ] || fail 'specs not saved'
alive 1 && alive 2 || fail 'tunnels not running'
grep -q -- '-N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 8080:localhost:80 -- host1$' "$calls" ||
    fail 'remote->local ssh argv'
grep -q -- '-R 9090:db:5432 -- host1$' "$calls" || fail 'local->remote ssh argv'
row 1 | grep -q 'running' && row 1 | grep -q 'remote→local' && row 1 | grep -q '8080' &&
    row 1 | grep -q 'localhost:80' || fail 'list row 1'
row 2 | grep -q 'running' && row 2 | grep -q 'local→remote' && row 2 | grep -q 'db:5432' || fail 'list row 2'

# Validation rejects bad input without touching saved specs.
before=$(cat "$specs")
for args in 'host1 L 0 localhost:80' 'host1 L 70000 localhost:80' 'host1 L abc localhost:80' \
    'host1 X 8081 localhost:80' 'host1 L 8081 localhost' 'host1 L 8081 localhost:0' \
    'host1 L 8081 -evil:80' 'host1 L 8080 localhost:81' 'host1 R 9090 other:1'; do
    # shellcheck disable=SC2086
    if pf add $args 2>/dev/null; then fail "accepted: $args"; fi
done
if pf add -oProxyCommand=evil L 8081 localhost:80 2>/dev/null; then fail 'option-like target accepted'; fi
if pf add 'a b' L 8081 localhost:80 2>/dev/null; then fail 'whitespace target accepted'; fi
if pf add '' L 8081 localhost:80 2>/dev/null; then fail 'empty target accepted'; fi
if pf add host1 L 8081 2>/dev/null; then fail 'missing argument accepted'; fi
[ "$(cat "$specs")" = "$before" ] || fail 'rejected add changed specs'
grep -q -- 'evil' "$calls" && fail 'rejected add reached ssh'

# Stop kills the tunnel and disables restore; start re-enables it.
pid1=$(cat "$root/state/1.pid")
pf stop 1 || fail 'stop failed'
! kill -0 "$pid1" 2>/dev/null || fail 'stop left tunnel running'
row 1 | grep -q 'stopped' || fail 'stopped status'
pf start 1 || fail 'start failed'
alive 1 || fail 'start did not run tunnel'
row 1 | grep -q 'running' || fail 'started status'
if pf start 42 2>/dev/null; then fail 'unknown id started'; fi

# A reused pid that is not ssh is never treated as the tunnel nor killed.
pf stop 1
sleep 300 &
decoy=$!
printf '%s\n' "$decoy" > "$root/decoy.pid"
printf '%s\n' "$decoy" > "$root/state/1.pid"
row 1 | grep -q 'stopped' || fail 'reused pid reported running'
pf stop 1 || fail 'stop with reused pid failed'
kill -0 "$decoy" 2>/dev/null || fail 'stop killed unrelated process'

# Restore starts enabled, not-running forwards only and tolerates failures.
kill "$(cat "$root/state/2.pid")"
sleep 1
FAKE_SSH_FAIL=bad
export FAKE_SSH_FAIL
if pf add bad L 7070 localhost:70 2>/dev/null; then fail 'failing tunnel reported success'; fi
row 3 | grep -q 'failed' || fail 'failure not reported in list'
grep -q 'Connection refused' "$root/state/3.log" || fail 'failure log missing'
starts1=$(starts host1)
HERDR_BIN_PATH=$root/bin/herdr pf restore > /dev/null 2>&1 || fail 'restore with failure did not exit 0'
alive 2 || fail 'restore did not start enabled forward'
[ "$(starts host1)" -eq $((starts1 + 1)) ] || fail 'restore started disabled or running forwards'
grep -q '^notification show' "$toasts" || fail 'restore failure toast missing'
starts1=$(starts host1)
pf restore > /dev/null 2>&1 || fail 'second restore failed'
[ "$(starts host1)" -eq "$starts1" ] || fail 'restore restarted running forward'
unset FAKE_SSH_FAIL

# Remove kills the tunnel and deletes the spec.
pid2=$(cat "$root/state/2.pid")
pf remove 2 || fail 'remove failed'
! kill -0 "$pid2" 2>/dev/null || fail 'remove left tunnel running'
! grep -q '^2	' "$specs" || fail 'remove kept spec'
[ -z "$(row 2)" ] || fail 'removed forward still listed'
if pf remove 2 2>/dev/null; then fail 'double remove accepted'; fi
pf add host2 L 6060 localhost:60 || fail 'add after remove failed'
[ -n "$(row 4)" ] || fail 'ids not stable after remove'

# Corrupt state is the only restore failure.
printf 'garbage\n' >> "$specs"
if pf restore > /dev/null 2>&1; then fail 'corrupt state accepted'; fi
printf 'ok: add, validate, stop, start, remove, restore and failure detection\n'
